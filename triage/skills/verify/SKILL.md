---
name: verify
description: Confirm the GitHub state matches the approved triage plan -- every planned close closed, every new issue created, no orphans -- and salvage failed operations. Invoke with /triage:verify <session-number>.
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash, Write, Edit
---

# Verify Phase

You are performing the **verify** stage of an issue-triage workflow. Your job is to confirm that the GitHub issue state now matches the approved plan, and to salvage any operation the consolidate stage failed to apply.

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
- **Input documents:** `./claude-triages/$0/Triage.md`, `./claude-triages/$0/Cluster.md`, `./claude-triages/$0/Interview.md`
- **Output document:** `./claude-triages/$0/Verify.md`

## Instructions

### Step 1: Reconstruct the expected end-state

From `Triage.md` (the actions taken) cross-checked against the approved plan (`Cluster.md` as amended by `Interview.md`), build the expected end-state:
- Every issue that should now be **closed**
- Every bundle issue that should now **exist (open)** with its absorbs/decisions sections
- Every issue that should have been **grown**

### Step 2: Check GitHub against expectations

```bash
gh issue list --state all --limit 500 --json number,state,title,labels > /tmp/triage-poststate-$0.json
```
(Scratch file in `/tmp` -- the only file you write under `./claude-triages/` is `Verify.md`.)

For each expected action, verify it actually happened:
- Planned closes -- confirm `state == CLOSED`. Any still OPEN is a **gap**.
- Bundle issues -- confirm each created/grown issue exists and is OPEN with the expected body sections (`gh issue view <n>`). A missing bundle issue is a **gap** (its absorbed issues may have been closed pointing at a non-existent successor -- high priority).
- Absorbed issues -- confirm closed AND that their closing comment points at a successor that exists.

Also flag **orphans**: any issue closed pointing at a successor that does not exist, or any absorbed issue left open.

### Step 3: Salvage gaps

For each gap, apply the missing operation directly (verify is allowed to mutate to repair):
- Missing close -> post the close comment and close it.
- Missing bundle issue -> recover its draft from `Cluster.md`, create it, and fix the pointers in any prematurely-closed absorbed issues (`gh issue comment`).
- Broken pointer -> add a corrected cross-reference comment.

If the gaps indicate the plan itself was inconsistent (not just a failed API call), do not improvise a new plan -- signal back to `consolidate` (or `interview`) instead.

### Step 4: Write Verify.md

```
# Triage Verification: Session #<N>

## Result
- **Status:** PASS (state matches approved plan) | REPAIRED (gaps salvaged) | FAIL (signalling back)
- **Expected closes:** <n> · confirmed <n> · salvaged <n>
- **Expected bundle issues:** <n> · confirmed <n> · salvaged <n>
- **Orphans found:** <n> · fixed <n>

## Checks
| Expected action | Observed | Resolution |
|---|---|---|
| close #<n> | CLOSED / still OPEN | ok / salvaged |
| bundle #<n> exists | OPEN / missing | ok / recreated |

## Salvage Actions Taken
<each repair, or "None -- everything matched.">

## Final Open Backlog
<the resulting open issue list -- numbers + titles -- so the report shows the clean end state>
```

### Step 5: Commit, push, and comment

```bash
git add ./claude-triages/$0/Verify.md
git commit -m "claude-triage(verify): verify GitHub state matches plan [session #$0]"
git push
gh pr comment "claude/triage/$0" --body "**Verify complete (session #$0):** <PASS | REPAIRED N gaps | FAIL>. Final open backlog: <N> issues."
```

## Stage Transition Signal

Write the target stage name to `./claude-triages/$0/.next-stage` for a non-default transition.

**When to signal:**
- `consolidate` -- if gaps reflect plan inconsistency that needs the consolidate stage to redo work: `echo "consolidate" > ./claude-triages/$0/.next-stage`
- Default (advance to `integrate`) is correct once the GitHub state matches the plan (PASS or REPAIRED).

## Re-trigger Behavior

If re-triggered, append a `## Re-verification (triggered during <stage> phase)` section. Do not overwrite the original verification record.
