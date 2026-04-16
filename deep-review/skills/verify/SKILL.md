---
name: verify
description: Verify remediations were applied correctly. Cross-references Remediation-Plan.md, Remediation.md, and actual code. Invoke with /deep-review:verify <session-number>.
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash, Agent, Write, Edit
---

# Verification Phase

You are performing the **verify** stage of a deep codebase review. Your job is to confirm that all remediations documented in Remediation.md were actually applied correctly in the code, and that nothing from the Remediation-Plan.md was missed.

## Workflow Context

This skill is one stage of a multi-stage deep review workflow orchestrated by the `deep-review` CLI.

- **Branch:** `claude/review/<session-number>` (created by the orchestrator during setup)
- **Work directory:** `./claude-reviews/<session-number>/` -- each stage produces one document here
- **Document ownership:** You may READ any prior document. Only WRITE to `./claude-reviews/$0/Verify.md` for your output document. When re-triggered, APPEND new sections -- never delete or overwrite existing content. Mark in-place edits with `> [IN-PLACE EDIT during <stage> phase]: <reason>`.
- **Commits:** Format: `claude-review(<stage>): <description> [session #<N>]`. Commit and push after completing the stage.
- **PR updates:** Post a summary to the PR thread (via `gh pr comment`) after each stage.
- **Subagent cost optimization:** Downgrade information-gathering agents (Explore, web research, context7) to `model: "sonnet"`. Keep the parent session's model for implementation and reasoning agents.
- **No code edits:** This stage does NOT edit any source code. It only reads code to verify remediations and produces Verify.md.

## Context
- **Session number:** $0 (the review session number passed as your argument)
- **Work directory:** `./claude-reviews/$0/`
- **Input documents:** `./claude-reviews/$0/Remediation-Plan.md`, `./claude-reviews/$0/Remediation.md` (primary), plus Review.md and sub-reviews for context
- **Output document:** `./claude-reviews/$0/Verify.md`

## Instructions

### Step 1: Determine Verification Mode

Check whether `./claude-reviews/$0/Integration.md` exists:

- **If Integration.md does NOT exist** (or this is the first verify run): this is a **standard verification** -- check all remediations against the plan.
- **If Integration.md exists** (and Verify.md already exists from a prior run): this is a **post-integration verification** -- focus on whether the rebase undid any remediations.

### Step 2: Read Input Documents

Read in full:
1. `Remediation-Plan.md` -- the approved plan listing all remediations to apply
2. `Remediation.md` -- the remediation report documenting what was actually done

If post-integration mode, also read:
3. `Integration.md` -- details of the rebase, conflicts resolved, files affected

### Step 3: Standard Verification (no Integration.md)

For each remediation marked as "Complete" in Remediation.md:

1. **Read the affected files** listed in the remediation entry
2. **Verify the fix is present** -- confirm the described change actually exists in the code
3. **Cross-reference against the plan** -- confirm the fix matches what the plan specified
4. **Record the result:** PASS (fix verified in code) or FAIL (fix missing, incomplete, or different from plan)

Then check for **missed items**:

1. Compare the full list of "fix now" items in Remediation-Plan.md against what Remediation.md reports
2. Any item in the plan not accounted for in Remediation.md (neither completed nor documented as failed) is a **missed** item

Use parallel subagents to verify multiple remediations concurrently. Each agent:
- Reads the specific files for one remediation
- Checks the fix is present and correct
- Reports PASS/FAIL with evidence

### Step 4: Post-Integration Verification (Integration.md exists)

This mode runs after a rebase. Focus specifically on remediations that may have been affected:

1. **Identify affected files** -- from Integration.md's conflict list and `git diff` output
2. **Filter remediations** -- only check remediations that touched files affected by the rebase
3. **For each affected remediation:**
   - Read the current state of the file
   - Compare against what Remediation.md says was changed
   - Record: INTACT (fix survived rebase), UNDONE (fix was lost/corrupted), or PARTIAL (fix partially present)
4. **Remediations in unaffected files** can be marked SKIPPED (assumed intact)

### Step 5: Write Verify.md

Write `./claude-reviews/$0/Verify.md`:

```
# Verification Report: Session #<N>

## Summary
- **Mode:** Standard / Post-Integration
- **Remediations verified:** <N>/<M>
- **Passed:** <N>
- **Failed:** <N>
- **Missed (not attempted):** <N>
- **Undone by integration:** <N> (post-integration mode only)
- **Verdict:** ALL PASS / GAPS FOUND

## Verification Results

### Remediation: <title>
- **Status:** PASS / FAIL / UNDONE / SKIPPED
- **Files checked:**
  - `path/to/file.ts` -- <what was verified, or what's missing>
- **Evidence:** <brief description of what was found in the code>
- **Plan reference:** <which item in Remediation-Plan.md this corresponds to>

### Remediation: <title>
...

## Missed Items
Items in Remediation-Plan.md not accounted for in Remediation.md:
- <plan item title> -- <files that should have been changed>
- ...
(Or: "None -- all plan items were addressed")

## Items Undone by Integration
(Post-integration mode only)
- <remediation title> -- <what was lost and in which file>
- ...

## Recommendation
<"All remediations verified. Proceed to integration." or "Gaps found. Remediation should address the items listed above.">
```

### Step 6: Commit and Push

```bash
git add ./claude-reviews/$0/Verify.md
git commit -m "claude-review(verify): verification complete [session #$0]"
git push
```

### Step 7: Comment on PR

```bash
gh pr comment "claude/review/$0" --body "**Verification Complete**

- Remediations verified: <N>/<M>
- Passed: <N>, Failed: <N>, Missed: <N>
- Verdict: <ALL PASS / GAPS FOUND>

<brief summary of any issues found>

See \`claude-reviews/$0/Verify.md\` for full details."
```

### Step 8: Signal Transition

- **If all remediations pass:** do not write a signal file (default transition to `integrate`)
- **If gaps found** (failures, missed items, or remediations undone by integration): signal `remediation`
  ```bash
  echo "remediation" > ./claude-reviews/$0/.next-stage
  ```

## Stage Transition Signal

When running under the `deep-review` orchestrator, you can request a transition to a different stage by writing the target stage name to `./claude-reviews/$0/.next-stage`.

**Rules:**
- Write exactly one stage name, nothing else
- Only write this file if you want a NON-DEFAULT transition
- If you do not write this file, the orchestrator advances to `integrate` (default)

**When to signal:**
- `remediation` -- gaps were found (failed, missed, or undone remediations). Remediation will read Verify.md to see what needs addressing:
  ```bash
  echo "remediation" > ./claude-reviews/$0/.next-stage
  ```
- Default (integrate) -- all remediations verified, proceed to integration.

## Re-trigger Behavior

If re-triggered and `Verify.md` already exists:

1. Read existing Verify.md to understand prior verification results
2. Determine the trigger context (post-remediation re-run or post-integration)
3. Re-verify items that previously failed, were missed, or were newly applied
4. Append a new section:

```
---

## Re-verification (<date>)

### Trigger
<post-remediation fix / post-integration rebase>

### Results
- Previously failed, now: <PASS/FAIL>
- Previously missed, now: <PASS/FAIL>
- Undone by integration, now: <INTACT/STILL UNDONE>

### Updated Verdict
<ALL PASS / GAPS REMAIN>
```
