---
name: interview
description: Present the full triage plan (closes, merges, consolidated bundles) for user approval. No GitHub mutations happen here. Invoke with /triage:interview <session-number>.
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash, Write, Edit, AskUserQuestion
---

# Interview Phase (Whole-Plan Approval Gate)

You are performing the **interview** stage of an issue-triage workflow. This is the **approval gate**: present the complete triage plan, let the user edit it or ask questions, and only advance to `consolidate` once the user has approved the final plan. **You make NO changes to GitHub in this stage** -- no closing, no creating, no commenting on triaged issues. The only writes you make are to this session's `Interview.md`.

## Workflow Context

This skill is one stage of a multi-stage issue-triage workflow orchestrated by the `triage` CLI.

- **Branch:** `claude/triage/<session-number>` (created by the orchestrator during setup)
- **Work directory:** `./claude-triages/<session-number>/` -- each stage produces one document here
- **Document ownership:** You may READ any prior document. Only WRITE to your own output document inside `./claude-triages/$0/` (where `$0` is the session number passed as your argument). Never create files, directories, or write anywhere else under `./claude-triages/`. When re-triggered, APPEND new sections -- never delete or overwrite existing content. Mark in-place edits with `> [IN-PLACE EDIT during <stage> phase]: <reason>`.
- **Commits:** Format: `claude-triage(<stage>): <description> [session #<N>]`. Commit and push after completing the stage.
- **PR updates:** Post a summary to the PR thread (via `gh pr comment`) after completing the stage.
- **No self-loop:** Do not use `/loop`, `ScheduleWakeup`, or recursive `claude` invocations to re-run this skill. For short waits, run the command synchronously with `Bash` (it blocks until completion); for long waits, use `Bash` with `run_in_background` and `Monitor`. If you cannot finish in one pass, commit your partial progress and write your own stage name to `.next-stage` -- the orchestrator re-enters the stage within its loop-safety limits. Never re-invoke yourself.
- **Read issues in full:** When you read a GitHub issue, read the *entire* thread -- the body **and every comment/reply** -- plus any linked issues, PRs, commits, or docs that look relevant. Critical scope and context often live in replies, not the original body; missing them causes under-scoped work. Treat the whole thread as the source of truth for what the issue actually asks.

## Context
- **Session number:** $0 (the triage session number passed as your argument)
- **Work directory:** `./claude-triages/$0/`
- **Input documents:** `./claude-triages/$0/Cluster.md` (the proposed plan), `Reconcile.md`, `Inventory.md`
- **Output document:** `./claude-triages/$0/Interview.md`

## Instructions

### Step 1: Read the proposed plan

Read `Cluster.md` fully (and consult `Reconcile.md` / `Inventory.md` for detail when the user probes). This is the plan you are presenting.

### Step 2: Present the plan and walk the user through it

First post the high-level shape so the user sees the whole picture: starting issue count, how many closes, how many merges, how many resulting bundles, and the net change. Then use `AskUserQuestion` to walk the user through the **decision points**, grouped to keep the number of prompts reasonable. Do not ask one question per issue if a group can be approved together; do single out anything risky.

Cover, in order:
1. **Closes (already fixed):** confirm the close list. Single out any close whose evidence was thin or that came from an UNCLEAR classification. Offer: approve all / review specific ones / keep open.
2. **Merges (duplicates):** confirm each duplicate cluster and its canonical. Offer: approve / change canonical / un-merge.
3. **Bundles:** for each bundle, present its scope, the decisions it anchors, and what it absorbs. Offer: approve / adjust scope / split / merge with another bundle / change new-issue-vs-grow-existing disposition. This is where the user most often pushes back -- if they want a bundle larger or smaller, capture it precisely.
4. **Open questions:** resolve the items Cluster.md flagged.

When an answer is ambiguous or raises a new question, issue a follow-up `AskUserQuestion` to clarify before moving on. The tool always provides an "Other" path, so the user can give free-form direction.

### Step 3: Decide whether re-planning is needed

- If the user's edits are **local** (drop a close, change a canonical, adjust a bundle's scope, move an item between bundles), record them in `Interview.md` as the authoritative deltas over `Cluster.md` -- the consolidate stage will apply `Cluster.md` **as amended by** `Interview.md`.
- If the user's edits are **structural** (they want the bundling fundamentally reworked, or reconciliation redone), do not try to re-derive it here. Record the direction in `Interview.md` and signal `cluster` (or `reconcile`) so that stage re-runs with the new guidance.

### Step 4: Write Interview.md

```
# Triage Interview: Session #<N>

## Plan Status
- **Decision:** APPROVED (proceed to consolidate) | RE-PLAN (signal cluster/reconcile)
- **Presented:** <A closes, B merges, K bundles>

## Approved Closes
<final close list -- issue numbers, or "as proposed in Cluster.md">

## Approved Merges
<final merge map, or "as proposed">

## Approved Bundles
<final bundle list with any scope amendments; for each, note new-issue vs grow-existing and the final absorbed set>

## Amendments to Cluster.md
<Explicit deltas the user requested: "Bundle B2 dropped TODO x", "Issue #14 kept open", "canonical for cluster D1 changed to #9". The consolidate stage applies Cluster.md AS AMENDED by this list. If none, write "None -- plan approved as proposed.">

## Notes / Rationale
<Why the user made non-obvious changes, for the audit trail.>
```

### Step 5: Commit, push, and comment

```bash
git add ./claude-triages/$0/Interview.md
git commit -m "claude-triage(interview): triage plan <approved|sent back for re-planning> [session #$0]"
git push
gh pr comment "claude/triage/$0" --body "**Interview complete (session #$0):** plan <APPROVED -- proceeding to consolidate | sent back to <stage> for re-planning>. <summary of final counts>."
```

## Stage Transition Signal

Write the target stage name to `./claude-triages/$0/.next-stage` for a non-default transition.

**When to signal:**
- `cluster` -- the user wants the bundling reworked: `echo "cluster" > ./claude-triages/$0/.next-stage`
- `reconcile` -- the user disputes the fixed/duplicate classifications: `echo "reconcile" > ./claude-triages/$0/.next-stage`
- Default (advance to `consolidate`) is correct **only when the plan is approved**. Never advance to consolidate with an unapproved or partially-reviewed plan.

## Re-trigger Behavior

If re-triggered after a re-plan, append a `## Re-interview (triggered during <stage> phase)` section presenting and approving the revised plan. Do not overwrite the prior approval record.
