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
| **execute** | sonnet[1m] | Implement the plan with parallel subagents |
| **debug** | opus[1m] | Root cause analysis and fix for escalated problems |
| **verify** | sonnet[1m] | Full verification suite (component + integration + tests) |
| **review** | sonnet[1m] | Code quality, security, and documentation review |
| **integrate** | opus[1m] | Rebase onto main; resolve conflicts |

### State Machine

**Hard wall:** Once execution starts, no returning to pre-execution stages (research, interview, plan).

**Stage transitions:** Skills write a stage name to `./claude-work/<issue>/.next-stage` to request non-default transitions. The orchestrator validates and follows the signal.

## Configuration

All configuration is via environment variables.

| Variable | Purpose | Default |
|----------|---------|---------|
| `ISSUE_WORKFLOW_MODEL` | Override model for all stages | per-stage defaults |
| `ISSUE_WORKFLOW_MODEL_<STAGE>` | Override model for one stage | per-stage default |
| `ISSUE_WORKFLOW_EFFORT_<STAGE>` | Override effort for one stage | per-stage default |
| `ISSUE_WORKFLOW_SKILL_PREFIX` | Skill name prefix for conflicts | `issue-workflow:` |
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
| verify | `Verify.md` |
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
