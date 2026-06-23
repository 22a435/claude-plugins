---
name: inventory
description: Read every open GitHub issue (full comment threads) and in-code TODOs, and build a structured inventory. Invoke with /triage:inventory <session-number>.
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash, Agent, Write, Edit, WebFetch
---

# Inventory Phase

You are performing the **inventory** stage of an issue-triage workflow. Your job is to build a complete, structured inventory of everything that could become work: every open GitHub issue (read in full -- threads included) and every genuine in-code TODO.

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
- **Input document:** `./claude-triages/$0/Session.md`
- **Output document:** `./claude-triages/$0/Inventory.md`

## Instructions

### Step 1: Pull the open issue set

```bash
gh issue list --state open --limit 500 --json number,title,labels,author,createdAt,updatedAt,url > /tmp/triage-issues-$0.json
```

Keep this scratch file in `/tmp` (never under `./claude-triages/` -- the only file you write there is `Inventory.md`). Use `jq` to drive the rest of the stage from it.

### Step 2: Read every issue in full (parallel subagents)

Batch the issues (e.g. 5-10 per subagent) and launch parallel `Agent` calls (model: sonnet) to read each issue's **full thread**:

```bash
gh issue view <n> --json number,title,body,labels,comments,url
```

Each subagent must, for every issue in its batch:
- Read the body **and every comment**. Resolve what the issue *actually* asks now (replies frequently expand, narrow, or supersede the original body).
- Follow links that look relevant -- referenced issues (`gh issue view`), PRs (`gh pr view`), commits, and docs (WebFetch for external URLs) -- and fold that context in.
- Return a structured summary per issue (NOT written to disk -- returned as text): number, one-line current ask, affected subsystem/area, any **design decision or open question** the issue hinges on, explicit cross-references (other #issues/PRs it mentions or that mention it), labels, and age.

Remind every subagent of the **Subagent write boundary** above.

### Step 3: Scan for in-code TODOs

Find genuine unfinished-work markers in the codebase (these are *candidate* items, not yet issues):

```bash
grep -rnE '\b(TODO|FIXME|XXX|HACK)\b' \
  --include='*.*' \
  -- . \
  | grep -vE '/(node_modules|\.git|dist|build|vendor|\.next|target)/' \
  | head -300
```

Adjust excludes to the repo. For each marker, capture `path:line`, the surrounding intent (read a few lines of context), and the subsystem it lives in. Do **not** treat every marker as real work -- note obvious noise (e.g. TODOs inside vendored code, or "TODO: nothing" placeholders) so the cluster stage can skip them. The reconcile and cluster stages decide which TODOs become real work.

### Step 4: Write Inventory.md

Synthesize all subagent results into `./claude-triages/$0/Inventory.md`:

```
# Triage Inventory: Session #<N>

## Summary
- **Open issues:** <count>
- **In-code TODO markers:** <count> (<count> look like genuine work, <count> likely noise)
- **Distinct subsystems touched:** <list>

## Open Issues

### Issue #<n>: <title>
- **URL:** <url>
- **Current ask (from full thread):** <what the issue actually asks now, accounting for comments>
- **Subsystem/area:** <area>
- **Design decision / open question it hinges on:** <the key undecided question, or "none -- well-specified">
- **Cross-references:** <#issues/PRs it links to or that link to it, or "none">
- **Labels:** <labels>  · **Age:** <opened date, last update>
- **Thread notes:** <anything important that lives only in the comments>

(repeat for every open issue)

## In-Code TODO Candidates

### <path>:<line>
- **Marker:** <TODO/FIXME/XXX/HACK text>
- **Intent:** <what it implies should be done>
- **Subsystem/area:** <area>
- **Looks like:** <genuine work | likely noise -- reason>

(repeat for every genuine marker; group trivially)

## Observations
<Cross-cutting patterns worth flagging for reconcile/cluster: clusters of related issues, repeated themes, issues that look already-done, obvious duplicates. This is a hint list, not a decision.>
```

### Step 5: Commit, push, and comment

```bash
git add ./claude-triages/$0/Inventory.md
git commit -m "claude-triage(inventory): inventory of open issues and TODOs [session #$0]"
git push
gh pr comment "claude/triage/$0" --body "**Inventory complete (session #$0):** <N> open issues read in full, <M> in-code TODO candidates catalogued. Proceeding to reconcile."
```

## Stage Transition Signal

When running under the `triage` orchestrator, request a non-default transition by writing the target stage name to `./claude-triages/$0/.next-stage`.

**Rules:**
- Write exactly one stage name, nothing else
- Only write this file for a NON-DEFAULT transition
- If you do not write this file, the orchestrator advances to `reconcile` (default)
- The orchestrator validates your request -- invalid transitions are ignored

**When to signal:**
- Re-run inventory (e.g., the issue list was truncated and you need another pass): `echo "inventory" > ./claude-triages/$0/.next-stage`
- Default (advance to `reconcile`) is correct in most cases.

## Re-trigger Behavior

If re-triggered, append a new section:

```
---

## Additional Inventory (triggered during <stage> phase)

### Reason
<why more inventory was needed>

### New Items
<new issues/TODOs found>
```

Do not modify the original sections unless correcting a factual error (mark in-place edits clearly).
