---
name: remediation
description: Apply approved remediations, create GitHub issues for complex items, run /simplify cleanup. The ONLY stage that edits repo code. Invoke with /deep-review:remediation <session-number>.
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash, Agent, Write, Edit, WebSearch, WebFetch, Skill
---

# Remediation Phase

You are performing the **remediation** stage of a deep codebase review. Your job is to apply all approved remediations from the remediation plan, create GitHub issues for complex items, and run a final `/simplify` cleanup pass.

## Workflow Context

This skill is one stage of a multi-stage deep review workflow orchestrated by the `deep-review` CLI.

- **Branch:** `claude/review/<session-number>` (created by the orchestrator during setup)
- **Work directory:** `./claude-reviews/<session-number>/` -- each stage produces one document here
- **Document ownership:** You may READ any prior document. Only WRITE to `./claude-reviews/$0/Remediation.md` for your output document. When re-triggered, APPEND new sections.
- **Commits:** Format: `claude-review(<stage>): <description> [session #<N>]`. Commit and push after completing all changes.
- **PR updates:** Post a summary to the PR thread (via `gh pr comment`) after completing the stage.
- **Code changes:** This is the ONLY stage that edits source code and documentation in the repository (along with update-tooling for setup scripts). Apply changes carefully and verify each one.

## Context
- **Session number:** $0 (the review session number passed as your argument)
- **Work directory:** `./claude-reviews/$0/`
- **Input document:** `./claude-reviews/$0/Remediation-Plan.md` (primary), plus Review.md and sub-reviews for context
- **Output document:** `./claude-reviews/$0/Remediation.md`

## Instructions

### Step 1: Read the Remediation Plan

Read `Remediation-Plan.md` in full. Understand:
- All "fix now" remediations, their files, and their execution order
- All "create issue" items and their descriptions
- Dependencies between remediations

Also read `Review.md` and relevant sub-reviews for full context on each finding.

### Step 2: Apply Remediations

Follow the execution order from the plan. For each batch of parallelizable remediations:

1. **Launch parallel subagents** -- one per independent remediation. Each agent gets:
   - The specific remediation description from the plan
   - Files to modify
   - The change to make
   - How to verify the fix
   - Full context from the relevant review finding

2. **Agent instructions template:**
   ```
   You are applying a remediation for deep review session #<N>.

   ## Remediation: <title>
   <full description from Remediation-Plan.md>

   ## Files to Change
   <list from plan>

   ## Context
   <relevant finding from Review.md or sub-review>

   ## Instructions
   1. Read each file to be changed
   2. Apply the described fix
   3. Run the verification check: <verification from plan>
   4. Report: what was changed, verification result, any issues encountered

   CONSTRAINTS:
   - Only modify the files listed above
   - Do NOT write to any file under ./claude-reviews/
   - If the verification fails, report the failure -- do not attempt alternative fixes
   ```

3. **After each batch completes:**
   - Review agent results
   - Record successes and failures
   - Continue to next batch if current batch succeeded
   - If a remediation failed: document it but continue with unblocked remediations

### Step 3: Run /simplify Cleanup

After all remediations are applied, run the `/simplify` skill as a final cleanup pass on the changes made:

1. Get the list of files changed during remediation:
   ```bash
   git diff --name-only HEAD
   ```

2. Invoke `/simplify` to review the changed code for opportunities to improve reuse, quality, and efficiency.

3. Record what `/simplify` changed (if anything).

### Step 4: Create GitHub Issues

For each "create issue" item in the remediation plan:

```bash
gh issue create \
  --title "<proposed title from plan>" \
  --body "<description with full context from review findings>" \
  --label "<labels from plan>"
```

The issue body should include:
- Description of the problem/opportunity
- Relevant findings from the review (quote specific sections)
- Suggested approach (if the review provided one)
- Reference to the review session: `Identified in deep review session #<N>`
- Link to the Review.md file on the review branch

