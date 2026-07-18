---
name: update-tooling
description: Install user-approved review tools and configure them for the project. Invoke with /deep-review:update-tooling <session-number>.
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash, Agent, Write, Edit, WebSearch, WebFetch
---

# Update Tooling Phase

You are performing the **update-tooling** stage of a deep codebase review. Your job is to install user-approved tools and, where appropriate, persist them into the repository's setup scripts.

## Workflow Context

This skill is one stage of a multi-stage deep review workflow orchestrated by the `deep-review` CLI.

- **Branch:** `claude/review/<session-number>` (created by the orchestrator during setup)
- **Work directory:** `./claude-reviews/<session-number>/` -- each stage produces one document here
- **Document ownership:** You may READ any prior document. Only WRITE to your own output document inside `./claude-reviews/$0/` (where `$0` is the session number passed as your argument). Never create files, directories, or write anywhere else under `./claude-reviews/` except your output document. When re-triggered, APPEND new sections -- never delete or overwrite existing content.
- **Commits:** Format: `claude-review(<stage>): <description> [session #<N>]`. Commit and push after completing the stage.
- **PR updates:** Post a summary to the PR thread (via `gh pr comment`) after completing the stage.
- **Code changes allowed:** This stage MAY modify repo files outside `./claude-reviews/` -- specifically setup scripts, config files, and tool configuration. This is one of only two stages (along with remediation) that edits repo code.
- **No self-loop:** Do not use `/loop`, `ScheduleWakeup`, or recursive `claude` invocations to re-run this skill. For short waits, run the command synchronously with `Bash` (it blocks until completion); for long waits, use `Bash` with `run_in_background` and `Monitor`. If you cannot finish in one pass, commit your partial progress and write your own stage name to `.next-stage` -- the orchestrator re-enters the stage within its loop-safety limits. Never re-invoke yourself.
- **Deferral hierarchy (never silently drop, never over-file):** Pre-existing bugs are not grounds for dismissal -- leave the codebase in the best working order regardless of origin. When work surfaces that you will not finish in this PR, walk this hierarchy and stop at the first tier that fits: **(1) Fix it in this PR** -- the default, and hard; "complex", "tedious", "touches many files", or "would take a while" are NOT reasons to defer, only a genuine Create-Issue criterion is (a tradeoff the user must decide / architectural refactor / high blast radius / team discussion / breaking upgrade / benchmark-needed). **(2) Append to a follow-up already filed in this run** -- if a follow-up you filed (or will file) this run naturally covers it, add it there rather than opening a second issue. **(3) Append to an existing open backlog issue** -- before filing anything new, search the backlog (`gh issue list --state open --limit 200 --json number,title,labels,body`); if an open issue already covers the area, comment the new context onto it instead of creating a duplicate. **(4) File one new, bundled issue** -- only if no tier above fits; bundle every co-deferred finding from this run that shares a subsystem or design decision into the SAME issue (one well-scoped issue, never one-per-finding). Filing a follow-up is a commitment that the proper fix exceeds this PR's scope -- not a way to avoid work; never leave a deferred finding as a document-only note, and record which tier each deferral took and why.
- **Read issues in full:** When you read a GitHub issue, read the *entire* thread -- the body **and every comment/reply** -- plus any linked issues, PRs, commits, or docs that look relevant. Critical scope and context often live in replies, not the original body; missing them causes under-scoped work. Treat the whole thread as the source of truth for what the issue actually asks.

## Context
- **Session number:** $0 (the review session number passed as your argument)
- **Work directory:** `./claude-reviews/$0/`
- **Input documents:** `./claude-reviews/$0/Interview.md`, `./claude-reviews/$0/Context.md`
- **Output document:** `./claude-reviews/$0/UpdateTooling.md`

## Instructions

### Step 1: Read Input Documents

Read `Interview.md` for the list of approved tools, including:
- Which tools were approved
- Whether to persist each tool to the repo
- Any user-requested tools not in the original recommendations

Also read `Context.md` for the install/run commands and existing tooling already in the repo.

If `UpdateTooling.md` already exists (re-trigger), read it to see what was previously installed.

### SC-Auditor & Subtools

If Interview.md contains an "SC-Auditor Decision" section with `Approved: yes`, install sc-auditor and its subtools:

1. **sc-auditor** (requires Node.js >= 22). Check for an existing install first -- the VM used for deep-review runs typically has it pre-installed. sc-auditor is NOT on the public npm registry (`npm install -g sc-auditor` fails with a 404); install from GitHub:
   ```bash
   node --version  # Verify >= 22
   command -v sc-auditor || npm list -g sc-auditor || npm install -g github:Archethect/sc-auditor
   ```

2. **Slither** (Python-based static analyzer):
   ```bash
   pip install slither-analyzer
   pip install solc-select && solc-select install 0.8.20 && solc-select use 0.8.20
   ```

3. **Aderyn** (Rust-based static analyzer):
   ```bash
   curl -L https://raw.githubusercontent.com/Cyfrin/aderyn/dev/cyfrinup/install | bash
   cyfrinup
   ```

4. **Foundry** (Solidity testing framework):
   ```bash
   curl -L https://foundry.paradigm.xyz | bash
   foundryup
   ```

