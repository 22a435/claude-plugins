---
name: interview
description: Resolve ambiguities, present tool recommendations for approval, gather review priorities. Invoke with /interview <session-number>.
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash, Agent, Write, Edit
---

# Interview Phase

You are performing the **interview** stage of a deep codebase review. Your job is to resolve ambiguities, present tool recommendations for user approval, and gather review priorities.

## Workflow Context

This skill is one stage of a 7-stage deep review workflow orchestrated by the `deep-review` CLI.

- **Branch:** `claude/review/<session-number>` (created by the orchestrator during setup)
- **Work directory:** `./claude-reviews/<session-number>/` -- each stage produces one document here
- **Document ownership:** You may READ any prior document. Only WRITE to your own output document inside `./claude-reviews/$0/` (where `$0` is the session number passed as your argument). Never create files, directories, or write anywhere else under `./claude-reviews/`. When re-triggered, APPEND new sections -- never delete or overwrite existing content. Mark in-place edits with `> [IN-PLACE EDIT during <stage> phase]: <reason>`.
- **Commits:** Format: `claude-review(<stage>): <description> [session #<N>]`. Commit and push after completing the stage.
- **PR updates:** Post a summary to the PR thread (via `gh pr comment`) after completing the stage.

## Context
- **Session number:** $0 (the review session number passed as your argument)
- **Work directory:** `./claude-reviews/$0/`
- **Input documents:** `./claude-reviews/$0/Session.md`, `./claude-reviews/$0/Context.md` (and `Interview.md`, `UpdateTooling.md` if re-triggered)
- **Output document:** `./claude-reviews/$0/Interview.md`

## Instructions

### Step 1: Read Input Documents

Read `Context.md` in full. If this is a re-trigger, also read the existing `Interview.md` and `UpdateTooling.md` (if it exists) to understand what has already been decided and what tools were installed.

### Step 2: Present Tool Recommendations

Present the recommended tools from Context.md to the user. Group them by category (static analysis, security, dependency, etc.). For each tool, show:
- What it does and what it catches
- Install and run commands
- Persistence risk level (low/medium/high)
- Ask: **approve / reject / defer**

If no tools were recommended, note this and skip to Step 3.

Handle special responses:
- "approve all" -- approve every recommended tool
- "skip" or "no tools" -- reject all, proceed with manual review only
- User suggests tools not in recommendations -- record as user-requested tools

### Step 3: Gather Review Priorities

Ask the user about their review priorities:

1. **Priority ordering:** Which aspects matter most? (security, performance, code quality, documentation, architecture, testing, dependencies)
2. **Known problem areas:** Are there specific directories, modules, or concerns to focus on?
3. **Out of scope:** Any areas to explicitly skip? (e.g., generated code, vendored deps, legacy modules)
4. **Specific concerns:** Anything particular to look for?

### Step 4: Ask About Derived Interfaces

If Context.md detected derived interfaces (SDKs, APIs, RPC, MCP, WebUI):
- Confirm which ones are accurate
- Ask which should be included in the review
- Ask about any undocumented interfaces

### Step 5: Resolve Open Questions

Address any open questions from Context.md. Present them grouped by topic. Ask follow-up questions to clarify ambiguous answers.

Handle deferrals gracefully:
- "you decide" -- provide a clear recommendation and record it as the decision
- "I don't know" -- record it as deferred, note assumptions being made

### Step 6: Write Interview.md

Write `./claude-reviews/$0/Interview.md`:

```
# Interview Record: Review Session #<N>

## Approved Tools
| Tool | Category | Persist to Repo |
|------|----------|----------------|
| ruff | static-analysis | yes |
| ...  | ...      | ...            |

## Rejected Tools
| Tool | Reason |
|------|--------|
| ...  | ...    |

## User-Requested Tools
Tools the user requested that were not in the original recommendations.

## Review Priorities
Ordered list of what matters most, with user's rationale.

## Focus Areas
Specific directories, modules, or concerns to prioritize.

## Out of Scope
What to skip and why.

## Derived Interfaces to Review
Which interfaces to include and their expected relationship to core code.

## Decisions
All other decisions from the interview, grouped by topic.

## Additional Context from User
Any other context the user provided.
```

### Step 7: Commit, Push, and Comment

```bash
git add ./claude-reviews/$0/Interview.md
git commit -m "claude-review(interview): decisions recorded [session #$0]"
git push
```

Post summary to PR:
```bash
gh pr comment "claude/review/$0" --body "**Interview:** <N> decisions recorded. <N> tools approved. Priority: <top priorities>. Focus areas: <areas>."
```

## Stage Transition Signal

When running under the `deep-review` orchestrator, you can request a transition to a different stage by writing the target stage name to `./claude-reviews/$0/.next-stage`.

**Rules:**
- Write exactly one stage name, nothing else
- Only write this file if you want a NON-DEFAULT transition
- If you do not write this file, the orchestrator advances to `plan` (default)
- The orchestrator validates your request -- invalid transitions are ignored

**When to signal:**
- `update-tooling` -- if any tools were approved for installation:
  ```bash
  echo "update-tooling" > ./claude-reviews/$0/.next-stage
  ```
- `interview` -- if you need another round of questions (should be rare):
  ```bash
  echo "interview" > ./claude-reviews/$0/.next-stage
  ```
- Default (advance to plan) is correct when no tools need installing.

## Re-trigger Behavior

If re-triggered and `./claude-reviews/$0/Interview.md` already exists:

1. Read the existing Interview.md and UpdateTooling.md (if exists)
2. Identify what has changed or what new questions arose
3. Append a new section:

```
---

## Follow-up Interview (triggered during <stage> phase)

### Reason
<why another interview was needed>

### New Decisions
<additional decisions>

### Updated Tools
<any changes to tool approvals>
```
