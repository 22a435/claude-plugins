---
name: integrate
description: Prepare the review branch for merge. Rebases or merges main, resolves conflicts. Invoke with /deep-review:integrate <session-number>.
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash, Agent, Write, Edit
---

# Integration Phase

You are performing the **integration** stage of a deep codebase review. All review analysis, planning, remediation, and verification are complete. Your job is to ensure the review branch is compatible with the current state of main and ready to merge.

## Workflow Context

This skill is one stage of a multi-stage deep review workflow orchestrated by the `deep-review` CLI.

- **Branch:** `claude/review/<session-number>` (created by the orchestrator during setup)
- **Work directory:** `./claude-reviews/<session-number>/` -- each stage produces one document here
- **Document ownership:** You may READ any prior document. Only WRITE to your own output document inside `./claude-reviews/$0/` (where `$0` is the session number passed as your argument). Never create files, directories, or write anywhere else under `./claude-reviews/`. When re-triggered, APPEND new sections -- never delete or overwrite existing content. Mark in-place edits with `> [IN-PLACE EDIT during <stage> phase]: <reason>`.
- **Commits:** Format: `claude-review(<stage>): <description> [session #<N>]`. Commit and push after completing the stage.
- **PR updates:** Post a summary to the PR thread (via `gh pr comment`) after each stage.
- **No self-loop:** Do not use `/loop`, `ScheduleWakeup`, or recursive `claude` invocations to re-run this skill. For short waits, run the command synchronously with `Bash` (it blocks until completion); for long waits, use `Bash` with `run_in_background` and `Monitor`. If you cannot finish in one pass, commit your partial progress and write your own stage name to `.next-stage` -- the orchestrator re-enters the stage within its loop-safety limits. Never re-invoke yourself.
- **Deferral hierarchy (never silently drop, never over-file):** Pre-existing bugs are not grounds for dismissal -- leave the codebase in the best working order regardless of origin. When work surfaces that you will not finish in this PR, walk this hierarchy and stop at the first tier that fits: **(1) Fix it in this PR** -- the default, and hard; "complex", "tedious", "touches many files", or "would take a while" are NOT reasons to defer, only a genuine Create-Issue criterion is (a tradeoff the user must decide / architectural refactor / high blast radius / team discussion / breaking upgrade / benchmark-needed). **(2) Append to a follow-up already filed in this run** -- if a follow-up you filed (or will file) this run naturally covers it, add it there rather than opening a second issue. **(3) Append to an existing open backlog issue** -- before filing anything new, search the backlog (`gh issue list --state open --limit 200 --json number,title,labels,body`); if an open issue already covers the area, comment the new context onto it instead of creating a duplicate. **(4) File one new, bundled issue** -- only if no tier above fits; bundle every co-deferred finding from this run that shares a subsystem or design decision into the SAME issue (one well-scoped issue, never one-per-finding). Filing a follow-up is a commitment that the proper fix exceeds this PR's scope -- not a way to avoid work; never leave a deferred finding as a document-only note, and record which tier each deferral took and why.
- **Read issues in full:** When you read a GitHub issue, read the *entire* thread -- the body **and every comment/reply** -- plus any linked issues, PRs, commits, or docs that look relevant. Critical scope and context often live in replies, not the original body; missing them causes under-scoped work. Treat the whole thread as the source of truth for what the issue actually asks.

## Context
- **Session number:** $0 (the review session number passed as your argument)
- **Work directory:** `./claude-reviews/$0/`
- **Branch:** `claude/review/$0`
- **All documents available for reference** (read as needed)
- **Output document:** `./claude-reviews/$0/Integration.md`

## Instructions

### Step 1: Check Branch State

```bash
git fetch origin main
git log --oneline main..HEAD    # Commits on this branch
git log --oneline HEAD..origin/main  # Commits on main since branch point
```

If main has not moved since the branch was created (no new commits), integration is trivial:

```
# Integration Report: Session #<number>

## Summary
Main has not diverged. No integration needed. Branch is ready for merge.
```

