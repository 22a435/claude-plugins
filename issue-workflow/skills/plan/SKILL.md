---
name: plan
description: Draft a comprehensive implementation plan based on issue, research, and interview. Requires user approval before proceeding. Invoke with /issue-workflow:plan <issue-number>.
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash, Agent, Write, Edit, AskUserQuestion
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
- **Subagent write boundary:** Subagents in this stage must NOT create, edit, or write any files under `./claude-work/`. Only this parent session writes the output document. Include this constraint in every subagent prompt you compose.
- **No self-loop:** Do not use `/loop`, `ScheduleWakeup`, or recursive `claude` invocations to re-run this skill. For short waits, run the command synchronously with `Bash` (it blocks until completion); for long waits, use `Bash` with `run_in_background` and `Monitor`. If you cannot finish in one pass, commit your partial progress and write your own stage name to `.next-stage` -- the orchestrator re-enters the stage within its loop-safety limits. Never re-invoke yourself.
- **Deferral hierarchy (never silently drop, never over-file):** Pre-existing bugs are not grounds for dismissal -- leave the codebase in the best working order regardless of origin. When work surfaces that you will not finish in this PR, walk this hierarchy and stop at the first tier that fits: **(1) Fix it in this PR** -- the default, and hard; "complex", "tedious", "touches many files", or "would take a while" are NOT reasons to defer, only a genuine Create-Issue criterion is (a tradeoff the user must decide / architectural refactor / high blast radius / team discussion / breaking upgrade / benchmark-needed). **(2) Append to a follow-up already filed in this run** -- if a follow-up you filed (or will file) this run naturally covers it, add it there rather than opening a second issue. **(3) Append to an existing open backlog issue** -- before filing anything new, search the backlog (`gh issue list --state open --limit 200 --json number,title,labels,body`); if an open issue already covers the area, comment the new context onto it instead of creating a duplicate. **(4) File one new, bundled issue** -- only if no tier above fits; bundle every co-deferred finding from this run that shares a subsystem or design decision into the SAME issue (one well-scoped issue, never one-per-finding). Filing a follow-up is a commitment that the proper fix exceeds this PR's scope -- not a way to avoid work; never leave a deferred finding as a document-only note, and record which tier each deferral took and why.
- **Read issues in full:** When you read a GitHub issue, read the *entire* thread -- the body **and every comment/reply** -- plus any linked issues, PRs, commits, or docs that look relevant. Critical scope and context often live in replies, not the original body; missing them causes under-scoped work. Treat the whole thread as the source of truth for what the issue actually asks.

## Scope Discipline

The plan must cover the issue end-to-end. Plan the complete feature, not an MVP.

- Every requirement stated in Issue.md must map to a component with full implementation details (function signatures, data structures, edge cases, error paths).
- "Out of Scope" is for items NOT requested by the issue. It is never a place to defer parts of the requested feature to a follow-up.
- The only acceptable reason to omit part of the requested feature is that the user explicitly restricted scope during /issue-workflow:interview, and that restriction is recorded in Interview.md. If you find yourself wanting to defer something to a follow-up issue while drafting the plan, signal `interview` (Step 5 Escalate) and get the user's explicit decision first -- do not silently shrink the scope.
- "Minimum viable", "MVP", "phase 1 / phase 2", and "stub for now, implement later" framing is not acceptable in this document unless the user chose it.

## Context
- **Issue number:** $0 (numeric GitHub issue ID -- not a title, keyword, or topic name)
- **Work directory:** `./claude-work/$0/`
- **Input documents:** `./claude-work/$0/Issue.md`, `./claude-work/$0/Research.md`, `./claude-work/$0/Interview.md`
- **Output document:** `./claude-work/$0/Plan.md`

## Instructions

### Step 1: Read All Input Documents

Read `Issue.md`, `Research.md`, and `Interview.md` in full. Cross-reference the interview decisions against the research options to confirm everything is consistent.

If needed, use Explore agents to do targeted codebase lookups to fill gaps for the plan.

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
Things explicitly NOT included in this plan (to set clear boundaries). Only list items that fall outside the issue's stated requirements OR that the user explicitly cut from scope during interview. Do not use this section to defer parts of the requested feature to a follow-up issue.

