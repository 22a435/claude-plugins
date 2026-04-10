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

### Step 5: Present the Plan to the User

Present the full remediation plan to the user as text. Then use the `AskUserQuestion` tool to collect their decision:

```
AskUserQuestion({
  questions: [{
    question: "How would you like to proceed with this remediation plan?",
    header: "Remed Plan",
    options: [
      { label: "Approve", description: "Plan looks good -- proceed to remediation" },
      { label: "Move items", description: "Move findings between Fix Now / Create Issue / Skip categories" },
      { label: "Edit items", description: "Add or remove specific items from the plan" },
      { label: "Need more tools", description: "Escalate to interview or update-tooling for additional tools" }
    ],
    multiSelect: false
  }]
})
```

The user can also select "Other" to provide free-text feedback.

### Step 6: Handle Feedback

Based on the user's `AskUserQuestion` response:

**"Approve"** -- Proceed to Step 7 (Post PR Comment).

**"Move items"** or **"Edit items"** (or "Other" with specific instructions):
- Edit `Remediation-Plan.md` in place with the requested changes
- Commit and push:
  ```bash
  git add ./claude-reviews/$0/Remediation-Plan.md
  git commit -m "claude-review(remediation-plan): revise plan -- <summary> [session #$0]"
  git push
  ```
- Present the updated plan and return to Step 5 (re-invoke `AskUserQuestion` for approval)

**"Need more tools"** (or "Other" requesting tools):
- Write the signal file:
  ```bash
  echo "interview" > ./claude-reviews/$0/.next-stage
  # or
  echo "update-tooling" > ./claude-reviews/$0/.next-stage
  ```

### Step 7: Post PR Comment (after approval)

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
2. Present it to the user, then use `AskUserQuestion` to ask how to proceed:
   ```
   AskUserQuestion({
     questions: [{
       question: "This remediation plan already exists from a previous run. How would you like to proceed?",
       header: "Prior Plan",
       options: [
         { label: "Approve", description: "Plan looks good as-is -- proceed to remediation" },
         { label: "Move items", description: "Move findings between Fix Now / Create Issue / Skip categories" },
         { label: "Edit items", description: "Add or remove specific items from the plan" },
         { label: "Need more tools", description: "Escalate to interview or update-tooling for additional tools" }
       ],
       multiSelect: false
     }]
   })
   ```
3. If edits requested: edit in place (git history serves as audit trail)
4. Commit, push, and return to Step 5 to re-invoke `AskUserQuestion` for approval