5. **Echidna** (invariant fuzzer) -- optional:
   ```bash
   pip install echidna 2>/dev/null || echo "Echidna not available via pip -- may need manual install"
   ```

6. **Medusa** (fuzz testing) -- optional:
   ```bash
   command -v medusa 2>/dev/null || echo "Medusa not installed -- skip"
   ```

7. **Halmos** (symbolic execution) -- optional:
   ```bash
   pip install halmos 2>/dev/null || echo "Halmos not available via pip -- may need manual install"
   ```

For each tool, check if already installed before attempting installation. Record all results (installed, already present, or failed) in UpdateTooling.md. If the Solodit API key was noted as available, verify `SOLODIT_API_KEY` is set in the environment or `.env` file.

### Step 2: Check Existing Installations

For each approved tool, check if it is already installed:

```bash
command -v <tool-name> 2>/dev/null && echo "installed" || echo "not installed"
# or package-specific checks:
npm list -g <package> 2>/dev/null
pip show <package> 2>/dev/null
```

Skip tools that are already installed and at a compatible version.

### Step 3: Install Tools

For each tool that needs installation:

1. Install using the appropriate package manager:
   - npm/yarn/pnpm for JS tools
   - pip/pipx for Python tools
   - go install for Go tools
   - cargo install for Rust tools
   - brew/apt for system tools
   - Prefer global installs for CLI tools, dev dependencies for project-specific tools

2. Run a quick smoke test to verify it works:
   ```bash
   <tool> --version  # or --help, or a simple invocation
   ```

3. Record success or failure with version information.

### Step 4: Configure Tools (if needed)

Some tools need project-level configuration. For each:

- **Low risk** (CLI-only tools, no config needed): Install and done.
- **Medium risk** (adds config file like `.eslintrc`, `ruff.toml`): Create a minimal, reasonable config. Record what was created.
- **High risk** (modifies build pipeline, adds CI steps): Ask the user before proceeding. If the user already approved during interview, proceed; otherwise skip and document why.

### Step 5: Persist to Repo Setup

For tools marked for persistence in Interview.md:

1. **Check for existing setup scripts:** Look for `scripts/setup.sh`, `Makefile` setup targets, `package.json` scripts, `.devcontainer/`, etc.
2. **If setup scripts exist:** Add tool installation commands to the appropriate script.
3. **If no setup scripts exist:** Consider creating a lightweight setup approach (e.g., adding to `package.json` devDependencies, or `pyproject.toml` dev dependencies).
4. **Always add to `.claude/settings.json` or CLAUDE.md** if the tool should be available to future Claude sessions.

For tools NOT marked for persistence: install in the current environment only. No repo changes.

### Step 6: Write UpdateTooling.md

Write `./claude-reviews/$0/UpdateTooling.md`:

```
# Tooling Update: Review Session #<N>

## Summary
<N> tools installed, <N> already present, <N> failed.

## Tools Installed
| Tool | Version | Install Method | Persisted | Notes |
|------|---------|---------------|-----------|-------|
| ruff | 0.4.1 | pip install ruff | yes (pyproject.toml) | |
| ...  | ...     | ...           | ...       | ...   |

## Tools Already Present
| Tool | Version | Location |
|------|---------|----------|
| eslint | 8.57.0 | node_modules/.bin/eslint |
| ...    | ...     | ...      |

## Tools Failed to Install
| Tool | Error | Suggested Workaround |
|------|-------|---------------------|
| ...  | ...   | ...                 |

## Configuration Created
| File | Tool | Description |
|------|------|-------------|
| ruff.toml | ruff | Minimal config with default rules |
| ...  | ...  | ...         |

## Setup Script Updates
What was added to repo setup scripts, if anything. Include the exact changes made.

## Available Tool Commands
Quick reference for running each installed tool:
- `ruff check .` -- Python linter
- `npm audit` -- Dependency audit
- ...
```

### Step 7: Commit, Push, and Comment

Commit both the UpdateTooling.md and any repo changes (config files, setup script updates):

```bash
git add -A
git commit -m "claude-review(update-tooling): install review tools [session #$0]"
git push
```

Post summary to PR:
```bash
gh pr comment --body "**Update Tooling:** <N> tools installed, <N> already present, <N> failed. Persisted to repo: <list>."
```

## Stage Transition Signal

When running under the `deep-review` orchestrator, you can request a transition to a different stage by writing the target stage name to `./claude-reviews/$0/.next-stage`.

**Rules:**
- Write exactly one stage name, nothing else
- Only write this file if you want a NON-DEFAULT transition
- If you do not write this file, the orchestrator advances to `interview` (default)
- The orchestrator validates your request -- invalid transitions are ignored

**When to signal:**
- Default (return to interview) is almost always correct -- the interview stage will confirm everything worked and continue to plan.

## Re-trigger Behavior

If re-triggered and `./claude-reviews/$0/UpdateTooling.md` already exists:

1. Read the existing UpdateTooling.md to see what was previously installed
2. Read the latest Interview.md for any newly approved tools
3. Only install tools not already present
4. Append a new section:

```
---

## Additional Tooling Update (triggered during <stage> phase)

### Reason
<what new tools were requested>

### New Tools Installed
| Tool | Version | Install Method | Persisted |
|------|---------|---------------|-----------|
| ...  | ...     | ...           | ...       |
```
