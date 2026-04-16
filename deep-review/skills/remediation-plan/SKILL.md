---
name: remediation-plan
description: Create a prioritized remediation plan from review findings, including follow-up issues for complex items. Requires user approval. Invoke with /deep-review:remediation-plan <session-number>.
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash, Agent, Write, Edit, AskUserQuestion
---

# Remediation Planning Phase

You are performing the **remediation-plan** stage of a deep codebase review. Your job is to create a prioritized plan for fixing review findings and creating GitHub issues for complex items.

## Workflow Context

This skill is one stage of a multi-stage deep review workflow orchestrated by the `deep-review` CLI.

- **Branch:** `claude/review/<session-number>` (created by the orchestrator during setup)
- **Work directory:** `./claude-reviews/<session-number>/` -- each stage produces one document here
- **Document ownership:** You may READ any prior document. Only WRITE to your own output document inside `./claude-reviews/$0/` (where `$0` is the session number passed as your argument). Never create files, directories, or write anywhere else under `./claude-reviews/`. You may edit Remediation-Plan.md in place freely -- git history serves as the audit trail.
- **Commits:** Format: `claude-review(<stage>): <description> [session #<N>]`. Commit and push after writing and after each revision.
- **PR updates:** Post a summary to the PR thread (via `gh pr comment`) after completing the stage.
- **Subagent cost optimization:** Downgrade information-gathering agents to `model: "sonnet"`. Keep the parent session's model for prioritization and judgment.
- **Subagent write boundary:** Subagents must NOT write to `./claude-reviews/`. Only this parent session writes the output document.

## Context
- **Session number:** $0 (the review session number passed as your argument)
- **Work directory:** `./claude-reviews/$0/`
- **Input documents:** `./claude-reviews/$0/Review.md` (primary), all `sub-reviews/*.md`, Context.md, Interview.md
- **Output document:** `./claude-reviews/$0/Remediation-Plan.md`

## Instructions

### Step 1: Read All Input Documents

Read `Review.md` in full -- this is your primary input. Also read:
- All files in `sub-reviews/` for detailed findings
- `Context.md` for project structure and available tools
- `Interview.md` for user priorities and constraints

### Step 2: Categorize All Findings

For every finding in Review.md, categorize it into one of three buckets:

**Fix Now** -- Items that can and should be fixed in this review session:
- Clear, well-defined changes with low risk
- Documentation updates and CLAUDE.md cleanup
- Style/formatting fixes
- Simple bug fixes with obvious correct behavior
- Dependency updates (minor/patch versions)
- Dead code removal

**Create Issue** -- Items too complex for immediate remediation:
- Changes involving tradeoffs the developer should decide
- Architectural refactors that need careful planning
- Changes with high blast radius
- Items requiring team discussion or broader context
- Major version upgrades with breaking changes
- Performance optimizations requiring benchmarking

**Skip** -- Items not worth addressing:
- False positives from automated tools
- Findings in out-of-scope areas
- Informational items that don't require action
- Items the user explicitly deprioritized

### Step 3: Draft Remediation-Plan.md

Write `./claude-reviews/$0/Remediation-Plan.md`:

```
# Remediation Plan: Session #<N>

## Overview
Summary of what will be remediated, what will become issues, and what will be skipped.
Total: <N> fix now, <N> create issue, <N> skip.

## Immediate Remediations

### Remediation 1: <title>
- **Source finding:** <reference to Review.md section or sub-review>
- **Severity:** critical / important / suggestion
- **Files to change:**
  - `path/to/file.ts` -- <what changes>
  - `path/to/other.ts` -- <what changes>
- **Change description:** Specific description of the fix
- **Verification:** How to confirm the fix works
- **Risk:** low / medium / high
- **Dependencies:** What must be done before/after this

### Remediation 2: ...
(continue for all fix-now items)

## Issues to Create

### Issue 1: <proposed title>
- **Source finding:** <reference>
- **Description:** What needs to be done and why
- **Relevant context:** Key findings that inform this issue
- **Suggested labels:** bug / enhancement / security / documentation / tech-debt
- **Priority:** high / medium / low
- **Estimated effort:** small / medium / large

### Issue 2: ...
(continue for all create-issue items)

## Deferred / Accepted Risk

### Skipped 1: <finding title>
- **Source finding:** <reference>
- **Reason:** Why this is being skipped (false positive / out of scope / acceptable risk / user deprioritized)

## Execution Order
Which remediations can be parallelized and which must be sequential.

1. Remediations A and B (parallel -- different files, no dependencies)
2. Remediation C (depends on A -- same file)
3. Remediation D (independent, but should be last -- runs /simplify cleanup)
```

### Step 4: Commit and Push

```bash
git add ./claude-reviews/$0/Remediation-Plan.md
git commit -m "claude-review(remediation-plan): draft remediation plan [session #$0]"
git push
```

### Step 5: Present Full Plan Overview

Present the complete remediation plan to the user organized by category. For each category (Fix Now, Create Issue, Skip), list every item with its title, severity, and a one-line description. The goal is to give the user the full picture -- including any overlaps or intersections between items -- before diving into per-item decisions.

