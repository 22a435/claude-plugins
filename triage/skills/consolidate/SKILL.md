---
name: consolidate
description: Apply the APPROVED triage plan to GitHub -- create bundle issues, close fixed/duplicate/absorbed issues with cross-references, relabel. Invoke with /triage:consolidate <session-number>.
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash, Agent, Write, Edit
---

# Consolidate Phase (Apply the Approved Plan)

You are performing the **consolidate** stage of an issue-triage workflow. The plan has been approved in the interview stage. Your job is to apply it on GitHub: create the consolidated bundle issues, close the already-fixed / duplicate / absorbed issues with clear cross-references, and relabel as needed.

## Workflow Context

This skill is one stage of a multi-stage issue-triage workflow orchestrated by the `triage` CLI.

- **Branch:** `claude/triage/<session-number>` (created by the orchestrator during setup)
- **Work directory:** `./claude-triages/<session-number>/` -- each stage produces one document here
- **Document ownership:** You may READ any prior document. Only WRITE to your own output document inside `./claude-triages/$0/` (where `$0` is the session number passed as your argument). Never create files, directories, or write anywhere else under `./claude-triages/`. When re-triggered, APPEND new sections -- never delete or overwrite existing content. Mark in-place edits with `> [IN-PLACE EDIT during <stage> phase]: <reason>`.
- **Commits:** Format: `claude-triage(<stage>): <description> [session #<N>]`. Commit and push after completing the stage.
- **PR updates:** Post a summary to the PR thread (via `gh pr comment`) after completing the stage.
- **Subagent write boundary:** Subagents in this stage must NOT create, edit, or write any files under `./claude-triages/`, and must NOT mutate GitHub. Only this parent session writes the output document and runs `gh` mutations. Include this constraint in every subagent prompt you compose.
- **No self-loop:** Do not use `/loop`, `ScheduleWakeup`, or recursive `claude` invocations to re-run this skill. For short waits, run the command synchronously with `Bash` (it blocks until completion); for long waits, use `Bash` with `run_in_background` and `Monitor`. If you cannot finish in one pass, commit your partial progress and write your own stage name to `.next-stage` -- the orchestrator re-enters the stage within its loop-safety limits. Never re-invoke yourself.
- **Read issues in full:** When you read a GitHub issue, read the *entire* thread -- the body **and every comment/reply** -- plus any linked issues, PRs, commits, or docs that look relevant. Critical scope and context often live in replies, not the original body; missing them causes under-scoped work. Treat the whole thread as the source of truth for what the issue actually asks.

## Context
- **Session number:** $0 (the triage session number passed as your argument)
- **Work directory:** `./claude-triages/$0/`
- **Input documents:** `./claude-triages/$0/Cluster.md` (the plan) **as amended by** `./claude-triages/$0/Interview.md` (the approval + deltas)
- **Output document:** `./claude-triages/$0/Triage.md`

## Authority and Safety

Act **only** on the approved plan. The source of truth is `Cluster.md` **as amended by** `Interview.md`'s "Amendments to Cluster.md" section. If `Interview.md` does not exist or its "Plan Status" is not APPROVED, do **not** mutate anything -- write a note in `Triage.md` explaining the block and signal back to `interview`. Never close or create an issue that is not in the approved plan.

## Instructions

### Step 1: Load and reconcile the approved plan

Read `Cluster.md` and `Interview.md`. Build the final action list by applying the interview amendments to the cluster plan:
- **Closes** (already-fixed) -- final set after amendments
- **Merges** (duplicates) -- canonical + absorbed, final set
- **Bundles** -- for each: new-issue vs grow-existing, final scope, final absorbed set, labels
- Confirm Plan Status is APPROVED.

### Step 2: Create / grow the bundle issues FIRST

Create bundle issues before closing anything, so the close comments can point at the new issue number.

- **New bundled issue:**
  ```bash
  gh issue create \
    --title "<bundle title>" \
    --body "<scope checklist, 'Decisions to resolve first' section, 'Absorbs: #x #y', cross-reference: 'Created during triage session #$0. See claude-triages/$0/Cluster.md'>" \
    --label "<labels>"
  ```
- **Grow an existing issue into the bundle:** edit that issue's body to the bundle scope and add the decisions/absorbs sections:
  ```bash
  gh issue edit <n> --body "<updated bundle body>" --add-label "<labels>"
  gh issue comment <n> --body "Expanded into a consolidated bundle during triage session #$0; absorbs #x, #y. See claude-triages/$0/Cluster.md."
  ```

Capture every resulting issue number and URL.

### Step 3: Close fixed / duplicate / absorbed issues with cross-references

For each issue being closed, post a comment explaining why and pointing to its successor, then close. Use the appropriate reason:

- **Already fixed:**
  ```bash
  gh issue comment <n> --body "Closing as already resolved (triage session #$0): <evidence -- file:line / PR>."
  gh issue close <n> --reason completed
  ```
- **Duplicate (absorbed into canonical):**
  ```bash
  gh issue comment <n> --body "Closing as duplicate of #<canonical> (triage session #$0)."
  gh issue close <n> --reason "not planned"
  ```
- **Absorbed into a new bundle:**
  ```bash
  gh issue comment <n> --body "Absorbed into #<bundle-issue> during triage session #$0; tracked there going forward."
  gh issue close <n> --reason "not planned"
  ```

Process closes carefully and check each command's exit status; if a `gh` call fails, record it as a failed action (the verify stage will catch and salvage it) rather than silently moving on.

### Step 4: Write Triage.md

```
# Triage Report: Session #<N>

## Summary
- **Issues at start:** <count>
- **Closed (fixed):** <count>   · **Closed (duplicate):** <count>   · **Closed (absorbed):** <count>
- **Bundle issues created:** <count>   · **Issues grown into bundles:** <count>
- **Open issues after triage:** <count>  (was <start>)

## Bundle Issues Created / Grown
### #<n>: <title>
- **URL:** <url>
- **Disposition:** <new | grown from #<n>>
- **Absorbs:** #<x>, #<y>, TODO <path:line>
- **Decisions to resolve first:** <carried from plan>

## Issues Closed
| Issue | Reason | Pointer | Status |
|---|---|---|---|
| #<n> | fixed/duplicate/absorbed | #<successor or evidence> | closed OK / FAILED |

## Failed Actions (for verify to salvage)
<Any gh command that did not succeed, with the intended action. If none, write "None -- all actions applied cleanly.">
```

### Step 5: Commit, push, and comment

```bash
git add ./claude-triages/$0/Triage.md
git commit -m "claude-triage(consolidate): apply approved triage plan [session #$0]"
git push
gh pr comment "claude/triage/$0" --body "**Consolidate complete (session #$0):** created <C> bundles, closed <F> fixed / <D> duplicate / <A> absorbed. Open issues: <start> → <end>. Proceeding to verify."
```

## Stage Transition Signal

Write the target stage name to `./claude-triages/$0/.next-stage` for a non-default transition.

**When to signal:**
- `interview` -- if the plan is not approved or is internally inconsistent (do not mutate): `echo "interview" > ./claude-triages/$0/.next-stage`
- Default (advance to `verify`) is correct once the plan has been applied.

## Re-trigger Behavior

If re-triggered (e.g., verify found gaps), append a `## Additional Consolidation (triggered during <stage> phase)` section describing the gap and the actions taken to fix it. Do not re-run already-applied actions; act only on what is still outstanding.
