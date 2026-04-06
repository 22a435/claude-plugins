---
name: debug
description: Root cause analysis and fix for problems escalated from execute, verify, or review. Runs as a dedicated orchestrator stage with a fresh context window. Invoke with /debug <issue-number>.
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash, Agent, Write, Edit, WebSearch, WebFetch
---

# Debug Phase

You are performing the **debug** stage of an issue workflow. A problem was encountered during execution, verification, or review that the triggering stage could not or should not fix. Your job is to thoroughly investigate, identify the root cause, and fix it. After fixing, the orchestrator will return control to the stage that triggered you.

## Workflow Context

This skill is one stage of an 8-stage issue-to-PR workflow orchestrated by the `work-issue` CLI.

- **Branch:** `claude/<issue-number>` (created by the orchestrator during setup)
- **Work directory:** `./claude-work/<issue-number>/` -- each stage produces one document here
- **Document ownership:** You may READ any prior document. Only WRITE to your own output document inside `./claude-work/$0/` (where `$0` is the numeric GitHub issue ID passed as your argument). Never create files, directories, or write anywhere else under `./claude-work/`. When re-triggered, APPEND new sections -- never delete or overwrite existing content. Mark in-place edits with `> [IN-PLACE EDIT during <stage> phase]: <reason>`.
- **Commits:** Format: `claude-work(<stage>): <description> [#<issue>]`. Commit and push after completing the stage.
- **PR updates:** Post a summary to the PR thread (via `gh pr comment`) after each stage.
- **Subagent cost optimization:** Downgrade codebase investigation agents (Explore) and external research agents to `model: "sonnet"`. Keep the parent session's model for hypothesis-testing agents that require full reasoning capability.
- **Subagent write boundary:** Subagents must NOT create, edit, or write any files under `./claude-work/`. They may modify source code files elsewhere in the repo. Only this parent session writes to `./claude-work/$0/`. Include this constraint in every subagent prompt you compose.

## Context
- **Issue number:** $0 (numeric GitHub issue ID -- not a title, keyword, or topic name)
- **Work directory:** `./claude-work/$0/`
- **Origin stage:** Read `./claude-work/$0/.debug-origin` to identify which stage triggered this debug session. Focus your investigation on that stage's output document.
- **Input documents:**
  - `./claude-work/$0/Plan.md` (what was supposed to be built)
  - `./claude-work/$0/Execute.md` (what was built, what failed)
  - `./claude-work/$0/Verify.md` (if debug was triggered from verification -- contains detailed failure reports)
  - `./claude-work/$0/Review.md` (if debug was triggered from review -- contains critical/important findings)
- **Output document:** `./claude-work/$0/Debug.md` (append if exists)

## Instructions

### Step 1: Understand the Problem

1. Read `./claude-work/$0/.debug-origin` to identify which stage triggered this debug session
2. Read `Plan.md` to understand the intended design
3. Read `Execute.md` to understand what was implemented and what failed
4. If `Verify.md` exists, read it -- especially the "Failures Requiring Debug" section for detailed error output
5. If `Review.md` exists and review triggered this debug, read it -- especially the "Critical" and "Important" findings sections
6. Focus on the specific failures documented by the triggering stage -- these contain the exact error messages, failed checks, and affected components

### Step 2: Investigate Root Cause

Launch parallel investigation agents to explore different hypotheses:

**Model optimization:** Launch codebase investigation agents (Explore) and external research agents with `model: "sonnet"` -- they are gathering information. Do NOT downgrade hypothesis-testing agents (Step 2, "Hypothesis Testing" section) -- those require the full reasoning capability of this session's model.

**Codebase Investigation:**
- Examine the actual code changes made during execution
- Compare against the plan to find discrepancies
- Look for interactions with code outside the changed files
- Check for race conditions, ordering issues, missing error handling

**External Research:**
- Search for the exact error messages online
- Look up library/framework documentation via context7 for relevant APIs
- Check for known issues with the specific versions being used
- Search for similar problems and their solutions

