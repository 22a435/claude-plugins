---
name: reconcile
description: Classify each inventoried item against the current codebase -- already-fixed, duplicate, or still-live -- with evidence. Invoke with /triage:reconcile <session-number>.
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash, Agent, Write, Edit, WebFetch
---

# Reconcile Phase

You are performing the **reconcile** stage of an issue-triage workflow. Your job is to confront every inventoried item with the *current* state of the codebase and decide whether it is already-fixed (closeable), a duplicate of another item, or still-live work.

## Workflow Context

This skill is one stage of a multi-stage issue-triage workflow orchestrated by the `triage` CLI.

- **Branch:** `claude/triage/<session-number>` (created by the orchestrator during setup)
- **Work directory:** `./claude-triages/<session-number>/` -- each stage produces one document here
- **Document ownership:** You may READ any prior document. Only WRITE to your own output document inside `./claude-triages/$0/` (where `$0` is the session number passed as your argument). Never create files, directories, or write anywhere else under `./claude-triages/`. When re-triggered, APPEND new sections -- never delete or overwrite existing content. Mark in-place edits with `> [IN-PLACE EDIT during <stage> phase]: <reason>`.
- **Commits:** Format: `claude-triage(<stage>): <description> [session #<N>]`. Commit and push after completing the stage.
- **PR updates:** Post a summary to the PR thread (via `gh pr comment`) after completing the stage.
- **Subagent write boundary:** Subagents in this stage must NOT create, edit, or write any files under `./claude-triages/`. Only this parent session writes the output document. Include this constraint in every subagent prompt you compose.
- **Subagent cost:** Information-gathering subagents should use `model: "sonnet"`. This parent session (opus) handles synthesis.
- **No self-loop:** Do not use `/loop`, `ScheduleWakeup`, or recursive `claude` invocations to re-run this skill. For short waits, run the command synchronously with `Bash` (it blocks until completion); for long waits, use `Bash` with `run_in_background` and `Monitor`. If you cannot finish in one pass, commit your partial progress and write your own stage name to `.next-stage` -- the orchestrator re-enters the stage within its loop-safety limits. Never re-invoke yourself.
- **Read issues in full:** When you read a GitHub issue, read the *entire* thread -- the body **and every comment/reply** -- plus any linked issues, PRs, commits, or docs that look relevant. Critical scope and context often live in replies, not the original body; missing them causes under-scoped work. Treat the whole thread as the source of truth for what the issue actually asks.

## Context
- **Session number:** $0 (the triage session number passed as your argument)
- **Work directory:** `./claude-triages/$0/`
- **Input documents:** `./claude-triages/$0/Inventory.md` (and `Session.md`)
- **Output document:** `./claude-triages/$0/Reconcile.md`

## Instructions

### Step 1: Read the inventory

Read `Inventory.md` in full. You will classify every open issue and every genuine TODO candidate it lists.

### Step 2: Investigate the current code (parallel subagents)

Batch the items and launch parallel `Agent` calls (model: sonnet) to investigate the **current** codebase for each. Each subagent must, per item, gather evidence and return one of these classifications (as text, not written to disk):

- **ALREADY-FIXED** -- the described problem no longer exists / the requested feature is already present in the code. Require concrete evidence: the file/function/test that demonstrates it, ideally with a `path:line`. Note if the fixing commit/PR can be identified (`git log -S`, `gh pr list --search`).
- **DUPLICATE** -- the item is substantially the same as another inventoried item (give the other item's id and why they're the same).
- **STILL-LIVE** -- the work genuinely remains. Confirm by pointing at where it would need to happen.
- **UNCLEAR** -- evidence is ambiguous; explain what's missing. (The cluster/interview stages will treat UNCLEAR as still-live but flag it.)

When an issue's thread (from Inventory.md) already records that it was fixed or superseded, weight that heavily -- but still confirm against the code.

Remind every subagent of the **Subagent write boundary** above. Subagents investigate and report; they do **not** close or modify anything.

### Step 3: Resolve duplicates into clusters

From the DUPLICATE classifications, form duplicate-clusters: pick one **canonical** item per cluster (usually the most complete / oldest with the most thread context) and list the others as absorbed-by-canonical. Do not pick a canonical that is itself ALREADY-FIXED.

### Step 4: Write Reconcile.md

Write `./claude-triages/$0/Reconcile.md`:

```
# Triage Reconciliation: Session #<N>

## Summary
- **Already-fixed (close candidates):** <count>
- **Duplicate clusters:** <count> (absorbing <count> issues)
- **Still-live:** <count>
- **Unclear:** <count>

## Already Fixed -- Close Candidates
### Issue #<n>: <title>
- **Evidence it is done:** <file:line / test / behavior that proves it>
- **Fixing commit/PR (if found):** <ref or "unknown">
- **Proposed close comment:** <one line to post when closing, cross-referencing the evidence>

## Duplicate Clusters
### Cluster D<k>: <theme>
- **Canonical:** #<n> (<why this one>)
- **Absorbed:** #<a>, #<b> (<why each is the same>)

## Still Live
### Issue #<n> / TODO <path:line>: <title>
- **Confirmed remaining because:** <where the work still needs to happen>
- **Subsystem/area:** <area>
- **Design decision / open question it hinges on:** <carried forward from inventory, refined>

## Unclear
### Issue #<n>: <title>
- **Why unclear:** <what evidence is missing>
- **Default handling:** treat as still-live, flag in interview
```

### Step 5: Commit, push, and comment

```bash
git add ./claude-triages/$0/Reconcile.md
git commit -m "claude-triage(reconcile): classify items against current code [session #$0]"
git push
gh pr comment --body "**Reconcile complete (session #$0):** <X> already-fixed, <Y> duplicate clusters, <Z> still-live. Proceeding to cluster."
```

## Stage Transition Signal

Write the target stage name to `./claude-triages/$0/.next-stage` for a non-default transition.

**When to signal:**
- `inventory` -- if reconciliation reveals the inventory missed items or needs fuller threads: `echo "inventory" > ./claude-triages/$0/.next-stage`
- Default (advance to `cluster`) is correct in most cases.

## Re-trigger Behavior

If re-triggered, append a new `## Additional Reconciliation (triggered during <stage> phase)` section with the reason and new classifications. Do not modify original sections unless correcting a factual error (mark in-place edits clearly).
