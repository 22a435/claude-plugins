# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

A Claude Code plugin marketplace (`22a435-workflows`) containing three plugins that orchestrate autonomous multi-stage workflows by launching sequential Claude Code CLI sessions. Each stage gets a fresh context window with full subagent access.

**Why sequential sessions:** Claude Code subagents cannot spawn sub-subagents. Running each stage as its own top-level `claude` invocation gives every skill maximum parallelism.

## Plugins

### issue-workflow
Autonomous issue-to-PR pipeline. Given a GitHub issue number, produces a reviewed, tested, integration-ready PR across 8 stages.

- CLI: `work-issue <issue-number> [--effort high|max] [--model <model>] [--resume <stage>] [--target <branch>] [--bump major|minor|patch] [--onto <branch|PR#>]`
- Branch: `<branchPrefix>/<issue-number>` (default `claude/<issue-number>`)
- Work dir: `./claude-work/<issue-number>/`
- Target/base branch is configurable (see Branching below); `--bump`/`--onto` route to semver update branches / stack onto an open PR
- Stages: `setup -> research <-> interview <-> plan -> execute <-> debug <-> verify <-> review <-> integrate -> done`
- Hard wall: once execution starts, no returning to pre-execution stages

### deep-review
Comprehensive codebase review with up to 10 parallel sub-reviewers and automated remediation.

- CLI: `deep-review [--effort high|max] [--model <model>] [--resume <stage>] [--session <N>] [--target <branch>]`
- Branch: `<branchPrefix>/review/<session-number>` (default `claude/review/<session-number>`)
- Work dir: `./claude-reviews/<session-number>/`
- Stages: `setup -> context-building -> interview <-> update-tooling -> [plan-sc-audit -> run-sc-audit] -> plan -> review -> remediation-plan -> remediation -> verify -> integrate -> done`
- Conditional stages: `plan-sc-audit` and `run-sc-audit` only run for Solidity projects with sc-auditor approved during interview

### triage
Backlog consolidation -- the net *consumer* of issues, counterweight to the two net producers above. Reads the open issue set (full comment threads) plus in-code TODOs, closes already-fixed/duplicate issues, and consolidates the rest into a small, loosely-coupled set of well-scoped issues -- each a single-PR "bite" for issue-workflow, with dependent work bundled behind the design decision it hinges on.

- CLI: `triage [--effort high|xhigh|max] [--model <model>] [--resume <stage>] [--session <N>] [--target <branch>]`
- Branch: `<branchPrefix>/triage/<session-number>` (default `claude/triage/<session-number>`)
- Work dir: `./claude-triages/<session-number>/`
- Stages: `setup -> inventory -> reconcile -> cluster -> interview -> consolidate -> verify -> integrate -> done`
- Approval gate: `interview` presents the full plan; no GitHub issue is closed or created until it is approved. GitHub mutations happen only in `consolidate` (and `verify` salvage).

## Repository Structure

```
.claude-plugin/marketplace.json   # Marketplace manifest listing all three plugins
issue-workflow/
  .claude-plugin/plugin.json      # Plugin metadata + version
  bin/work-issue                  # Bash orchestrator (state machine)
  bin/_branch-lib.sh              # Base/target branch resolver (triplicated, byte-identical)
  hooks/hooks.json                # PreToolUse hook config
  hooks/check-git-branch.sh       # Prevents push to protected branches (config-aware)
  skills/<stage>/SKILL.md         # One skill prompt per stage
deep-review/
  .claude-plugin/plugin.json
  bin/deep-review                 # Bash orchestrator (state machine)
  bin/_branch-lib.sh              # Base/target branch resolver (byte-identical copy)
  hooks/hooks.json
  hooks/check-git-branch.sh
  skills/<stage>/SKILL.md         # Includes plan-sc-audit/ and run-sc-audit/ for sc-auditor integration
triage/
  .claude-plugin/plugin.json
  bin/triage                      # Bash orchestrator (state machine)
  bin/_branch-lib.sh              # Base/target branch resolver (byte-identical copy)
  hooks/hooks.json
  hooks/check-git-branch.sh
  skills/<stage>/SKILL.md         # inventory/reconcile/cluster/interview/consolidate/verify/integrate
```