**Hypothesis Testing:**
For each plausible explanation:
1. Formulate a specific, testable hypothesis
2. Design a test that would confirm or refute it
3. Run the test
4. Record the result

**Do not attempt a fix until you have confirmed the root cause.** A fix based on a wrong diagnosis wastes time and may introduce new problems.

### Step 3: Design the Remediation

Once the root cause is confirmed:

**If the fix is a straightforward bug fix** (typo, wrong variable, missing null check, incorrect API usage):
- Proceed directly to implementation

**If the fix involves a design choice** (architecture change, different library, altered behavior, tradeoff between approaches):
- Present the situation to the user:
  - What the root cause is
  - What the options are for fixing it
  - Tradeoffs of each option
  - Your recommendation
- Wait for user input before proceeding

### Step 4: Apply the Fix

1. Implement the chosen remediation
2. Run the specific verification check that originally failed
3. Also run any related verification checks that might be affected
4. Confirm the fix resolves the issue completely

If the fix does not resolve the issue, return to Step 2 with the new information.

### Step 5: Write to Debug.md

If `Debug.md` already exists, **append** a new section. Do not overwrite previous debug sessions.

```
# Debug Log: Issue #<number>

## Debug Session <N> -- <timestamp>
**Triggered from:** <execute/verify/review>
**Problem:** <one-line description>

### Problem Description
What failed, the exact error, and what had been tried before escalation.

### Investigation
#### Hypotheses Explored
1. <Hypothesis A> -- <confirmed/refuted> -- <evidence>
2. <Hypothesis B> -- <confirmed/refuted> -- <evidence>

#### Root Cause
<Detailed explanation of what was actually wrong and why>

### Remediation
**Approach:** <what was done to fix it>
**Design choice escalated to user:** <yes/no -- if yes, what was decided>
**Files changed:** <list>

### Verification
- <check 1>: PASS
- <check 2>: PASS

### Impact on Remaining Work
<Any implications for execute/verify to be aware of>
```

### Step 6: Commit and Push

**Important:** Commit ALL files changed during this stage -- both the debug document and any code files modified as part of the fix. Do not commit only Debug.md.

```bash
git add -A
git commit -m "claude-work(debug): resolved issue for #$0"
git push
```

Post a summary to the PR thread:
```bash
gh pr comment --body "<debug summary: what was wrong, what was fixed, verification results>"
```

## Stage Transition Signal

When running under the `work-issue` orchestrator, you can request a transition to a different stage by writing the target stage name to `./claude-work/$0/.next-stage`.

**Rules:**
- Write exactly one stage name, nothing else
- Only write this file if you want a NON-DEFAULT transition
- If you do not write this file, the orchestrator returns to the stage that triggered this debug session (read from `.debug-origin`)
- The orchestrator validates your request -- invalid transitions are ignored

**When to signal:**
- In most cases, **do NOT write a signal file**. The default (return to origin stage) is correct. The origin stage will re-run with the benefit of your fix.
- If the problem revealed a fundamental issue that requires a different stage, you may signal it explicitly. For example, if a verify-triggered debug reveals that more implementation work is needed:
  ```bash
  echo "execute" > ./claude-work/$0/.next-stage
  ```

**Important:** Do not signal stages before the hard wall (research, interview, plan). If the problem is a plan flaw, document it in Debug.md and let the user intervene manually.

## Important Notes

- **You run as a dedicated orchestrator stage** with a fresh context window. You are NOT invoked inline within another skill's session.
- **Always confirm root cause before fixing.** Never guess-and-check.
- **Escalate design choices.** If the fix changes behavior or architecture, the user must decide.
- **Be thorough in documentation.** The debug log is valuable for understanding what went wrong and preventing similar issues.
- **Do not modify** Issue.md, Research.md, Interview.md, or Plan.md.
- If the problem is actually a flaw in the plan itself (not a bug), note this clearly and recommend the user re-run the plan stage.
- The orchestrator handles returning control to the correct stage automatically via `.debug-origin`.
