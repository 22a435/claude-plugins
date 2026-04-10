# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

A Claude Code plugin marketplace (`22a435-workflows`) containing two plugins that orchestrate autonomous multi-stage workflows by launching sequential Claude Code CLI sessions. Each stage gets a fresh context window with full subagent access.

**Why sequential sessions:** Claude Code subagents cannot spawn sub-subagents. Running each stage as its own top-level `claude` invocation gives every skill maximum parallelism.

## Plugins

### issue-workflow
Autonomous issue-to-PR pipeline. Given a GitHub issue number, produces a reviewed, tested, integration-ready PR across 8 stages.

- CLI: `work-issue <issue-number> [--effort high|max] [--model <model>] [--resume <stage>]`
- Branch: `claude/<issue-number>`
- Work dir: `./claude-work/<issue-number>/`
- Stages: `setup -> research <-> interview <-> plan -> execute <-> debug <-> verify <-> review <-> integrate -> done`
- Hard wall: once execution starts, no returning to pre-execution stages

### deep-review
Comprehensive codebase review with up to 10 parallel sub-reviewers and automated remediation.

- CLI: `deep-review [--effort high|max] [--model <model>] [--resume <stage>] [--session <N>]`
- Branch: `claude/review/<session-number>`
- Work dir: `./claude-reviews/<session-number>/`
- Stages: `setup -> context-building -> interview <-> update-tooling -> [plan-sc-audit -> run-sc-audit] -> plan -> review -> remediation-plan -> remediation -> verify -> integrate -> done`
- Conditional stages: `plan-sc-audit` and `run-sc-audit` only run for Solidity projects with sc-auditor approved during interview

## Repository Structure

```
.claude-plugin/marketplace.json   # Marketplace manifest listing both plugins
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
```

## Architecture

### Orchestrators (`bin/work-issue`, `bin/deep-review`)

Pure bash state machines. They:
1. Parse args, validate environment (`gh`, `claude`, `git`, `jq`)
2. Read issue/create session metadata
3. Loop through stages, invoking `claude --model <model> --effort <effort> "/<skill-prefix>:<stage> <arg>"`
4. Handle stage transitions via `.next-stage` signal files written by skills
5. Validate transitions against `ALLOWED_TRANSITIONS` map
6. Enforce loop safety (5 per-stage, 25 global max)

Key orchestrator patterns:
- **`refresh_env()`** -- re-sources PATH from a login shell after stages that install tools
- **Trivial integration** -- if main hasn't diverged, the integrate stage skips Claude entirely and handles it inline in bash
- **Debug origin tracking** -- `issue-workflow` saves which stage triggered debug in `.debug-origin` so debug can return to the correct stage

### Skills (`skills/<stage>/SKILL.md`)

SKILL.md files are prompt templates loaded by Claude Code when the skill is invoked. They use `$0` as the argument placeholder (issue number or session number).

Skill conventions:
- **Document ownership:** Each stage reads prior documents, writes only its own output document. Re-triggered stages append, never overwrite.
- **Subagent write boundary:** Subagents must NOT write to the work directory -- only the parent session writes output documents.
- **Subagent cost optimization:** Information-gathering agents use `model: "sonnet"`. Parent sessions (opus) handle synthesis.
- **Commit format:** `claude-work(<stage>): <desc> [#<issue>]` (issue-workflow) or `claude-review(<stage>): <desc> [session #<N>]` (deep-review)

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
