---
name: plan
description: Draft a comprehensive implementation plan based on issue, research, and interview. Requires user approval before proceeding. Invoke with /plan <issue-number>.
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash, Agent, Write, Edit
---

# Planning Phase

You are performing the **planning** stage of an issue workflow. Your job is to create a thorough, specific implementation plan that will guide execution.

## Workflow Context

This skill is one stage of an 8-stage issue-to-PR workflow orchestrated by the `work-issue` CLI.

- **Branch:** `claude/<issue-number>` (created by the orchestrator during setup)
- **Work directory:** `./claude-work/<issue-number>/` -- each stage produces one document here
- **Document ownership:** You may READ any prior document. Only WRITE to your own output document inside `./claude-work/$0/` (where `$0` is the numeric GitHub issue ID passed as your argument). Never create files, directories, or write anywhere else under `./claude-work/`. You may edit Plan.md in place freely -- git history serves as the audit trail. No append-only constraint applies to this stage.
- **Commits:** Format: `claude-work(plan): <description> [#<issue>]`. Use `claude-work(plan): draft plan [#$0]` for the initial write and `claude-work(plan): revise plan -- <summary> [#$0]` for subsequent edits. Commit and push after writing the initial draft AND after each round of revisions.
- **PR updates:** Post a summary to the PR or issue thread (via `gh pr comment` or `gh issue comment`) after each stage.
- **Subagent cost optimization:** Downgrade information-gathering agents (Explore, web research, context7) to `model: "sonnet"`. Keep the parent session's model for implementation and reasoning agents.
- **Subagent write boundary:** Subagents in this stage must NOT create, edit, or write any files under `./claude-work/`. Only this parent session writes the output document. Include this constraint in every subagent prompt you compose.

## Context
- **Issue number:** $0 (numeric GitHub issue ID -- not a title, keyword, or topic name)
- **Work directory:** `./claude-work/$0/`
- **Input documents:** `./claude-work/$0/Issue.md`, `./claude-work/$0/Research.md`, `./claude-work/$0/Interview.md`
- **Output document:** `./claude-work/$0/Plan.md`

## Instructions

### Step 1: Read All Input Documents

Read `Issue.md`, `Research.md`, and `Interview.md` in full. Cross-reference the interview decisions against the research options to confirm everything is consistent.

If needed, use Explore agents to do targeted codebase lookups to fill gaps for the plan. Launch Explore agents with `model: "sonnet"` -- they are gathering information, not designing the plan.

### Step 2: Draft the Plan

Create a comprehensive implementation plan. The plan must be **specific** -- it should name exact files, functions, APIs, and data structures. Vague steps like "update the code" are not acceptable.

**Plan structure:**

```
# Implementation Plan: Issue #<number>

## Overview
What is being built/changed and why. 1-2 paragraphs.

## Components

### Component 1: <name>
**Description:** What this component does.
**Files to modify/create:**
- `path/to/file.ts` -- <what changes>
- `path/to/new-file.ts` -- <new file, purpose>

**Implementation details:**
Specific description of the changes. Include function signatures, data structures, API shapes, configuration values, etc.

**Dependencies:** What must be done before this component.

**Verification:**
- [ ] <Specific, runnable check that proves this component works>
- [ ] <Another verification step>
- [ ] <Edge case to verify>

### Component 2: <name>
...

## Execution Order
Which components can be done in parallel and which are sequential.

1. Component A and Component B (parallel -- no dependencies)
2. Component C (depends on A)
3. Component D (depends on B and C)

## Full Verification Suite
After all components are complete, these checks validate the entire implementation:
- [ ] <End-to-end verification step>
- [ ] <Integration verification>
- [ ] <All existing tests pass>
- [ ] <Performance/security check if applicable>
- [ ] <Documentation is updated if applicable>

## Risks and Mitigations
Known risks and how the plan accounts for them.

## Out of Scope
Things explicitly NOT included in this plan (to set clear boundaries).
```

### Step 3: Write Plan.md and Commit

Write the drafted plan to `./claude-work/$0/Plan.md` immediately. Commit and push so the original draft is recorded in git history:

```bash
git add ./claude-work/$0/Plan.md
git commit -m "claude-work(plan): draft plan [#$0]"
git push
```

### Step 4: Present the Plan to the User

Present the full plan to the user for review. Tell them:

"Here is the complete implementation plan. Please review it. You can:
- **Approve** it as-is to proceed to implementation
- **Request edits** to specific sections
- **Escalate** back to interview or research if something needs more discussion"

### Step 5: Handle Feedback

If the user requests edits:
- Edit `./claude-work/$0/Plan.md` in place with the requested changes
- Commit and push after each round of edits:
  ```bash
  git add ./claude-work/$0/Plan.md
  git commit -m "claude-work(plan): revise plan -- <brief summary of changes> [#$0]"
  git push
  ```
- Present the updated plan to the user
- Return to Step 4 (ask for approval again)

If the user escalates to interview or research:
- Note what needs to be revisited in Plan.md
- Commit and push the current state of Plan.md if it has uncommitted changes
- Write the appropriate stage name to the signal file:
  ```bash
  echo "interview" > ./claude-work/$0/.next-stage
  # or
  echo "research" > ./claude-work/$0/.next-stage
  ```
- The orchestrator will redirect to that stage automatically. When it completes, the pipeline will advance back through to plan again.

### Step 6: Create Draft PR (after approval)

Only after the user explicitly approves the plan:

Create a draft Pull Request:
```bash
gh pr create \
  --title "Issue #$0: <issue title summary>" \
  --body "<plan summary + 'Closes #$0'>" \
  --draft \
  --base main \
  --head "claude/$0"
```

The PR body should contain:
- A concise summary of the plan (not the full plan)
- List of components being implemented
- `Closes #$0` to link the issue
- Reference to `./claude-work/$0/Plan.md` for the full plan

## Stage Transition Signal

When running under the `work-issue` orchestrator, you can request a transition to a different stage by writing the target stage name to `./claude-work/$0/.next-stage`.

**Rules:**
- Write exactly one stage name, nothing else
- Only write this file if you want a NON-DEFAULT transition
- If you do not write this file, the orchestrator advances to `execute` (default)
- The orchestrator validates your request -- invalid transitions are ignored

**When to signal:**
- `research` -- if the plan reveals that critical information is missing from Research.md
- `interview` -- if the plan surfaces new design questions that need user input
- In most cases, the user approves the plan and the default (advance to execute) is correct.

Write the signal file as your last action, after the commit/push step. See Step 5 for the specific escalation flow.

## Re-trigger Behavior

If re-triggered and `./claude-work/$0/Plan.md` already exists:

1. Read the existing Plan.md in full
2. Present it to the user and ask what needs to change
3. Edit Plan.md in place with the requested changes (git history serves as the audit trail -- do not append revision sections)
4. Commit and push after each round of edits:
   ```bash
   git add ./claude-work/$0/Plan.md
   git commit -m "claude-work(plan): revise plan -- <brief summary of changes> [#$0]"
   git push
   ```
5. Return to Step 4 to ask for approval again

If Plan.md does not exist, start from Step 1.