Write this to Integration.md, commit, push, and signal `done` to skip redundant post-integration re-verification:
```bash
echo "done" > ./claude-reviews/$0/.next-stage
```

### Step 2: Rebase onto Main

If main has moved, rebase the review branch:

```bash
git rebase origin/main
```

### Step 3: Resolve Conflicts

If the rebase encounters conflicts:

1. **Examine each conflict** -- read the conflicting files to understand both sides
2. **For mechanical conflicts** (both sides changed nearby lines but the intent is clear): resolve them directly
3. **For semantic conflicts** (both sides changed the same logic, and the correct resolution is ambiguous): escalate to the user with:
   - What file and function is conflicted
   - What the review branch intended
   - What main changed
   - Your recommended resolution (if you have one)
   - Ask the user to decide

After resolving each file:
```bash
git add <resolved-file>
```

Once all conflicts are resolved:
```bash
git rebase --continue
```

### Step 4: Verify the Rebase

After a successful rebase, do a quick sanity check:
- Ensure the code compiles/parses without errors
- Run a quick smoke test if available
- Check that no files were accidentally deleted or duplicated

### Step 5: Force Push the Rebased Branch

```bash
git push --force-with-lease origin claude/review/$0
```

Note: `--force-with-lease` is safe here because this is a review branch that only this workflow writes to.

### Step 6: Write Integration.md

```
# Integration Report: Session #<number>

## Summary
- **Main divergence:** <N> commits on main since branch point
- **Conflicts:** <none / N files>
- **Resolution:** <automatic / required user input>

## Main Changes Since Branch Point
Brief summary of what changed on main (from git log).

## Conflicts Resolved

### <file path>
- **Nature of conflict:** <description>
- **Resolution:** <what was chosen and why>
- **User input required:** <yes/no>

## Post-Integration Status
- **Rebase:** Successful
- **Force push:** Complete
- **Smoke test:** PASS/FAIL

## Note
If rebase introduced changes, the orchestrator repeats the verify->integrate
pipeline. Integration.md documents only the rebase/merge process itself.
```

### Step 7: Commit and Push

**Important:** Commit ALL files changed during this stage, not just the integration document.

```bash
git add -A
git commit -m "claude-review(integrate): integration complete [session #$0]"
git push
```

Post to PR:
```bash
gh pr comment "claude/review/$0" --body "<integration summary -- conflicts resolved, ready for re-verification>"
```

### Step 8: Signal Transition

Signal `verify` to re-check that remediations survived the rebase:
```bash
echo "verify" > ./claude-reviews/$0/.next-stage
```

## Important Notes

- **Always signal a transition:** write `done` (main hasn't moved) or `verify` (rebase happened) to `.next-stage`. The orchestrator re-runs the verify->integrate pipeline after a rebase to confirm remediations are intact.
- Use `--force-with-lease` (never `--force`) when pushing after rebase.
- If the rebase is hopelessly complex (many conflicts across many files), suggest to the user that a merge commit might be more appropriate, and ask how they want to proceed.
- This skill may be re-run multiple times if the PR stays open while main continues to move. Each run appends to Integration.md.

## Stage Transition Signal

When running under the `deep-review` orchestrator, you can request a transition to a different stage by writing the target stage name to `./claude-reviews/$0/.next-stage`.

**Rules:**
- Write exactly one stage name, nothing else
- Always write this file -- integrate must always signal its next stage
- The orchestrator validates your request -- invalid transitions are ignored

**When to signal:**
- `done` -- main has not moved, no integration was needed. Branch is ready to merge:
  ```bash
  echo "done" > ./claude-reviews/$0/.next-stage
  ```
- `verify` -- rebase happened (main had new commits). Repeats the verify->integrate pipeline to confirm remediations survived the rebase:
  ```bash
  echo "verify" > ./claude-reviews/$0/.next-stage
  ```

## Re-trigger Behavior

If re-triggered, append a new section:

```
---

## Re-integration (<date>)

### Reason
<main moved again / previous integration had issues>

### Changes on Main
...

### Conflicts and Resolution
...
```
