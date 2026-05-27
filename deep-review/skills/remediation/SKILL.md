---
name: remediation
description: Apply approved remediations, create GitHub issues for complex items, run /code-review cleanup. The ONLY stage that edits repo code. Invoke with /deep-review:remediation <session-number>.
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash, Agent, Write, Edit, WebSearch, WebFetch, Skill
---

# Remediation Phase

You are performing the **remediation** stage of a deep codebase review. Your job is to apply all approved remediations from the remediation plan, create GitHub issues for complex items, and run a final `/code-review` cleanup pass.

## Workflow Context

This skill is one stage of a multi-stage deep review workflow orchestrated by the `deep-review` CLI.

- **Branch:** `claude/review/<session-number>` (created by the orchestrator during setup)
- **Work directory:** `./claude-reviews/<session-number>/` -- each stage produces one document here
- **Document ownership:** You may READ any prior document. Only WRITE to `./claude-reviews/$0/Remediation.md` for your output document. When re-triggered, APPEND new sections.
- **Commits:** Format: `claude-review(<stage>): <description> [session #<N>]`. Commit and push after completing all changes.
- **PR updates:** Post a summary to the PR thread (via `gh pr comment`) after completing the stage.
- **Code changes:** This is the ONLY stage that edits source code and documentation in the repository (along with update-tooling for setup scripts). Apply changes carefully and verify each one.
- **No self-loop:** Do not use `/loop`, `ScheduleWakeup`, or recursive `claude` invocations to re-run this skill. For short waits, run the command synchronously with `Bash` (it blocks until completion); for long waits, use `Bash` with `run_in_background` and `Monitor`. If you cannot finish in one pass, commit your partial progress and write your own stage name to `.next-stage` -- the orchestrator re-enters the stage within its loop-safety limits. Never re-invoke yourself.

## Completeness Requirement

Apply each remediation in full. A remediation is not done until the fix is complete end-to-end.

Forbidden in applied code:
- `TODO`, `FIXME`, or `XXX` comments marking unfinished work in code you wrote
- Stubs, no-op functions, or placeholder return values standing in for real logic
- `NotImplementedError`, `unimplemented!()`, `panic!("todo")`, `throw new Error("not implemented")`, `raise NotImplementedError`, or equivalent in any language
- Comments like "fix this properly later", "MVP for now", "follow-up needed"
- Mocked or hardcoded responses in production code paths (test fixtures are fine)

If a remediation appears harder than the plan expected, complete it anyway -- do not silently downgrade it to a partial fix. If it is genuinely blocked (the change as planned is impossible, or it surfaces a deeper issue that must be escalated), stop, document the blocker in Remediation.md, and flag it for the user during the next stage. Do not invent a "create issue" item mid-remediation to escape the work; that decision was made during remediation-plan and is locked.

Failures during a remediation's verification do not become follow-up issues either -- they are documented and handled per the standard failure path in Step 2.

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
   - Apply the fix end-to-end. No stubs, TODOs, NotImplementedError, placeholder returns, or "follow-up needed" notes. If a planned change is genuinely impossible, report it back instead of stubbing past it.
   ```

3. **After each batch completes:**
   - Review agent results
   - Record successes and failures
   - Continue to next batch if current batch succeeded
   - If a remediation failed: document it but continue with unblocked remediations

### Step 3: Run /code-review Cleanup

After all remediations are applied, run `/code-review --fix` as a final cleanup pass on the changes made.

`/code-review` is a sub-skill that returns control to you when it finishes. **Returning from `/code-review` is NOT the end of this stage.** Steps 4-7 below are mandatory and must still run after `/code-review` completes. Specifically: GitHub issues from the remediation plan are not yet created, Remediation.md has not been written, nothing has been committed, and no PR comment has been posted. Do not declare the stage done or hand control back to the orchestrator until Step 7 finishes.

1. Capture the pre-review file list:
   ```bash
   git diff --name-only HEAD > /tmp/pre-codereview-files-$0.txt
   ```

2. Invoke the skill: `/code-review --fix`. The `--fix` flag applies the findings to the working tree -- without it, the skill only reports.

3. When control returns, capture what changed:
   ```bash
   git diff --name-only HEAD
   ```
   Compare against the pre-review list to identify files `/code-review` modified. Note any summary the skill emitted.

4. Record these results for inclusion in Step 5's Remediation.md write -- specifically the "Code Review Pass" section. If `/code-review` made no changes, record "No changes recommended."

5. **Continue immediately to Step 4 (Create GitHub Issues).** Do not stop, do not summarize back to the user, do not commit yet -- the stage is not complete until Step 7 finishes.

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
- **Code review changes:** <N> files modified by /code-review
- **Failures:** <N>

## Remediations Applied

### Remediation 1: <title>
- **Status:** Complete / Failed / Partial
- **Files changed:**
  - `path/to/file.ts` -- <what was changed>
- **Verification:** PASS / FAIL -- <details>
- **Notes:** <any deviations from plan or observations>

### Remediation 2: ...

## Code Review Pass
What `/code-review` found and changed (or "No changes recommended"):
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
- /code-review changes: <N> files
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
