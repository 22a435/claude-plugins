# deep-review

A Claude Code plugin that orchestrates comprehensive codebase reviews through a 7-stage workflow with up to 10 parallel sub-reviewers and automated remediation.

## How It Works

The `deep-review` CLI launches sequential Claude Code sessions, one per stage. Unlike issue-workflow (which reviews changes relative to a branch), deep-review examines the **entire codebase** -- architecture, security, code quality, documentation, dependencies, and more.

The review stage is the core: it launches up to 10 specialized sub-reviewer agents in parallel, each analyzing the codebase from a different perspective. An opus-level parent session synthesizes all findings into a comprehensive review document. The remediation stage then applies approved fixes and creates GitHub issues for complex items.

## Prerequisites

- **GitHub CLI** (`gh`) -- authenticated with repo access
- **Claude Code CLI** (`claude`) -- authenticated
- **git** and **jq** in PATH

## Installation

```bash
# Add the marketplace (if not already added)
claude plugin marketplace add 22a435/issue-workflow

# Install the deep-review plugin
claude plugin install 22a435-workflows@deep-review --scope user
```

### Setting up the CLI command

```bash
# Option A: symlink
PLUGIN_PATH="$(find ~/.claude -path '*/deep-review/bin/deep-review' 2>/dev/null | head -1)"
sudo ln -sf "$PLUGIN_PATH" /usr/local/bin/deep-review

# Option B: shell alias
alias deep-review='bash ~/.claude/plugins/marketplaces/22a435-workflows/deep-review/bin/deep-review'
```

## Quick Start

```bash
# Start a new review session
deep-review

# Use max effort for all stages
deep-review --effort max

# Resume a previous session from a specific stage
deep-review --resume review --session 3

# Override model for all stages
deep-review --model opus[1m]
```

## Stages

```
setup -> context-building -> interview <-> update-tooling -> plan -> review -> remediation-plan -> remediation -> done
```

| Stage | Model (default) | Purpose |
|-------|----------------|---------|
| **setup** | haiku | Create branch, session folder; run repo setup scripts |
| **context-building** | opus[1m] | Analyze project structure, tech stack, discover and recommend review tools |
| **interview** | opus[1m] | Resolve ambiguities, approve tools, set review priorities |
| **update-tooling** | sonnet[1m] | Install approved tools, persist to repo setup scripts |
| **plan** | opus[1m] | Draft comprehensive review plan; requires user approval |
| **review** | opus[1m] | Deep review with up to 10 parallel sub-reviewers |
| **remediation-plan** | opus[1m] | Prioritize fixes and issues; requires user approval |
| **remediation** | sonnet[1m] | Apply fixes, create issues, run /simplify cleanup |

### State Machine

Interview, update-tooling, and plan can loop between each other (for adding tools or adjusting priorities). The review stage can self-loop for deeper investigation. Remediation-plan can loop back to interview/update-tooling if more tools are needed.

### Sub-Reviewers (Review Stage)

The review stage launches up to 10 parallel sub-reviewers, each with `model: "sonnet"`:

| # | Sub-Reviewer | Focus |
|---|-------------|-------|
| 1 | Security | SAST, secrets, dependency vulns, auth, injection, crypto |
| 2 | Code Quality | Complexity, duplication, dead code, naming |
| 3 | Architecture | Modularity, coupling, layering, circular deps |
| 4 | Documentation | README, CLAUDE.md, API docs, inline docs |
| 5 | Style/Formatting | Linting, consistency, conventions |
| 6 | Testing | Coverage, quality, gaps, assertions |
| 7 | Dependencies | Outdated, vulnerable, unused, licenses |
| 8 | Performance | N+1s, unbounded ops, caching, resources |
| 9 | Derived Interfaces | SDK/API/RPC/MCP/WebUI consistency |
| 10 | Simplification | Code size reduction, unnecessary indirection |

The plan stage determines which sub-reviewers to launch based on the project. Small projects may combine or skip tracks.

## Configuration

| Variable | Purpose | Default |
|----------|---------|---------|
| `DEEP_REVIEW_MODEL` | Override model for all stages | per-stage defaults |
| `DEEP_REVIEW_MODEL_<STAGE>` | Override model for one stage | per-stage default |
| `DEEP_REVIEW_EFFORT_<STAGE>` | Override effort for one stage | per-stage default |
| `DEEP_REVIEW_SKILL_PREFIX` | Skill name prefix | `deep-review:` |

## Session Folder

Each review session gets `./claude-reviews/<session-number>/`:

| Stage | Document |
|-------|----------|
| setup | `Session.md` |
| context-building | `Context.md` |
| interview | `Interview.md` |
| update-tooling | `UpdateTooling.md` |
| plan | `Plan.md` |
| review | `Review.md` + `sub-reviews/*.md` |
| remediation-plan | `Remediation-Plan.md` |
| remediation | `Remediation.md` |

Tool output is captured in `sub-reviews/.tool-output/`.

## Document Ownership

- Each stage may **read** any prior document but only **write** to its own
- Re-triggered stages **append** new sections
- Only **remediation** and **update-tooling** may edit source code

## Commits

Format: `claude-review(<stage>): <description> [session #<N>]`

## Loop Safety

- **5 runs maximum per stage** (prompts for confirmation)
- **25 total stage executions** (hard abort)

## License

MIT
