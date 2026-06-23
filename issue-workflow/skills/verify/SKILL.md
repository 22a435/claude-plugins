---
name: verify
description: Full verification suite -- re-runs all component checks, integration tests, and repo test suites. Documents failures and signals debug. Invoke with /issue-workflow:verify <issue-number>.
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash, Agent, Write, Edit
---

# Verification Phase

You are performing the **verification** stage of an issue workflow. Your job is to confirm that the implementation is complete, correct, and does not introduce regressions.

## Workflow Context

This skill is one stage of an 8-stage issue-to-PR workflow orchestrated by the `work-issue` CLI.

- **Branch:** `claude/<issue-number>` (created by the orchestrator during setup)
- **Work directory:** `./claude-work/<issue-number>/` -- each stage produces one document here
- **Document ownership:** You may READ any prior document. Only WRITE to your own output document inside `./claude-work/$0/` (where `$0` is the numeric GitHub issue ID passed as your argument). Never create files, directories, or write anywhere else under `./claude-work/`. When re-triggered, APPEND new sections -- never delete or overwrite existing content. Mark in-place edits with `> [IN-PLACE EDIT during <stage> phase]: <reason>`.
- **Commits:** Format: `claude-work(<stage>): <description> [#<issue>]`. Commit and push after completing the stage.
- **PR updates:** Post a summary to the PR thread (via `gh pr comment`) after each stage.
- **Subagent write boundary:** Subagents in this stage must NOT create, edit, or write any files under `./claude-work/`. Only this parent session writes the output document. Include this constraint in every subagent prompt you compose.
- **No self-loop:** Do not use `/loop`, `ScheduleWakeup`, or recursive `claude` invocations to re-run this skill. For short waits, run the command synchronously with `Bash` (it blocks until completion); for long waits, use `Bash` with `run_in_background` and `Monitor`. If you cannot finish in one pass, commit your partial progress and write your own stage name to `.next-stage` -- the orchestrator re-enters the stage within its loop-safety limits. Never re-invoke yourself.
- **Deferral hierarchy (never silently drop, never over-file):** Pre-existing bugs are not grounds for dismissal -- leave the codebase in the best working order regardless of origin. When work surfaces that you will not finish in this PR, walk this hierarchy and stop at the first tier that fits: **(1) Fix it in this PR** -- the default, and hard; "complex", "tedious", "touches many files", or "would take a while" are NOT reasons to defer, only a genuine Create-Issue criterion is (a tradeoff the user must decide / architectural refactor / high blast radius / team discussion / breaking upgrade / benchmark-needed). **(2) Append to a follow-up already filed in this run** -- if a follow-up you filed (or will file) this run naturally covers it, add it there rather than opening a second issue. **(3) Append to an existing open backlog issue** -- before filing anything new, search the backlog (`gh issue list --state open --limit 200 --json number,title,labels,body`); if an open issue already covers the area, comment the new context onto it instead of creating a duplicate. **(4) File one new, bundled issue** -- only if no tier above fits; bundle every co-deferred finding from this run that shares a subsystem or design decision into the SAME issue (one well-scoped issue, never one-per-finding). Filing a follow-up is a commitment that the proper fix exceeds this PR's scope -- not a way to avoid work; never leave a deferred finding as a document-only note, and record which tier each deferral took and why.
- **Read issues in full:** When you read a GitHub issue, read the *entire* thread -- the body **and every comment/reply** -- plus any linked issues, PRs, commits, or docs that look relevant. Critical scope and context often live in replies, not the original body; missing them causes under-scoped work. Treat the whole thread as the source of truth for what the issue actually asks.

## Context
- **Issue number:** $0 (numeric GitHub issue ID -- not a title, keyword, or topic name)
- **Work directory:** `./claude-work/$0/`
- **Input documents:**
  - `./claude-work/$0/Plan.md` (verification checks are defined here)
  - `./claude-work/$0/Execute.md` (what was implemented)
  - `./claude-work/$0/Review.md` (if exists -- review feedback and requested changes)
  - `./claude-work/$0/Integration.md` (if exists -- integration changes, conflict resolutions)
