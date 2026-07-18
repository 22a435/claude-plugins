# issue-workflow

A Claude Code plugin that orchestrates autonomous issue-to-PR workflows through an 8-stage state machine. Given a GitHub issue number, it produces a reviewed, tested, integration-ready pull request.

## How It Works

The `work-issue` CLI launches sequential Claude Code sessions, one per stage. Each stage loads a dedicated skill prompt and gets a fresh context window with full access to parallel subagents. This design solves a key constraint: Claude Code subagents cannot spawn sub-subagents, so running each stage as its own top-level session gives every skill maximum parallelism.

## Prerequisites

### GitHub CLI

The workflow uses `gh` extensively. Install and authenticate:

```bash
# Install gh: https://github.com/cli/cli#installation

# Authenticate with a personal access token (PAT) or browser login
gh auth login
```

**Required PAT scopes** (if using a token instead of browser auth):
- `repo` -- full repository access (read issues, create branches, open PRs, push code)
- `read:org` -- read org membership (needed for org-owned repos)
- `project` -- project board access (optional, for project-linked issues)

The workflow uses these `gh` commands: `gh issue view`, `gh repo view`, `gh pr create`, `gh pr comment`, `gh pr ready`.

### Claude Code CLI

Install Claude Code: https://claude.ai/install

Authenticate: `claude auth login`

### Other tools

The orchestrator also requires `git` and `jq` in PATH.

## Quick Start

```bash
# Run the full workflow for issue #42
work-issue 42

# Use a specific model for all stages
work-issue 42 --model sonnet

# Resume from a specific stage
work-issue 42 --resume verify

# Override effort level
work-issue 42 --effort max

# Merge into develop instead of main (one-off; or set it in .claude-workflows.json)
work-issue 42 --target develop

# Route to the minor semver update branch (needs updateBranches in config)
work-issue 42 --bump minor

# Stack issue #43 on top of issue #42's still-open PR (sequential PRs)
work-issue 43 --onto 42
```

## Stages

The workflow runs as a **state machine**, not a rigid linear sequence:

```
setup -> research <-> interview <-> plan -> execute <-> debug <-> verify <-> review <-> integrate -> done
```

| Stage | Model (default) | Purpose |
|-------|----------------|---------|
| **setup** | haiku | Create branch, work folder, Issue.md; run repo setup scripts |
| **research** | opus[1m] | Deep codebase, web, and library documentation investigation |
| **interview** | opus[1m] | Resolve open questions with user input |
| **plan** | opus[1m] | Draft implementation plan; requires user approval; opens draft PR |
| **execute** | opus[1m] | Implement the plan with parallel subagents |
| **debug** | opus[1m] | Root cause analysis and fix for escalated problems |
| **verify** | opus[1m] | Full verification suite (component + integration + tests + local CI script) |
| **review** | opus[1m] | Code quality, security, and documentation review |
| **integrate** | opus[1m] | Rebase onto the target branch; resolve conflicts |

### State Machine

**Hard wall:** Once execution starts, no returning to pre-execution stages (research, interview, plan).

**Stage transitions:** Skills write a stage name to `./claude-work/<issue>/.next-stage` to request non-default transitions. The orchestrator validates and follows the signal.

### Local CI Gate

The PR stays a draft until local CI is confirmed green against the final code state. The verify stage discovers the repo's local CI script (documented command in CLAUDE.md/README, `scripts/ci*`, `make ci`, or `npm run ci`), runs it, and records the command plus a tree-content hash (excluding `claude-work/`) in `.local-ci-state`. Just before `gh pr ready`, the orchestrator re-checks that hash: if code changed since the last green run, it re-runs local CI inline; if red, it re-enters the workflow at verify (max 2 re-entries), and if local CI still cannot go green the PR is left as a draft. This keeps red runs off GitHub Actions, which only fires once the PR is marked ready. Set `ISSUE_WORKFLOW_SKIP_CI_GATE=1` to bypass.

