# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

A Claude Code plugin marketplace (`22a435-workflows`) containing three plugins that orchestrate autonomous multi-stage workflows by launching sequential Claude Code CLI sessions. Each stage gets a fresh context window with full subagent access.

**Why sequential sessions:** Claude Code subagents cannot spawn sub-subagents. Running each stage as its own top-level `claude` invocation gives every skill maximum parallelism.

## Plugins

### issue-workflow
Autonomous issue-to-PR pipeline. Given a GitHub issue number, produces a reviewed, tested, integration-ready PR across a multi-stage pipeline.

- CLI: `work-issue <issue-number> [--effort high|max] [--model <model>] [--resume <stage>]`
- Branch: `claude/<issue-number>`
- Work dir: `./claude-work/<issue-number>/`
- Stages: `setup -> research <-> interview <-> plan -> execute <-> debug <-> verify <-> review <-> integrate -> done`
- Self-loops: execute and debug can signal themselves to continue long work in a fresh session
- Abandon: any post-setup stage can signal `abandon` -- a user-gated stage that verifies the case, asks for explicit approval, then closes out the PR/branch/issue (declining returns to the signaling stage via `.abandon-origin`)
- Hard wall: once execution starts, no returning to pre-execution stages

### deep-review
Comprehensive codebase review with up to 10 parallel sub-reviewers and automated remediation.

- CLI: `deep-review [--effort high|max] [--model <model>] [--resume <stage>] [--session <N>]`
- Branch: `claude/review/<session-number>`
- Work dir: `./claude-reviews/<session-number>/`
- Stages: `setup -> context-building -> interview <-> update-tooling -> [plan-sc-audit -> run-sc-audit] -> plan -> review -> remediation-plan -> remediation -> verify -> integrate -> done`
- Conditional stages: `plan-sc-audit` and `run-sc-audit` only run for Solidity projects with sc-auditor approved during interview

### triage
Backlog consolidation -- the net *consumer* of issues, counterweight to the two net producers above. Reads the open issue set (full comment threads) plus in-code TODOs, closes already-fixed/duplicate issues, and consolidates the rest into a small, loosely-coupled set of well-scoped issues -- each a single-PR "bite" for issue-workflow, with dependent work bundled behind the design decision it hinges on.

- CLI: `triage [--effort high|xhigh|max] [--model <model>] [--resume <stage>] [--session <N>]`
- Branch: `claude/triage/<session-number>`
- Work dir: `./claude-triages/<session-number>/`
- Stages: `setup -> inventory -> reconcile -> cluster -> interview -> consolidate -> verify -> integrate -> done`
- Approval gate: `interview` presents the full plan; no GitHub issue is closed or created until it is approved. GitHub mutations happen only in `consolidate` (and `verify` salvage).

## Repository Structure

```
.claude-plugin/marketplace.json   # Marketplace manifest listing all three plugins
issue-workflow/
  .claude-plugin/plugin.json      # Plugin metadata + version
  bin/work-issue                  # Bash orchestrator (state machine)
  hooks/hooks.json                # PreToolUse hook config
  hooks/check-git-branch.sh       # Prevents push to protected branches
  skills/<stage>/SKILL.md         # One skill prompt per stage
deep-review/
  .claude-plugin/plugin.json
  bin/deep-review                 # Bash orchestrator (state machine)
  hooks/hooks.json
  hooks/check-git-branch.sh
  skills/<stage>/SKILL.md         # Includes plan-sc-audit/ and run-sc-audit/ for sc-auditor integration
triage/
  .claude-plugin/plugin.json
  bin/triage                      # Bash orchestrator (state machine)
  hooks/hooks.json
  hooks/check-git-branch.sh
  skills/<stage>/SKILL.md         # inventory/reconcile/cluster/interview/consolidate/verify/integrate
```

## Architecture

### Orchestrators (`bin/work-issue`, `bin/deep-review`, `bin/triage`)