- **Output document:** `./claude-work/$0/Verify.md`

## Instructions

### Step 1: Read Plan and Execution Log

Read `Plan.md` to extract:
- All component-level verification checks
- The full verification suite defined at the end of the plan

Read `Execute.md` to understand:
- What was actually implemented
- Any deviations from the plan
- Implementation notes that affect verification

If `Review.md` exists, read it to understand:
- What changes were requested during review
- What was modified after the initial implementation
- Any areas flagged for closer verification

If `Integration.md` exists, read it to understand:
- What changed during integration (rebase, conflict resolution)
- Which files were affected by merge conflict resolution
- Any areas where integrated changes may have altered behavior

### Step 2: Run Component Verification

For each component in the plan, run its specific verification checks. Use parallel subagents where checks are independent:

- Launch one Agent per component to run its verification checks
- Each agent should report: check description, pass/fail, and output/evidence

Collect all results.

### Step 3: Run Full Verification Suite

Run the end-of-plan verification checks sequentially:
1. End-to-end integration checks from the plan
2. All existing repo test suites -- detect and run them:
   - `npm test`, `npm run test`, `pnpm test` (Node.js)
   - `pytest`, `python -m pytest` (Python)
   - `go test ./...` (Go)
   - `cargo test` (Rust)
   - `make test` (Makefile)
   - Check the repo's CLAUDE.md, README, or CI config for the correct test command
3. Linting and type checking if configured in the repo
4. Any other checks specified in the plan

### Step 4: Handle Failures

If any verification check fails:

1. **Do not attempt to fix the failures.** Do not invoke `/debug`.
2. **Complete ALL remaining verification checks** even after a failure -- document every check's result, not just the first failure. This gives the debug stage a complete picture of what is broken.
3. Record all failure details in Verify.md (see Step 5), with enough context for the debug stage to investigate without re-running the checks.
4. After documenting all results, commit, push, and signal `debug` as the next stage (see Stage Transition Signal).

**Pre-existing failures:** If a failing check was already failing on `main` before this branch existed, it is still a failure. Pre-existing status is NEVER grounds to mark verify as PASS. Two responses are valid:

- **(a) Route to `debug` to fix it now.** This is the default. The goal is to leave the codebase in the best working order regardless of bug origin.
- **(b) File a follow-up issue and mark the row `DEFERRED-ISSUE #<n>`.** Only valid if the proper fix meets the Create-Issue criteria (tradeoffs the user should decide, architectural refactoring, high blast radius, team discussion, breaking upgrades, or benchmark-needed performance work) AND is truly out of scope for this PR. Option (b) requires explicit rationale in Verify.md; it is not the default.

To file a follow-up, apply the **Deferral hierarchy** (Workflow Context) -- search the backlog and prefer appending before creating:

```bash
gh issue list --state open --limit 200 --json number,title,labels,body > /tmp/backlog-$0.json
```
If an open issue already covers this failure's area, append the context with `gh issue comment <existing-#> --body "..."` instead of opening a duplicate. Only if none fits, create one (bundling co-deferred failures that share a subsystem):

```bash
gh issue create \
  --title "<concise title>" \
  --body "<problem description, quoted failure output, cross-reference: 'Identified during verification of PR #<pr-number> for issue #<issue-number>. See ./claude-work/<issue>/Verify.md'>" \
  --label "followup,from-pr-#<pr-number>"
```

