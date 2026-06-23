---
name: integrate
description: Prepare the triage report branch for merge -- rebase onto main if it has diverged, resolve any conflicts in the report docs. Invoke with /triage:integrate <session-number>.
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash, Write, Edit
---

# Integrate Phase

You are performing the **integrate** stage of an issue-triage workflow. The triage's GitHub mutations are already applied and verified. Your job is to get the **report branch** (which carries the triage artifacts) into a mergeable state: rebase onto the latest `main` and resolve any conflicts in the `claude-triages/` documents.

The orchestrator only invokes this skill when `main` has diverged from the branch; if it had not, integration was handled inline and this skill is skipped.

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
- **Input documents:** all prior session documents
- **Output document:** `./claude-triages/$0/Integration.md`

## Instructions

### Step 1: Rebase onto main

```bash
git fetch origin main
git rebase origin/main
```

The report docs live under `claude-triages/$0/` and are unlikely to conflict with `main`. If a conflict does occur (e.g., another triage session touched a shared file), resolve it preserving **both** sets of changes -- triage reports are append-only artifacts; never discard another session's content. Continue the rebase to completion.

If the rebase is hopeless, abort it (`git rebase --abort`) and record that integration needs manual attention in `Integration.md`, then still proceed to write the report and finish (do not loop forever).

### Step 2: Confirm the triaged GitHub state is unaffected

A report-branch rebase does **not** change GitHub issues, but sanity-check that the verified end-state still holds (no one re-opened a closed issue in the interim):

```bash
gh issue list --state open --limit 500 --json number --jq 'length'
```

Compare against the "Final Open Backlog" count in `Verify.md`. Note any drift (do not act on it -- just record it).

### Step 3: Write Integration.md

```
# Integration Report: Triage Session #<N>

## Summary
- **Rebase:** clean | resolved <n> conflicts | aborted (manual attention needed)
- **GitHub end-state:** matches Verify.md (<N> open) | drifted (<describe>)
- **Branch status:** ready for merge | needs manual attention

## Conflicts Resolved
<files + how, or "none">
```

### Step 4: Commit, push, and comment

```bash
git add ./claude-triages/$0/Integration.md
git commit -m "claude-triage(integrate): rebase report branch onto main [session #$0]"
git push --force-with-lease
gh pr comment "claude/triage/$0" --body "**Integrate complete (session #$0):** branch rebased onto main and ready for merge."
```

(`--force-with-lease` is required because the rebase rewrote history; it is safe on this session branch and the protected-branch hook still blocks pushes to main/master/production.)

## Stage Transition Signal

Write the target stage name to `./claude-triages/$0/.next-stage` for a non-default transition.

**When to signal:**
- `verify` -- if the rebase surfaced something that warrants re-verifying the GitHub state: `echo "verify" > ./claude-triages/$0/.next-stage`
- Default (advance to `done`) is correct once the branch is rebased and ready.

## Re-trigger Behavior

If re-triggered, append a `## Additional Integration (triggered during <stage> phase)` section. Do not overwrite the original integration record.
