---
name: abandon
description: User-gated teardown for an issue that should not ship. Verifies the case for abandoning, asks the user for explicit approval, then closes out the PR/branch/issue or returns to the signaling stage. Invoke with /issue-workflow:abandon <issue-number>.
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash, Agent, Write, Edit, AskUserQuestion
---

# Abandon Phase

You are performing the **abandon** stage of an issue workflow. A prior stage concluded that this issue should not ship and signaled `abandon`. Your job is to independently verify that case, present it to the user, and act ONLY on their explicit decision. You are a safeguard, not a rubber stamp -- and never an executioner without approval.

## Workflow Context

This skill is one stage of a multi-stage issue-to-PR workflow orchestrated by the `work-issue` CLI.

- **Branch:** `claude/<issue-number>` (created by the orchestrator during setup)
- **Work directory:** `./claude-work/<issue-number>/` -- each stage produces one document here
- **Document ownership:** You may READ any prior document. Only WRITE to your own output document inside `./claude-work/$0/` (where `$0` is the numeric GitHub issue ID passed as your argument). Never create files, directories, or write anywhere else under `./claude-work/`. When re-triggered, APPEND new sections -- never delete or overwrite existing content. Mark in-place edits with `> [IN-PLACE EDIT during <stage> phase]: <reason>`.
- **Commits:** Format: `claude-work(abandon): <description> [#<issue>]`. Commit and push after completing the stage.
- **No self-loop:** Do not use `/loop`, `ScheduleWakeup`, or recursive `claude` invocations to re-run this skill. Never re-invoke yourself.
- **Read issues in full:** When you read a GitHub issue, read the *entire* thread -- the body **and every comment/reply** -- plus any linked issues, PRs, commits, or docs that look relevant. Critical scope and context often live in replies, not the original body; missing them causes under-scoped work. Treat the whole thread as the source of truth for what the issue actually asks.
- **Session result:** After your final commit/push and PR/issue comment, as the very LAST step of the session, write `./claude-work/$0/.session-result.json` (overwrite if present; do NOT commit it): `{"stage": "abandon", "outcome": "complete|partial|blocked", "next_stage_signal": "<stage written to .next-stage, or null>", "summary": "<1-3 factual sentences on what happened>", "artifacts": ["<key files produced or changed>"], "follow_ups": ["<issue refs filed, if any>"], "timestamp": "<UTC ISO-8601>"}`. External tooling reads this file to understand session state -- write it even when blocked or partial.

## Context
- **Issue number:** $0 (numeric GitHub issue ID -- not a title, keyword, or topic name)
- **Work directory:** `./claude-work/$0/`
- **Origin marker:** `./claude-work/$0/.abandon-origin` -- the stage that signaled abandonment
- **Input documents:** ALL existing documents in `./claude-work/$0/` (Issue.md through whatever the origin stage wrote)
- **Output document:** `./claude-work/$0/Abandon.md`

## Instructions

### Step 1: Understand the Proposal

Read `.abandon-origin` to learn which stage signaled abandonment, then read every document in the work directory -- the origin stage's document should contain the reasoning. Read the full issue thread and the PR (if one exists: `gh pr view claude/$0` -- the draft PR is created during plan, so pre-plan abandons have no PR).

### Step 2: Independently Verify the Case

Do not take the origin stage's word for it. Verify each claim with fresh evidence:

- "Already fixed on main" -- fetch and inspect main; find the commit/PR that fixed it.
- "Superseded by #X" -- read #X in full; confirm it actually covers this issue's scope.
- "Obsolete / no longer applies" -- confirm the code, dependency, or requirement it referenced is really gone or changed.
- "Invalid / based on a misunderstanding" -- re-read the issue thread; make sure no comment re-scopes it into something valid.

Form your own recommendation: **abandon** or **continue**. If your verification does NOT support abandonment, say so plainly -- your counter-case goes to the user too.

### Step 3: Write the Proposal to Abandon.md

Write (or append, if re-triggered) `./claude-work/$0/Abandon.md`:

```markdown
# Abandon Proposal: Issue #$0

## Origin
Signaled by the `<origin>` stage on <date>.

## Case for Abandoning
<the origin stage's reasoning, in your words>

## Independent Verification
<claim-by-claim: what you checked, what you found, with links/SHAs>

## Work That Would Be Discarded
<stages completed, commits on the branch, PR state>

## Recommendation
<abandon or continue, and why>
```

### Step 4: Ask the User

Use AskUserQuestion. Summarize the case and your recommendation in the question text (the user may be arriving with no context -- give them enough to decide, including a pointer to Abandon.md for the full detail). Options:

1. **Abandon -- close the issue** (it should never ship: invalid, already fixed, obsolete)
2. **Abandon -- leave the issue open** (this attempt should stop, but the issue stays in the backlog; your findings get commented onto it)
3. **Continue -- return to `<origin>`** (the case is not convincing; resume work)

If the user chooses to abandon, ask a follow-up: delete the remote branch, or keep it? (Default: delete -- the closed PR preserves the commits on GitHub.)

Wait for the user. Never proceed on a timeout, an assumption, or your own recommendation.

### Step 5a: On Approval -- Teardown

Order matters -- preserve the record BEFORE closing anything:

1. Append a `## Decision` section to Abandon.md: what the user chose and any rationale they gave.
2. Commit and push: `claude-work(abandon): abandon issue #$0 -- <short reason> [#$0]`.
3. Comment on the issue: a concise summary of the findings, why work was abandoned, and a link to the PR/branch for the record.
4. If a PR exists, close it: `gh pr close claude/$0 --comment "<one-line reason, pointer to Abandon.md>"`.
5. If the user chose to close the issue: `gh issue close $0 --reason "not planned"`.
6. If the user chose branch deletion: `git push origin --delete claude/$0` (only AFTER the push in step 2 succeeded).
7. Write the marker the orchestrator checks: `touch ./claude-work/$0/.abandoned`
8. Signal completion: `echo "done" > ./claude-work/$0/.next-stage`
9. Write `.session-result.json` (outcome `complete`, next_stage_signal `done`).

### Step 5b: On Rejection -- Return to Origin

1. Append a `## Decision` section to Abandon.md: the user declined, their rationale, and any new direction they gave (later stages will read this).
2. Commit and push.
3. Signal the origin stage: `echo "<origin>" > ./claude-work/$0/.next-stage` -- the orchestrator only accepts the stage recorded in `.abandon-origin` (or `done`); anything else is rejected.
4. Write `.session-result.json` (outcome `complete`, next_stage_signal `<origin>`).

## Hard Rules

- **Nothing is closed, deleted, or commented before the user approves in Step 4.** No exceptions -- not even when the case is overwhelming.
- Never force-push, never delete the work directory, never rewrite branch history.
- Only `done` (after teardown) or the recorded origin stage are valid transitions. Do not signal anything else.
- If `.abandon-origin` is missing (e.g., a manual `--resume abandon`), you cannot offer a return-to-origin transition: present the case with only the two abandon options, and tell the user that declining means resuming manually via `work-issue $0 --resume <stage>`.
- If the user's decision does not fit the options (they redirect scope, want a different stage, etc.), record it in Abandon.md, make NO GitHub mutations, write no `.next-stage` signal, and tell the user which `--resume` invocation matches their intent.

## Re-trigger Behavior

If this skill runs again (a later signal after a rejected abandon), APPEND a new dated proposal section to Abandon.md -- never overwrite the earlier proposal or decision.
