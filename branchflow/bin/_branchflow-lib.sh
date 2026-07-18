# shellcheck shell=bash
# ═══════════════════════════════════════════════════════════════════
# _branchflow-lib.sh -- release-train primitives for the branchflow CLI
# ═══════════════════════════════════════════════════════════════════
# Reads the same per-repo .claude-workflows.json as the feature plugins
# and provides the git/version/invariant helpers the orchestrator uses.
#
# Model (see branchflow/README.md):
#   - releaseBranch (main) holds tagged, released versions.
#   - updateBranches map defines semver accumulator lines (patch<minor<major).
#   - Invariant: major ⊇ minor ⊇ patch (content) at all times.
#   - Everything is merge-only + PR-driven; accumulators are never
#     force-pushed, so this coexists with strict branch protection.
#
# All functions read config via bf_load_config (call it once, early).
# ═══════════════════════════════════════════════════════════════════

# Canonical low->high semver order. Cascade always flows up this chain.
BF_LEVEL_ORDER=(patch minor major)

# ── Config ────────────────────────────────────────────────────────
# Sets: BF_CONFIG_FILE BF_RELEASE_BRANCH BF_TAG_PREFIX BF_VERSION_FROM
#       BF_VERSION_FILE BF_CHANGELOG_FILE
#       BF_LEVELS (array, low->high, only levels present in updateBranches)
#       BF_BRANCH_<level> (branch name per present level)
#       BF_HAS_UPDATE_BRANCHES ("true"/"false")
#       BF_SINGLE_TARGET (targetBranch, for the develop model; "" otherwise)
#       BF_MODE ("semver" = updateBranches | "develop" = targetBranch | "none")
bf_load_config() {
  local cfg="${REPO_ROOT}/.claude-workflows.json"
  BF_CONFIG_FILE="$cfg"
  BF_RELEASE_BRANCH="main"
  BF_TAG_PREFIX="v"
  BF_VERSION_FROM="tag"
  BF_VERSION_FILE="none"
  BF_CHANGELOG_FILE=""
  BF_LEVELS=()
  BF_HAS_UPDATE_BRANCHES="false"
  BF_SINGLE_TARGET=""
  BF_MODE="none"

  if [[ -f "$cfg" ]] && jq -e . "$cfg" >/dev/null 2>&1; then
    local v
    v="$(jq -r '.releaseBranch          // empty' "$cfg")"; [[ -n "$v" ]] && BF_RELEASE_BRANCH="$v"
    v="$(jq -r '.targetBranch           // empty' "$cfg")"; [[ -n "$v" ]] && BF_SINGLE_TARGET="$v"
    v="$(jq -r '.release.tagPrefix      // empty' "$cfg")"; [[ -n "$v" ]] && BF_TAG_PREFIX="$v"
    v="$(jq -r '.release.versionFrom    // empty' "$cfg")"; [[ -n "$v" ]] && BF_VERSION_FROM="$v"
    v="$(jq -r '.release.versionFile    // empty' "$cfg")"; [[ -n "$v" ]] && BF_VERSION_FILE="$v"
    v="$(jq -r '.release.changelogFile  // empty' "$cfg")"; [[ -n "$v" ]] && BF_CHANGELOG_FILE="$v"

    # Present levels, in canonical low->high order.
    local lvl branch
    for lvl in "${BF_LEVEL_ORDER[@]}"; do
      branch="$(jq -r --arg l "$lvl" '.updateBranches[$l] // empty' "$cfg")"
      if [[ -n "$branch" ]]; then
        BF_LEVELS+=("$lvl")
        printf -v "BF_BRANCH_${lvl}" '%s' "$branch"
        BF_HAS_UPDATE_BRANCHES="true"
      fi
    done
  fi

  if [[ "$BF_HAS_UPDATE_BRANCHES" == "true" ]]; then
    BF_MODE="semver"
  elif [[ -n "$BF_SINGLE_TARGET" ]]; then
    BF_MODE="develop"
  fi
}

# Echo the branch name for a level (patch|minor|major).
bf_branch_for_level() {
  local ref="BF_BRANCH_$1"
  echo "${!ref:-}"
}

# Echo present levels above the given one (low->high).
bf_higher_levels() {
  local target="$1" seen="false" lvl
  for lvl in "${BF_LEVELS[@]}"; do
    if [[ "$seen" == "true" ]]; then echo "$lvl"; fi
    [[ "$lvl" == "$target" ]] && seen="true"
  done
}

# Echo the level immediately above the given one ("" if none).
bf_next_level() {
  bf_higher_levels "$1" | head -1
}

# Is <name> a known level or accumulator branch? Echo its level or "".
bf_level_of() {
  local q="$1" lvl
  for lvl in "${BF_LEVELS[@]}"; do
    [[ "$q" == "$lvl" || "$q" == "$(bf_branch_for_level "$lvl")" ]] && { echo "$lvl"; return; }
  done
  echo ""
}