Record the created issue number and URL.

### Step 5: Write Remediation.md

Write `./claude-reviews/$0/Remediation.md`:

```
# Remediation Report: Session #<N>

## Summary
- **Remediations applied:** <N>/<M> (succeeded/total planned)
- **Issues created:** <N>
- **Simplification changes:** <N> files modified by /simplify
- **Failures:** <N>

## Remediations Applied

### Remediation 1: <title>
- **Status:** Complete / Failed / Partial
- **Files changed:**
  - `path/to/file.ts` -- <what was changed>
- **Verification:** PASS / FAIL -- <details>
- **Notes:** <any deviations from plan or observations>

### Remediation 2: ...

## Simplification Pass
What `/simplify` found and changed (or "No changes recommended"):
- `path/to/file.ts` -- <what was simplified>
- ...

## Issues Created

### Issue #<number>: <title>
- **URL:** <github URL>
- **Labels:** <labels>
- **Description summary:** <one-line>
- **Source finding:** <reference to Review.md>

### Issue #<number>: ...

## Failures
For each failed remediation:
- **Remediation:** <title>
- **Error:** <what went wrong>
- **Impact:** <what remains unfixed>
- **Suggested follow-up:** <how to address this manually>

## Files Changed
Complete list of all files modified during remediation:
- `path/to/file1.ts`
- `path/to/file2.md`
- ...
```

### Step 6: Commit and Push

Commit ALL changes -- source code fixes, documentation updates, and Remediation.md:

```bash
git add -A
git commit -m "claude-review(remediation): apply fixes and create issues [session #$0]"
git push
```

### Step 7: Comment on PR

Post a comprehensive summary to the PR thread:

```bash
gh pr comment "claude/review/$0" --body "**Remediation Complete**

- Remediations applied: <N>/<M>
- Issues created: <N> (<list issue numbers>)
- /simplify changes: <N> files
- Failures: <N>

<brief description of key changes made>

See \`claude-reviews/$0/Remediation.md\` for full details."
```

## Stage Transition Signal

**Rules:**
- Write exactly one stage name, nothing else
- Only write this file if you want a NON-DEFAULT transition
- If you do not write this file, the orchestrator advances to `verify` (default)

**When to signal:**
- Default (verify) is almost always correct. Verification checks that all remediations were applied.
- Do NOT write a signal file unless something exceptional requires skipping verification.

## Re-trigger Behavior

If re-triggered and `Remediation.md` already exists, first check for `Verify.md`:

### Case A: Verify.md exists (targeted remediation)

Verify has identified specific gaps -- failed checks, missed items, or remediations undone by integration.

1. Read `Verify.md` to find exactly what needs addressing
2. Only fix the specific items listed in Verify.md -- do NOT re-run the full remediation plan
3. For each item:
   - Read the affected files
   - Apply the fix or re-apply the remediation
   - Verify the fix locally
4. Append a targeted section:

```
---

## Targeted Remediation (<date>)

### Trigger
<verify found gaps / verify found remediations undone by integration>

### Items from Verify.md

#### <item title>
- **Verify.md finding:** <what verify reported>
- **Action taken:** <what was fixed>
- **Files changed:** <list>
- **Local verification:** PASS/FAIL

### Updated Summary
- Items addressed: <N>/<M from Verify.md>
- Failures: <N>
```

### Case B: No Verify.md (standard re-trigger)

1. Read existing Remediation.md and the current Remediation-Plan.md
2. Identify remediations that were not yet applied or that failed previously
3. Apply only the remaining/failed remediations
4. Append a new section:

```
---

## Continued Remediation (triggered during <stage> phase)

### Reason
<why remediation was re-triggered>

### Additional Remediations Applied
...

### Additional Issues Created
...

### Updated Summary
- Total remediations applied: <N>/<M>
- Total issues created: <N>
- Remaining failures: <N>
```
