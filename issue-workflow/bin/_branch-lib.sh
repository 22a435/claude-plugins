# shellcheck shell=bash
# ═══════════════════════════════════════════════════════════════════
# _branch-lib.sh -- shared base/target branch resolution
# ═══════════════════════════════════════════════════════════════════
# Sourced by the orchestrators (work-issue, deep-review, triage) to
# resolve which branch a run cuts from and merges into, so the plugins
# work for repos that use develop/staging targets, semver "update
# branches" (major/minor/patch), and stacked feature branches -- not
# just trunk-based "branch from main, PR to main".
#
# THIS FILE IS TRIPLICATED, one byte-identical copy per plugin's bin/.
# Keep the three copies identical (a diff-based CI check enforces this,
# the same discipline hooks/check-git-branch.sh already relies on).
#
# Per-repo config lives at <repo-root>/.claude-workflows.json (read from
# the target repo, never the plugin repo). All keys optional; absence of
# the file -> classic "main" behavior, byte-for-byte.
#
# INPUTS (globals, all optional -- read defensively with :- so a plugin
# that never sets one is fine):
#   REPO_ROOT            repo root (always set by the orchestrator)
#   CLI_TARGET           value of --target ("")
#   CLI_BUMP             value of --bump   ("")   [issue-workflow only]
#   CLI_ONTO             value of --onto   ("")   [issue-workflow only]
#   WF_TARGET_OVERRIDE   <PLUGIN>_TARGET_BRANCH env override ("")
#   WF_PREFIX_OVERRIDE   <PLUGIN>_BRANCH_PREFIX env override ("")
#   WF_LABEL_BUMP        semver:* issue label bump ("") [issue-workflow]
#
# OUTPUTS (exported globals):
#   WF_TARGET             branch the PR merges into (gh pr create --base)
#   WF_BASE_REF           remote ref to fetch/cut-from/diff/rebase
#                         (origin/$WF_TARGET), or origin/<parent> stacked
#   WF_BRANCH_PREFIX      feature-branch namespace (default "claude")
#   WF_BUMP               resolved bump level ("" when not bump-driven)
#   WF_STACK_PARENT_PR    parent PR number when stacking ("")
#   WF_STACK_FINAL_TARGET update branch the stack ultimately lands on ("")
#   WF_CONFIG_FILE        path to .claude-workflows.json
# ═══════════════════════════════════════════════════════════════════

resolve_branches() {
  local cfg="${REPO_ROOT}/.claude-workflows.json"
  WF_CONFIG_FILE="$cfg"

  local cfg_target="" cfg_prefix="" cfg_default_bump="" has_update="false"
  if [[ -f "$cfg" ]] && jq -e . "$cfg" >/dev/null 2>&1; then
    cfg_target="$(jq -r '.targetBranch // empty' "$cfg")"
    cfg_prefix="$(jq -r '.branchPrefix  // empty' "$cfg")"
    cfg_default_bump="$(jq -r '.defaultBump // empty' "$cfg")"
    if jq -e '.updateBranches | objects | (has("major") or has("minor") or has("patch"))' \
         "$cfg" >/dev/null 2>&1; then
      has_update="true"
    fi
  fi

  # Feature-branch namespace: env override > config > "claude".
  WF_BRANCH_PREFIX="${WF_PREFIX_OVERRIDE:-${cfg_prefix:-claude}}"

  # Reset stacking / bump outputs.
  WF_BUMP=""
  WF_STACK_PARENT_PR=""
  WF_STACK_FINAL_TARGET=""

  # ── Resolve the normal (non-stack) target ────────────────────────
  # Precedence: --target > env override > bump map > config target > main.
  local normal_target=""
  if [[ -n "${CLI_TARGET:-}" ]]; then
    normal_target="$CLI_TARGET"
  elif [[ -n "${WF_TARGET_OVERRIDE:-}" ]]; then
    normal_target="$WF_TARGET_OVERRIDE"
  elif [[ -n "${CLI_BUMP:-}" || -n "${WF_LABEL_BUMP:-}" || "$has_update" == "true" ]]; then
    # Bump-driven selection. --bump beats a semver:* label beats defaultBump.
    local bump="${CLI_BUMP:-${WF_LABEL_BUMP:-${cfg_default_bump:-patch}}}"
    if [[ -n "${CLI_BUMP:-}" && -n "${WF_LABEL_BUMP:-}" && "$CLI_BUMP" != "$WF_LABEL_BUMP" ]]; then
      echo "[branch] WARNING: --bump ${CLI_BUMP} overrides issue label semver:${WF_LABEL_BUMP}." >&2
    fi
    WF_BUMP="$bump"
    local mapped=""
    if [[ "$has_update" == "true" ]]; then
      mapped="$(jq -r --arg b "$bump" '.updateBranches[$b] // empty' "$cfg" 2>/dev/null)"
    fi
    if [[ -n "$mapped" ]]; then
      normal_target="$mapped"
    else
      # No map (or missing key): a bump with nowhere to route falls back
      # to the configured target, then main. Bump becomes a harmless no-op.
      normal_target="${cfg_target:-main}"
    fi
  elif [[ -n "$cfg_target" ]]; then
    normal_target="$cfg_target"
  else
    normal_target="main"
  fi

  # ── Stacking: --onto cuts from / targets a parent feature branch ──
  if [[ -n "${CLI_ONTO:-}" ]]; then
    local parent="$CLI_ONTO"
    if [[ "$CLI_ONTO" =~ ^[0-9]+$ ]]; then
      local head
      head="$(gh pr view "$CLI_ONTO" --json headRefName -q .headRefName 2>/dev/null)"
      if [[ -z "$head" ]]; then
        echo "[branch] ERROR: --onto ${CLI_ONTO}: could not resolve the PR's head branch." >&2
        return 1
      fi
      parent="$head"
      WF_STACK_PARENT_PR="$CLI_ONTO"
    else
      # Branch name given; look up its open PR number (for retarget tracking).
      WF_STACK_PARENT_PR="$(gh pr view "$parent" --json number -q .number 2>/dev/null || true)"
    fi
    WF_TARGET="$parent"
    WF_STACK_FINAL_TARGET="$normal_target"
  else
    WF_TARGET="$normal_target"
  fi

  WF_BASE_REF="origin/${WF_TARGET}"

  export WF_TARGET WF_BASE_REF WF_BRANCH_PREFIX WF_BUMP \
         WF_STACK_PARENT_PR WF_STACK_FINAL_TARGET WF_CONFIG_FILE
}