## Branching

By default a run cuts a feature branch from `origin/main` and opens its PR against `main`. To target a different branch -- a `develop`/staging branch, or per-change semver **update branches** -- drop a `.claude-workflows.json` at the **target repo root** (all keys optional):

```jsonc
{
  "targetBranch": "develop",              // default PR base (omitted => "main")
  "branchPrefix": "claude",               // feature-branch namespace (omitted => "claude")
  "defaultBump": "patch",                 // used only with updateBranches
  "updateBranches": {                     // route by change size
    "major": "release/major",
    "minor": "release/minor",
    "patch": "release/patch"
  },
  "protectedBranches": ["main", "release/major", "release/minor", "release/patch"]
}
```

> The comments above are illustrative -- the real file must be plain JSON (no `//` comments). A malformed config is ignored and the plugin falls back to `main`.

- **`--bump major|minor|patch`** selects the matching branch from `updateBranches`. With no flag, a single `semver:<level>` label on the issue is used; otherwise `defaultBump`.
- **`--target <branch>`** overrides everything for a one-off (also `ISSUE_WORKFLOW_TARGET_BRANCH`).
- **`--onto <branch|PR#>`** stacks this work onto an existing feature branch / open PR: it cuts from and targets that branch so dependent PRs stack, and the whole chain lands on the update branch once the feature is complete. The PR body is marked "stacked" and uses `Part of #N` instead of `Closes #N`. When the parent PR merges, the child follows GitHub's retarget onto the final target.
- Resolution precedence: `--onto` > `--target` > `ISSUE_WORKFLOW_TARGET_BRANCH` > `--bump`/`semver:*` label > config `targetBranch` > `main`. The resolved target is recorded in `.branch-meta.json` so `--resume` reuses it.
- With **no config and no flags**, behavior is byte-for-byte the classic "branch from origin/main, PR to main" model.

## Configuration

Configuration is via a per-repo `.claude-workflows.json` (branching, above) plus environment variables:

| Variable | Purpose | Default |
|----------|---------|---------|
| `ISSUE_WORKFLOW_MODEL` | Override model for all stages | per-stage defaults |
| `ISSUE_WORKFLOW_MODEL_<STAGE>` | Override model for one stage | per-stage default |
| `ISSUE_WORKFLOW_EFFORT_<STAGE>` | Override effort for one stage | per-stage default |
| `ISSUE_WORKFLOW_SKILL_PREFIX` | Skill name prefix for conflicts | `issue-workflow:` |
| `ISSUE_WORKFLOW_TARGET_BRANCH` | Merge target override (like `--target`) | `main` / config |
| `ISSUE_WORKFLOW_BRANCH_PREFIX` | Feature-branch prefix | `claude` / config |
| `ISSUE_WORKFLOW_SKIP_CI_GATE` | Skip the pre-ready local CI gate | unset |
| `CLAUDE_CODE_EFFORT_LEVEL` | Global effort override | `xhigh` |

## Work Directory

Each issue gets `./claude-work/<issue-number>/` with one document per stage:

| Stage | Document |
|-------|----------|
| setup | `Issue.md` |
| research | `Research.md` |
| interview | `Interview.md` |
| plan | `Plan.md` |
| execute | `Execute.md` |
| debug | `Debug.md` |
| verify | `Verify.md`, `.local-ci-state` (local CI command + code hash, read by the pre-ready gate) |
| review | `Review.md` |
| integrate | `Integration.md` |

## Document Ownership

- Each skill may **read** any prior document but must only **write** to its own
- Re-triggered skills **append** new sections rather than rewriting
- In-place edits marked: `> [IN-PLACE EDIT during <stage> phase]: <reason>`

## Commits

Format: `claude-work(<stage>): <brief description> [#<issue>]`

## Loop Safety

- **5 runs maximum per stage** (prompts for confirmation after 5)
- **25 total stage executions** (hard abort)

## License

MIT
