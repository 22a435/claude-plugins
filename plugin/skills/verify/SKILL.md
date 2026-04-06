---
name: verify
description: Full verification suite -- re-runs all component checks, integration tests, and repo test suites. Documents failures and signals debug. Invoke with /verify <issue-number>.
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
- **Subagent cost optimization:** Verification-running agents should use `model: "sonnet"` -- they are executing checks and reporting results, not making judgment calls. Keep the parent session's model for analyzing failures and deciding whether to escalate.
- **Subagent write boundary:** Subagents in this stage must NOT create, edit, or write any files under `./claude-work/`. Only this parent session writes the output document. Include this constraint in every subagent prompt you compose.

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

### Step 5: Write Verify.md

```
# Verification Report: Issue #<number>

## Summary
- **Status:** PASS / FAIL
- **Components verified:** <N>/<total>
- **Full suite:** PASS / FAIL
- **Test suites run:** <list>
- **Failures requiring debug:** <N>

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

## Verification Conclusion
<Final assessment: is the implementation complete and correct?>
```

### Step 6: Commit, Push, and Comment

```bash
git add ./claude-work/$0/Verify.md
git commit -m "claude-work(verify): verification complete for issue #$0"
git push
```

Post results to the PR thread:
```bash
gh pr comment --body "<verification summary>"
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