A per-repo `.claude-workflows.json` (read from the target repo root, not this repo) configures the base/target branch, update-branch map, feature-branch prefix, and protected branches -- see Branching under Architecture.

## Architecture

### Orchestrators (`bin/work-issue`, `bin/deep-review`, `bin/triage`)

Pure bash state machines. They:
1. Parse args, validate environment (`gh`, `claude`, `git`, `jq`)
2. Read issue/create session metadata
3. Loop through stages, invoking `claude --model <model> --effort <effort> "/<skill-prefix>:<stage> <arg>"`
4. Handle stage transitions via `.next-stage` signal files written by skills
5. Validate transitions against `ALLOWED_TRANSITIONS` map
6. Enforce loop safety (5 per-stage, 25 global max)

Key orchestrator patterns:
- **`refresh_env()`** -- re-sources PATH from a login shell after stages that install tools
- **Trivial integration** -- if the configured target branch hasn't diverged, the integrate stage skips Claude entirely and handles it inline in bash
- **Debug origin tracking** -- `issue-workflow` saves which stage triggered debug in `.debug-origin` so debug can return to the correct stage
- **Local CI pre-ready gate** -- `issue-workflow` and `deep-review` check a committed `.local-ci-state` marker (local CI command + tree-content hash excluding the work dir, written by the verify skill) before `gh pr ready`; stale state re-runs local CI inline or re-enters verify, and the PR stays draft if local CI cannot go green

### Skills (`skills/<stage>/SKILL.md`)

SKILL.md files are prompt templates loaded by Claude Code when the skill is invoked. They use `$0` as the argument placeholder (issue number or session number).

Skill conventions:
- **Document ownership:** Each stage reads prior documents, writes only its own output document. Re-triggered stages append, never overwrite.
- **Subagent write boundary:** Subagents must NOT write to the work directory -- only the parent session writes output documents.
- **Subagent cost optimization:** Information-gathering agents use `model: "sonnet"`. Parent sessions (opus) handle synthesis.
- **Commit format:** `claude-work(<stage>): <desc> [#<issue>]` (issue-workflow), `claude-review(<stage>): <desc> [session #<N>]` (deep-review), or `claude-triage(<stage>): <desc> [session #<N>]` (triage)

### Hooks

All three plugins share the same hook: a `PreToolUse` hook on `Bash` that blocks `git push` to protected branches. The list defaults to `main master production` but is overridden by `protectedBranches` in the target repo's `.claude-workflows.json` (see Branching below) -- repos using develop/staging or update branches should list those so feature sessions can never push directly to a merge target.

### Branching (configurable base/target)

By default every plugin cuts a feature branch from `origin/main` and opens its PR against `main`. A per-repo `.claude-workflows.json` at the **target repo root** (read via `jq`; all keys optional) changes this without touching the plugins:

```jsonc
{
  "targetBranch": "develop",              // default PR base (omitted => "main")
  "branchPrefix": "claude",               // feature-branch namespace (omitted => "claude")
  "defaultBump": "patch",                 // used only with updateBranches
  "updateBranches": { "major": "release/major", "minor": "release/minor", "patch": "release/patch" },
  "protectedBranches": ["main", "release/major", "release/minor", "release/patch"]
}
```

(Comments above are illustrative; the actual file must be strict JSON -- `jq` rejects `//` comments, and a malformed config is silently ignored, falling back to `main`.)

