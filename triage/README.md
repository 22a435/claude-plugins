# triage

A Claude Code plugin that consolidates a messy GitHub backlog into a small, loosely-coupled set of well-scoped issues -- each a single comprehensive "bite" the [issue-workflow](../issue-workflow) plugin can take to one PR.

## Why It Exists

The issue-workflow and deep-review plugins are both **net creators** of issues: each issue-workflow run tends to spin off more than one follow-up, and each deep-review run emits a batch. Without a counterweight the backlog grows and fragments. `triage` is the **net consumer**: it reads the whole open backlog (plus in-code TODOs), closes what's already fixed, merges duplicates, and bundles the rest into the fewest well-scoped issues that respect real boundaries.

The key move is **anchoring each bundle on the design decision its members depend on**. Dependent and downstream work travels with the decision it hinges on, so the issue workflow resolves that decision **once** (during its research/interview) and everything in the bundle flows from it -- which is exactly what lets different bundles be worked **in parallel** with minimal coupling.

## How It Works

The `triage` CLI launches sequential Claude Code sessions, one per stage. It reads every open issue **in full** (bodies *and* comment threads -- scope often lives in replies), confronts each with the current codebase, then plans and applies a consolidation. **No GitHub issue is closed or created until you approve the full plan in the interview stage.**

## Prerequisites

- **GitHub CLI** (`gh`) -- authenticated with repo access
- **Claude Code CLI** (`claude`) -- authenticated
- **git** and **jq** in PATH

## Installation

```bash
# Add the marketplace (if not already added)
claude plugin marketplace add 22a435/claude-plugins

# Install the triage plugin
claude plugin install 22a435-workflows@triage --scope user
```

### Setting up the CLI command

```bash
# Option A: symlink
PLUGIN_PATH="$(find ~/.claude -path '*/triage/bin/triage' 2>/dev/null | head -1)"
sudo ln -sf "$PLUGIN_PATH" /usr/local/bin/triage

# Option B: shell alias
alias triage='bash ~/.claude/plugins/marketplaces/22a435-workflows/triage/bin/triage'
```

## Quick Start

```bash
# Start a new triage session
triage

# Use max effort for all stages
triage --effort max

# Resume a previous session from a specific stage
triage --resume cluster --session 3

# Override model for all stages
triage --model opus[1m]
```

## Stages

```
setup -> inventory -> reconcile -> cluster -> interview -> consolidate -> verify -> integrate -> done
```

| Stage | Model (default) | Purpose |
|-------|----------------|---------|
| **setup** | haiku | Create branch, session folder, draft PR; run repo setup scripts |
| **inventory** | opus[1m] | Read every open issue (full comment threads) and in-code TODOs; build a structured inventory |
| **reconcile** | opus[1m] | Classify each item against the current code: already-fixed / duplicate / still-live |
| **cluster** | opus[1m] | Build the dependency / design-decision graph; consolidate into well-scoped bundles |
| **interview** | opus[1m] | Present the full plan for approval -- **no GitHub mutations happen before this** |
| **consolidate** | opus[1m] | Apply the approved plan: create bundles, close fixed/duplicate/absorbed issues |
| **verify** | opus[1m] | Confirm GitHub state matches the approved plan; salvage failed operations |
| **integrate** | opus[1m] | Rebase the report branch onto main if needed; mark PR ready |

### State Machine

The pre-consolidate stages can loop back for more depth (reconcile can ask inventory for fuller threads; cluster can send reconcile back to rework classifications). The **interview** stage is the approval gate: it advances to `consolidate` only when the plan is approved, and loops back to `cluster`/`reconcile` if the user wants re-planning. Verify loops back to `consolidate` if it finds gaps; otherwise advances to `integrate`. Integrate rebases the report branch onto main and finishes.

### Inputs

| Input | How it's gathered |
|-------|-------------------|
| Open GitHub issues | `gh issue list` + `gh issue view <n> --comments` (full thread, links followed) |
| In-code TODOs | grep for `TODO`/`FIXME`/`XXX`/`HACK` (genuine work only; noise is skipped) |

## Configuration

| Variable | Purpose | Default |
|----------|---------|---------|
| `TRIAGE_MODEL` | Override model for all stages | per-stage defaults |
| `TRIAGE_MODEL_<STAGE>` | Override model for one stage | per-stage default |
| `TRIAGE_EFFORT_<STAGE>` | Override effort for one stage | per-stage default |
| `TRIAGE_SKILL_PREFIX` | Skill name prefix | `triage:` |
| `CLAUDE_PLUGINS_SKIP_UPDATE` | Skip the startup marketplace refresh | unset |

## Session Folder

Each triage session gets `./claude-triages/<session-number>/`:

| Stage | Document |
|-------|----------|
| setup | `Session.md` |
| inventory | `Inventory.md` |
| reconcile | `Reconcile.md` |
| cluster | `Cluster.md` |
| interview | `Interview.md` |
| consolidate | `Triage.md` |
| verify | `Verify.md` |
| integrate | `Integration.md` |

## Document Ownership

- Each stage may **read** any prior document but only **write** to its own
- Re-triggered stages **append** new sections, never overwrite
- Subagents never write to the session folder and never mutate GitHub -- only the parent session does
- GitHub issues are mutated **only** in `consolidate` (and `verify` salvage), strictly per the approved plan

## Commits

Format: `claude-triage(<stage>): <description> [session #<N>]`

## Safety

- A `PreToolUse` hook blocks `git push` to protected branches (main, master, production)
- The interview stage is a hard approval gate: nothing is closed or created on GitHub until the full plan is approved