Items listed here that represent known bugs, risks, or tech debt are to be filed as follow-up GitHub issues during the review stage's issue-creation step (Step 5a of /issue-workflow:review) -- not left as document-only notes. Per the **Deferral hierarchy**, the review stage dedupes these against the open backlog and **bundles** related items into the fewest issues, so group them here by subsystem/design decision rather than pre-splitting them one-per-line.
```

### Step 3: Write Plan.md and Commit

Write the drafted plan to `./claude-work/$0/Plan.md` immediately. Commit and push so the original draft is recorded in git history:

```bash
git add ./claude-work/$0/Plan.md
git commit -m "claude-work(plan): draft plan [#$0]"
git push
```

### Step 4: Present the Plan to the User

Present the full plan to the user as text. Then use the `AskUserQuestion` tool to collect their decision:

```
AskUserQuestion({
  questions: [{
    question: "How would you like to proceed with this implementation plan?",
    header: "Plan Review",
    options: [
      { label: "Approve", description: "Plan looks good -- proceed to implementation" },
      { label: "Request edits", description: "Specific sections need changes before approval" },
      { label: "Escalate", description: "Needs more discussion -- return to interview or research" }
    ],
    multiSelect: false
  }]
})
```

The user can also select "Other" to provide free-text feedback.

### Step 5: Handle Feedback

Based on the user's `AskUserQuestion` response:

**"Approve"** -- Proceed to Step 6 (Create Draft PR).

**"Request edits"** (or "Other" with edit instructions):
- Edit `./claude-work/$0/Plan.md` in place with the requested changes
- Commit and push after each round of edits:
  ```bash
  git add ./claude-work/$0/Plan.md
  git commit -m "claude-work(plan): revise plan -- <brief summary of changes> [#$0]"
  git push
  ```
- Present the updated plan to the user
- Return to Step 4 (re-invoke `AskUserQuestion` for approval)

**"Escalate"** (or "Other" requesting interview/research):
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

First resolve the merge target. Open the PR against the **configured target branch**, NOT against `main` unless `main` is the configured target.

```bash
# Precedence: env vars (set by the orchestrator) > .branch-meta.json > main.
META="./claude-work/$0/.branch-meta.json"
TARGET="${WF_TARGET:-$(jq -r '.wfTarget      // empty' "$META" 2>/dev/null)}"
TARGET="${TARGET:-main}"
STACK_PARENT_PR="${WF_STACK_PARENT_PR:-$(jq -r '.stackParentPR    // empty' "$META" 2>/dev/null)}"
STACK_FINAL_TARGET="${WF_STACK_FINAL_TARGET:-$(jq -r '.stackFinalTarget // empty' "$META" 2>/dev/null)}"
```

Create a draft Pull Request against `$TARGET`:
```bash
gh pr create \
  --title "Issue #$0: <issue title summary>" \
  --body "<plan summary + issue-linking line (see below)>" \
  --draft \
  --base "$TARGET" \
  --head "$(git branch --show-current)"
```

The PR body should contain:
- A concise summary of the plan (not the full plan)
- List of components being implemented
- An issue-linking line (see the stacking rule below)
- Reference to `./claude-work/$0/Plan.md` for the full plan

**Issue-linking line -- stacking-aware:**
- **Not stacked** (`$STACK_PARENT_PR` empty): use `Closes #$0` so merging the PR closes the issue.
- **Stacked** (`$STACK_PARENT_PR` set): the PR's base is a parent feature branch, so merging it into the parent must NOT close the umbrella issue. Use `Part of #$0` and `Stacked on #$STACK_PARENT_PR` instead, and add a visible banner at the top of the body:
  `> :warning: **Stacked PR** -- base is parent feature branch \`$TARGET\`, NOT the final target \`$STACK_FINAL_TARGET\`. This merges into the parent; the feature reaches \`$STACK_FINAL_TARGET\` once the whole stack lands.`

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
2. Present it to the user, then use `AskUserQuestion` to ask how to proceed:
   ```
   AskUserQuestion({
     questions: [{
       question: "This plan already exists from a previous run. How would you like to proceed?",
       header: "Prior Plan",
       options: [
         { label: "Approve", description: "Plan looks good as-is -- proceed to implementation" },
         { label: "Request edits", description: "Specific sections need changes before approval" },
         { label: "Escalate", description: "Needs more discussion -- return to interview or research" }
       ],
       multiSelect: false
     }]
   })
   ```
3. If edits requested: edit Plan.md in place (git history serves as the audit trail -- do not append revision sections)
4. Commit and push after each round of edits:
   ```bash
   git add ./claude-work/$0/Plan.md
   git commit -m "claude-work(plan): revise plan -- <brief summary of changes> [#$0]"
   git push
   ```
5. Return to Step 4 to re-invoke `AskUserQuestion` for approval

If Plan.md does not exist, start from Step 1.