write_branch_meta() {
  # Persist the resolved branching decision so --resume reuses the same
  # base even if flags are omitted or the config changes. Lives under the
  # work dir (excluded from the local-CI tree hash, like .local-ci-state).
  local dir="$1"
  cat > "${dir}/.branch-meta.json" <<META_EOF
{
  "wfTarget": "${WF_TARGET}",
  "wfBaseRef": "${WF_BASE_REF}",
  "branchPrefix": "${WF_BRANCH_PREFIX}",
  "bump": "${WF_BUMP}",
  "stackParentPR": "${WF_STACK_PARENT_PR}",
  "stackFinalTarget": "${WF_STACK_FINAL_TARGET}"
}
META_EOF
}

load_branch_meta() {
  # Restore resolved branch values recorded at setup (used on --resume).
  # Returns 0 if it loaded, 1 if there was nothing usable to load.
  local dir="$1"
  local meta="${dir}/.branch-meta.json"
  [[ -f "$meta" ]] || return 1
  jq -e . "$meta" >/dev/null 2>&1 || return 1

  local m_target
  m_target="$(jq -r '.wfTarget // empty' "$meta")"
  [[ -z "$m_target" ]] && return 1

  if [[ -n "${CLI_TARGET:-}" && "$CLI_TARGET" != "$m_target" ]]; then
    echo "[branch] WARNING: --target ${CLI_TARGET} ignored on resume; using recorded target ${m_target}." >&2
  fi

  WF_TARGET="$m_target"
  WF_BASE_REF="$(jq -r '.wfBaseRef // empty' "$meta")"
  [[ -z "$WF_BASE_REF" ]] && WF_BASE_REF="origin/${WF_TARGET}"
  local m_prefix
  m_prefix="$(jq -r '.branchPrefix // empty' "$meta")"
  [[ -n "$m_prefix" ]] && WF_BRANCH_PREFIX="$m_prefix"
  WF_BUMP="$(jq -r '.bump // empty' "$meta")"
  WF_STACK_PARENT_PR="$(jq -r '.stackParentPR // empty' "$meta")"
  WF_STACK_FINAL_TARGET="$(jq -r '.stackFinalTarget // empty' "$meta")"

  export WF_TARGET WF_BASE_REF WF_BRANCH_PREFIX WF_BUMP \
         WF_STACK_PARENT_PR WF_STACK_FINAL_TARGET
  echo "[branch] Resumed with recorded target '${WF_TARGET}' (base ${WF_BASE_REF})." >&2
  return 0
}