# ── Versioning ────────────────────────────────────────────────────
# Highest released version (from tags; falls back to a version file, then 0.0.0).
bf_current_version() {
  local t
  t="$(git tag -l "${BF_TAG_PREFIX}*" --sort=-v:refname 2>/dev/null | head -1)"
  if [[ -n "$t" ]]; then echo "${t#"$BF_TAG_PREFIX"}"; return; fi
  if [[ "$BF_VERSION_FILE" != "none" && -f "$BF_VERSION_FILE" ]]; then
    # Best-effort extract of a semver-looking string from the version file.
    local fv
    fv="$(grep -oE '[0-9]+\.[0-9]+\.[0-9]+' "$BF_VERSION_FILE" 2>/dev/null | head -1)"
    [[ -n "$fv" ]] && { echo "$fv"; return; }
  fi
  echo "0.0.0"
}

# bf_bump_version <version> <level>  ->  bumped version
bf_bump_version() {
  local v="${1#"$BF_TAG_PREFIX"}" level="$2"
  v="${v#v}"; v="${v%%-*}"; v="${v%%+*}"   # strip leading v and pre-release/build
  local M m p
  IFS='.' read -r M m p <<<"$v"
  M="${M:-0}"; m="${m:-0}"; p="${p:-0}"
  case "$level" in
    major) echo "$((M + 1)).0.0" ;;
    minor) echo "${M}.$((m + 1)).0" ;;
    patch) echo "${M}.${m}.$((p + 1))" ;;
    *) return 1 ;;
  esac
}

# ── Git helpers ───────────────────────────────────────────────────
# Count commits reachable from <b> but not <a> (i.e. on b, missing from a).
# Commit-based -- used for informational "pending/behind" display only.
bf_count_ahead() {
  git rev-list --count "$1..$2" 2>/dev/null || echo 0
}

# CONTENT-based containment: how many of <head>'s non-merge commits carry
# changes NOT already present in <upstream> (by patch-id). Zero means
# "<upstream> already contains <head>'s changes." Unlike bf_count_ahead this
# ignores merge commits and recognises cherry-picked/rebased equivalents, so
# per-branch reconcile merges don't create false "ahead" counts.
#   bf_content_ahead <upstream> <head>
bf_content_ahead() {
  git cherry "$1" "$2" 2>/dev/null | grep -c '^+' || true
}

# Fetch a set of branches from origin, forcing the remote-tracking refs to
# update (explicit refspec -- opportunistic updates are version-dependent).
# Ignores failures for branches that don't exist on the remote yet.
bf_fetch() {
  local b
  for b in "$@"; do
    git fetch origin "+refs/heads/${b}:refs/remotes/origin/${b}" 2>/dev/null || true
  done
}

# Does origin/<branch> exist?
bf_remote_has() {
  git show-ref --verify --quiet "refs/remotes/origin/$1"
}

# Invariant check. Echoes one "low->high:N" line per violated pair (a lower
# line has N commits a higher line is missing). Returns 1 if any violation.
# Compares remote refs, so bf_fetch the accumulators first.
bf_invariant_violations() {
  local i j low high lb hb n rc=0
  for ((i = 0; i < ${#BF_LEVELS[@]}; i++)); do
    for ((j = i + 1; j < ${#BF_LEVELS[@]}; j++)); do
      low="${BF_LEVELS[i]}"; high="${BF_LEVELS[j]}"
      lb="$(bf_branch_for_level "$low")"; hb="$(bf_branch_for_level "$high")"
      bf_remote_has "$lb" && bf_remote_has "$hb" || continue
      n="$(bf_content_ahead "origin/${hb}" "origin/${lb}")"
      if [[ "$n" -gt 0 ]]; then echo "${low}->${high}:${n}"; rc=1; fi
    done
  done
  return $rc
}

# Trial-merge <head> into <base> in a throwaway worktree; no side effects.
# Returns 0 if it merges cleanly, 1 on conflict, 2 if the trial couldn't run.
bf_mergeable() {
  local base="$1" head="$2" wt rc
  wt="$(mktemp -d)"
  git worktree add --detach "$wt" "$base" >/dev/null 2>&1 || { rm -rf "$wt"; return 2; }
  ( cd "$wt" && git merge --no-commit --no-ff "$head" >/dev/null 2>&1 ); rc=$?
  ( cd "$wt" && git merge --abort >/dev/null 2>&1 || true )
  git worktree remove --force "$wt" >/dev/null 2>&1 || true
  rm -rf "$wt" 2>/dev/null || true
  return $rc
}

# Echo the open PR number for head->base, or "" if none.
bf_open_pr_number() {
  local head="$1" base="$2"
  gh pr list --state open --head "$head" --base "$base" --json number -q '.[0].number' 2>/dev/null || true
}

# Newest merged release PR (branchflow/release/*) into the release branch.
# Echoes "headRefName" (e.g. branchflow/release/1.5.0) or "".
bf_last_merged_release_head() {
  gh pr list --base "$BF_RELEASE_BRANCH" --state merged \
    --search "head:branchflow/release/ sort:updated-desc" \
    --json headRefName -q '.[0].headRefName' 2>/dev/null || true
}

# Extract the version from a release branch name (branchflow/release/1.5.0 -> 1.5.0).
bf_version_from_release_head() {
  local h="$1"
  echo "${h##*/}"
}