Example format:

```
## Fix Now (N items)
1. <title> — <severity> — <one-line description>
2. ...

## Create Issue (N items)
1. <title> — <severity> — <one-line description>
2. ...

## Skip (N items)
1. <title> — <severity> — <one-line description>
2. ...
```

After presenting the overview, proceed directly to per-item review.

### Step 6: Sequential Per-Item Review

Walk through every item across all three categories (Fix Now first, then Create Issue, then Skip) one at a time. For each item:

1. **Present the item's full details** -- title, source finding, severity, files to change, change description, verification, risk, and dependencies.

2. **Call `AskUserQuestion`** with options contextual to the item's current category:

**If item is currently in "Fix Now":**
```
AskUserQuestion({
  questions: [{
    question: "<item title>\n<brief item summary>",
    header: "Fix Now — Item N of M",
    options: [
      { label: "Approve", description: "Keep in Fix Now" },
      { label: "Move to Create Issue", description: "Defer to a GitHub issue instead" },
      { label: "Remove", description: "Drop from plan entirely" },
      { label: "Edit", description: "Modify this item (provide details via Other)" }
    ],
    multiSelect: false
  }]
})
```

**If item is currently in "Create Issue":**
```
AskUserQuestion({
  questions: [{
    question: "<item title>\n<brief item summary>",
    header: "Create Issue — Item N of M",
    options: [
      { label: "Approve", description: "Keep as Create Issue" },
      { label: "Move to Fix Now", description: "Fix immediately in this session" },
      { label: "Remove", description: "Drop from plan entirely" },
      { label: "Edit", description: "Modify this item (provide details via Other)" }
    ],
    multiSelect: false
  }]
})
```

**If item is currently in "Skip":**
```
AskUserQuestion({
  questions: [{
    question: "<item title>\n<brief item summary>",
    header: "Skip — Item N of M",
    options: [
      { label: "Approve", description: "Keep skipped" },
      { label: "Move to Fix Now", description: "Fix immediately in this session" },
      { label: "Move to Create Issue", description: "Defer to a GitHub issue" },
      { label: "Edit", description: "Modify this item (provide details via Other)" }
    ],
    multiSelect: false
  }]
})
```

3. **Apply the user's decision:**
   - **Approve**: No change. Move to the next item.
   - **Move to \<category\>**: Recategorize the item to the target bucket. Move to the next item.
   - **Remove**: Delete the item from the plan entirely. Move to the next item.
   - **Edit** (or "Other" with free-text instructions): Apply the user's edits to the item, present the updated item, and re-ask for approval on that same item (loop until the user selects Approve, Move, or Remove).

### Step 7: Finalize Plan

After all items have been individually reviewed:

1. Update `Remediation-Plan.md` with all moves, removals, and edits applied.
2. Commit and push:
   ```bash
   git add ./claude-reviews/$0/Remediation-Plan.md
   git commit -m "claude-review(remediation-plan): revise plan per item review [session #$0]"
   git push
   ```
3. Present a final summary showing the updated counts per category. Then call `AskUserQuestion`:
   ```
   AskUserQuestion({
     questions: [{
       question: "Final plan: <N> fix now, <N> create issue, <N> skip. Ready to proceed?",
       header: "Final Plan",
       options: [
         { label: "Approve", description: "Proceed to remediation" },
         { label: "Restart review", description: "Walk through all items again from the beginning" },
         { label: "Need more tools", description: "Escalate to interview or update-tooling for additional tools" }
       ],
       multiSelect: false
     }]
   })
   ```

Based on the response:
- **Approve**: Proceed to Step 8 (Post PR Comment).
- **Restart review**: Return to Step 5 (present overview, then walk through items again).
- **Need more tools** (or "Other" requesting tools): Write the signal file:
  ```bash
  echo "interview" > ./claude-reviews/$0/.next-stage
  # or
  echo "update-tooling" > ./claude-reviews/$0/.next-stage
  ```

### Step 8: Post PR Comment (after approval)

```bash
gh pr comment "claude/review/$0" --body "**Remediation Plan Approved**

- Fix now: <N> items
- Create issues: <N> items
- Skip: <N> items

Proceeding to remediation."
```

## Stage Transition Signal

**Rules:**
- Write exactly one stage name, nothing else
- Only write this file if you want a NON-DEFAULT transition
- If you do not write this file, the orchestrator advances to `remediation` (default)

**When to signal:**
- `interview` -- if the user wants to discuss more tools or reprioritize
- `update-tooling` -- if approved tools need installing for remediation
- `remediation-plan` -- if you need a fresh pass (should be rare)
- Default (advance to remediation) is correct when the user approves the plan.

## Re-trigger Behavior

If re-triggered and `Remediation-Plan.md` already exists:

1. Read the existing plan
2. Present the full plan overview (Step 5)
3. Walk through each item sequentially for per-item approval (Step 6)
4. Finalize, commit, push, and present the final summary for approval (Step 7)