- **Resolution lives in `bin/_branch-lib.sh`** -- a byte-identical copy in each plugin's `bin/` (no shared lib ships across independently-installed plugins; keep the three copies in sync, same as the three `check-git-branch.sh`). `resolve_branches()` exports the resolved values; `write_branch_meta`/`load_branch_meta` persist them to `<work-dir>/.branch-meta.json` for `--resume`.
- **Exported vars the skills read:** `WF_TARGET` (PR base), `WF_BASE_REF` (`origin/$WF_TARGET`; fetch/diff/rebase against this), `WF_BRANCH_PREFIX`, and for stacking `WF_STACK_PARENT_PR` / `WF_STACK_FINAL_TARGET`. Skills resolve these once (env var > `.branch-meta.json` > `origin/main`) and then never re-type `origin/main`.
- **Precedence:** `--onto` (stacking) > `--target` > `<PLUGIN>_TARGET_BRANCH` env > `--bump`/`semver:*` label > config `targetBranch` > `main`.
- **Bump routing and stacking are issue-workflow only** (the plugin that produces sized feature work). `deep-review` and `triage` take a single configured target (`--target` / `<PLUGIN>_TARGET_BRANCH` / config), no `--bump` or `--onto`.
- **Stacking (`--onto <branch|PR#>`):** cut from and target a parent feature branch so dependent PRs stack and merge into the update branch once the whole feature lands. When the parent PR merges, GitHub retargets the child onto the final target; the integrate/review skills and the orchestrator's inline trivial-integration path detect the merged parent and follow it.
- **Out of scope:** promoting an update branch into `main` with a version bump (the workflows only route feature PRs to the right update branch).
- **Backwards compatible:** with no config and no new flags, behavior is byte-for-byte the trunk-based "branch from origin/main, PR to main" model.

### Stage Transition Signals

Skills write a stage name to `<work-dir>/.next-stage` to request non-default transitions. The orchestrator reads, validates against `ALLOWED_TRANSITIONS`, and follows or falls back to `DEFAULT_NEXT`.

## Editing Skills

When editing SKILL.md files:
- `$0` is the argument passed to the skill (issue number or session number) -- do not change this convention
- The YAML frontmatter (`name`, `description`, `disable-model-invocation`, `allowed-tools`) is parsed by Claude Code's plugin system
- `disable-model-invocation: true` means the skill cannot be auto-triggered -- it must be explicitly invoked
- Keep the "Workflow Context" section consistent across skills within a plugin (document ownership rules, commit format, subagent boundaries)
- **Never hardcode `origin/main`, `--base main`, or the `claude/` branch prefix.** Branch-touching skills resolve the target once in a "Step 0" (env `WF_TARGET`/`WF_BASE_REF` > `.branch-meta.json` > `origin/main`) and use those vars; `gh pr` calls target the current branch (`gh pr comment` with no arg, `--head "$(git branch --show-current)"`, `git push ... origin HEAD`) so a custom `branchPrefix` still works

## Editing Orchestrators

When modifying the bash orchestrators:
- `ALLOWED_TRANSITIONS` and `DEFAULT_NEXT` must stay in sync -- every stage in DEFAULT_NEXT must be a valid transition in ALLOWED_TRANSITIONS
- The `ALL_STAGES` array is used for `--resume` validation
- `STAGE_SKILL`, `STAGE_DOC`, `STAGE_MODEL`, `STAGE_EFFORT` maps must all cover the same set of stages
- Environment variable overrides follow the pattern `<PLUGIN>_MODEL_<STAGE>` (with hyphens converted to underscores for env var names)
- Base/target branch handling goes through `resolve_branches` (sourced from `bin/_branch-lib.sh`): source it after `cd "$REPO_ROOT"`, set `WF_TARGET_OVERRIDE`/`WF_PREFIX_OVERRIDE` from the plugin's env vars first, then `write_branch_meta` at setup and `load_branch_meta` on `--resume`. Use `$WF_TARGET`/`$WF_BASE_REF` instead of literal `main`/`origin/main`

## Prerequisites

- `gh` (GitHub CLI) -- authenticated with repo access
- `claude` (Claude Code CLI) -- authenticated
- `git` and `jq` in PATH

## Versioning

Both plugins follow [Semantic Versioning](https://semver.org/). When making changes to either plugin:

- **Always bump the patch version** in that plugin's `.claude-plugin/plugin.json`
- If the change alters the stage machine topology, public interfaces, or orchestrator behavior, it may warrant a minor or major bump -- ask the user if the level of change is unclear
- Bump only the plugin(s) that were actually modified