Pure bash state machines. They:
1. Parse args, validate environment (`gh`, `claude`, `git`, `jq`)
2. Read issue/create session metadata
3. Loop through stages, invoking `claude --model <model> --effort <effort> "/<skill-prefix>:<stage> <arg>"`
4. Handle stage transitions via `.next-stage` signal files written by skills
5. Validate transitions against `ALLOWED_TRANSITIONS` map
6. Enforce loop safety (issue-workflow: 10 per-stage, 40 global max; deep-review/triage: 5 per-stage, 25 global max)

Key orchestrator patterns:
- **`refresh_env()`** -- re-sources PATH from a login shell after stages that install tools
- **Trivial integration** -- if main hasn't diverged, the integrate stage skips Claude entirely and handles it inline in bash
- **Debug origin tracking** -- `issue-workflow` saves which stage triggered debug in `.debug-origin` so debug can return to the correct stage; `.abandon-origin` does the same for the abandon stage (declining an abandon returns to the origin, and only the origin)
- **Local CI pre-ready gate** -- `issue-workflow` and `deep-review` check a committed `.local-ci-state` marker (local CI command + tree-content hash excluding the work dir, written by the verify skill) before `gh pr ready`; stale state re-runs local CI inline or re-enters verify, and the PR stays draft if local CI cannot go green

### Skills (`skills/<stage>/SKILL.md`)

SKILL.md files are prompt templates loaded by Claude Code when the skill is invoked. They use `$0` as the argument placeholder (issue number or session number).

Skill conventions:
- **Document ownership:** Each stage reads prior documents, writes only its own output document. Re-triggered stages append, never overwrite.
- **Subagent write boundary:** Subagents must NOT write to the work directory -- only the parent session writes output documents.
- **Subagent cost optimization:** Information-gathering agents use `model: "sonnet"`. Parent sessions (opus) handle synthesis.
- **Commit format:** `claude-work(<stage>): <desc> [#<issue>]` (issue-workflow), `claude-review(<stage>): <desc> [session #<N>]` (deep-review), or `claude-triage(<stage>): <desc> [session #<N>]` (triage)

### Hooks

Both plugins share the same hook: a `PreToolUse` hook on `Bash` that blocks `git push` to protected branches (main, master, production).

### Stage Transition Signals

Skills write a stage name to `<work-dir>/.next-stage` to request non-default transitions. The orchestrator reads, validates against `ALLOWED_TRANSITIONS`, and follows or falls back to `DEFAULT_NEXT`.

## Editing Skills

When editing SKILL.md files:
- `$0` is the argument passed to the skill (issue number or session number) -- do not change this convention
- The YAML frontmatter (`name`, `description`, `disable-model-invocation`, `allowed-tools`) is parsed by Claude Code's plugin system
- `disable-model-invocation: true` means the skill cannot be auto-triggered -- it must be explicitly invoked
- Keep the "Workflow Context" section consistent across skills within a plugin (document ownership rules, commit format, subagent boundaries)

## Editing Orchestrators

When modifying the bash orchestrators:
- `ALLOWED_TRANSITIONS` and `DEFAULT_NEXT` must stay in sync -- every stage in DEFAULT_NEXT must be a valid transition in ALLOWED_TRANSITIONS
- The `ALL_STAGES` array is used for `--resume` validation
- `STAGE_SKILL`, `STAGE_DOC`, `STAGE_MODEL`, `STAGE_EFFORT` maps must all cover the same set of stages
- Environment variable overrides follow the pattern `<PLUGIN>_MODEL_<STAGE>` (with hyphens converted to underscores for env var names)

## Prerequisites

- `gh` (GitHub CLI) -- authenticated with repo access
- `claude` (Claude Code CLI) -- authenticated
- `git` and `jq` in PATH

## Versioning

Both plugins follow [Semantic Versioning](https://semver.org/). When making changes to either plugin:

- **Always bump the patch version** in that plugin's `.claude-plugin/plugin.json`
- If the change alters the stage machine topology, public interfaces, or orchestrator behavior, it may warrant a minor or major bump -- ask the user if the level of change is unclear
- Bump only the plugin(s) that were actually modified