Record the issue number and URL (and tier: appended to #n / new #n) in Verify.md's "Follow-up Issues Created" section. In the "Failures Requiring Debug" table, annotate deferred rows as `DEFERRED-ISSUE #<n>` instead of leaving them as plain failures.

If all remaining failures are deferred and there is nothing left for `debug` to investigate, the default transition to `debug` should be replaced by advancing to `review` -- but mark verify status as FAIL in the summary so the review stage sees the deferred context.

### Step 5: Write Verify.md

```
# Verification Report: Issue #<number>

## Summary
- **Status:** PASS / FAIL
- **Components verified:** <N>/<total>
- **Full suite:** PASS / FAIL
- **Test suites run:** <list>
- **Failures requiring debug:** <N>
- **Failures deferred to follow-up issues:** <N -- list numbers, or "none">

## Component Verification

### Component: <name>
| Check | Status | Details |
|-------|--------|---------|
| <check description> | PASS/FAIL | <output or evidence> |

### Component: <name>
...

## Full Verification Suite

| Check | Status | Details |
|-------|--------|---------|
| End-to-end: <description> | PASS/FAIL | <details> |
| Existing tests: <suite> | PASS/FAIL | <output summary> |
| Lint/typecheck | PASS/FAIL | <details> |

## Failures Requiring Debug
For each failure, provide enough context for the debug stage to investigate without re-running the checks:
- **Check:** <exact check description and command>
- **Error output:** <complete error output>
- **Affected component:** <which component or module>
- **Observations:** <any patterns noticed, e.g., "only fails when X", "worked in component verification but fails in integration">
- **Status:** TO-DEBUG | DEFERRED-ISSUE #<n> (with rationale for deferral)

## Follow-up Issues Created

<One subsection per issue filed in Step 4 option (b). If none, write the single line: "None -- all failures routed to debug.">

### Issue #<n>: <title>
- **URL:** <gh url>
- **Tier:** <new issue | appended to existing #n>
- **Source failure:** <which check, quoted error>
- **Why deferred:** <criterion: tradeoff / architecture / blast radius / team-discussion / breaking-upgrade / benchmark-needed / out-of-scope>
- **Mitigation applied in this PR:** <yes -- describe | no>

## Verification Conclusion
<Final assessment: is the implementation complete and correct?>
```

### Step 6: Commit, Push, and Comment

```bash
git add ./claude-work/$0/Verify.md
git commit -m "claude-work(verify): verification complete for issue #$0"
git push
```

Post results to the PR thread. The comment MUST include a `Deferred (follow-up issues):` line -- either a list of issue numbers filed in Step 4, or the literal word `none`.

```bash
gh pr comment --body "<verification summary

Deferred (follow-up issues): #<n1>, #<n2>  # or 'none'>"
```

The PR comment should clearly state whether all verification passed, and if any debug cycles were needed.

## Stage Transition Signal

When running under the `work-issue` orchestrator, you can request a transition to a different stage by writing the target stage name to `./claude-work/$0/.next-stage`.

**Rules:**
- Write exactly one stage name, nothing else
- Only write this file if you want a NON-DEFAULT transition
- If you do not write this file, the orchestrator advances to `review` (default)
- The orchestrator validates your request -- invalid transitions are ignored

**When to signal:**
- `debug` -- if any verification check failed. Document all failures in Verify.md first:
  ```bash
  echo "debug" > ./claude-work/$0/.next-stage
  ```
  The orchestrator will run a debug session, then return to verify for a fresh re-verification pass.
- `verify` -- if you want the orchestrator to re-run verification in a completely fresh session. Rarely needed since the default after debug->verify already gets a fresh session.
- Default (advance to review) is correct when all verification passes.

## Re-trigger Behavior

If re-triggered (e.g., after a debug session, review changes, or integration), you MUST read `Debug.md`, `Review.md`, and/or `Integration.md` before running checks. These documents describe what changed since the last verification and should inform which areas need the closest attention.

Append a new section:

```
---

## Re-verification (triggered during <stage> phase)

### Reason
<why re-verification was needed>

### Changes Since Last Verification
<summarize relevant changes from Review.md and/or Integration.md>

### Results
<same structure as above>
```
