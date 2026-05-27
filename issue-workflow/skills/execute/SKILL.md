---
name: execute
description: Implement the approved plan using parallel subagents. Documents failures and signals debug when components fail verification. Invoke with /issue-workflow:execute <issue-number>.
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash, Agent, Write, Edit, WebSearch, WebFetch, Skill
---

# Execution Phase

You are performing the **execution** stage of an issue workflow. Your job is to implement every component of the approved plan and verify each one. If any verification fails, document the failure and signal `debug` as the next stage -- do not attempt fixes.

## Workflow Context

This skill is one stage of an 8-stage issue-to-PR workflow orchestrated by the `work-issue` CLI.

- **Branch:** `claude/<issue-number>` (created by the orchestrator during setup)
- **Work directory:** `./claude-work/<issue-number>/` -- each stage produces one document here
- **Document ownership:** You may READ any prior document. Only WRITE to your own output document inside `./claude-work/$0/` (where `$0` is the numeric GitHub issue ID passed as your argument). Never create files, directories, or write anywhere else under `./claude-work/`. When re-triggered, APPEND new sections -- never delete or overwrite existing content. Mark in-place edits with `> [IN-PLACE EDIT during <stage> phase]: <reason>`.
- **Commits:** Format: `claude-work(<stage>): <description> [#<issue>]`. Commit and push after completing the stage.
- **PR updates:** Post a summary to the PR thread (via `gh pr comment`) after each stage.
- **Subagent write boundary:** Subagents must NOT create, edit, or write any files under `./claude-work/`. They may modify source code files elsewhere in the repo. Only this parent session writes to `./claude-work/$0/`. Include this constraint in every subagent prompt you compose.
- **No self-loop:** Do not use `/loop`, `ScheduleWakeup`, or recursive `claude` invocations to re-run this skill. For short waits, run the command synchronously with `Bash` (it blocks until completion); for long waits, use `Bash` with `run_in_background` and `Monitor`. If you cannot finish in one pass, commit your partial progress and write your own stage name to `.next-stage` -- the orchestrator re-enters the stage within its loop-safety limits. Never re-invoke yourself.
- **Follow-up issues, not dismissal:** Pre-existing bugs are not valid grounds for dismissal -- the goal is to leave the codebase in the best working order regardless of bug origin. When a finding is genuinely too complex or out of scope to fix in this PR, file a GitHub issue via `gh issue create` -- never a document-only note. Every stage that surfaces a deferrable finding is responsible for filing it.

## Completeness Requirement

Implement every component of the plan end-to-end. The implementation is not considered done until every code path the plan specifies is fully built.

Forbidden in the final implementation:
- `TODO`, `FIXME`, or `XXX` comments that mark unfinished work in code you wrote
- Stubs, no-op functions, or placeholder return values (`return None`, `return {}`, hardcoded fake data) standing in for real logic
- `NotImplementedError`, `unimplemented!()`, `panic!("todo")`, `throw new Error("not implemented")`, `raise NotImplementedError`, or equivalent in any language
- Comments like "implement this in a follow-up", "wire this up later", "MVP for now"
- Mocked or hardcoded responses in production code paths (test fixtures are fine)

Follow-up issues from this stage are reserved for pre-existing bugs in adjacent code or genuinely out-of-scope cleanup discovered while implementing -- never for parts of the requested feature. If a component is hard, slow, or messy, that is not grounds to defer it; build it. If a component appears impossible as specified, do not silently downgrade it: stop, document the blocker in Execute.md, and ask the user how to proceed.

If verification of a component fails, that routes to `debug` (not a follow-up issue). Debug fixes it and execute re-runs to completion.

## Context
- **Issue number:** $0 (numeric GitHub issue ID -- not a title, keyword, or topic name)
- **Work directory:** `./claude-work/$0/`
- **Primary input:** `./claude-work/$0/Plan.md`
- **Query access:** `Issue.md`, `Research.md`, `Interview.md` (read as needed, do not modify)
- **Output document:** `./claude-work/$0/Execute.md`
- **Debug document:** `./claude-work/$0/Debug.md` (written by /debug if invoked)

## Instructions

### Step 1: Read the Plan

Read `./claude-work/$0/Plan.md` in full. Understand every component, its dependencies, verification steps, and the execution order.

If anything in the plan is unclear, read the earlier documents (Issue.md, Research.md, Interview.md) for context. Do not modify those documents.

### Step 2: Execute Components

Follow the execution order from the plan. For each batch of parallelizable components:

1. **Launch parallel subagents** -- one general-purpose Agent per independent component. Each agent's prompt must include:
   - The specific component description from the plan
   - The files to modify/create
   - The implementation details
   - The completeness requirement: "Build the component end-to-end. No stubs, TODOs, NotImplementedError, placeholder returns, or 'implement later' notes. Every code path described in the plan must be fully implemented. If you hit a true blocker, report it back instead of stubbing past it."
   - Instructions to make the code changes and report what was done

2. **Wait for all agents in the batch to complete.**

3. **Run component verification** -- for each component, execute the verification checks specified in the plan. Run these sequentially to catch any cross-component issues.

4. **Handle failures:**
   - If a component's verification check fails, **do not attempt to fix it**
   - Document the failure in Execute.md (see Step 4) with the exact error output
   - Continue implementing remaining components that do not depend on the failed one
   - Skip any components that have a dependency on the failed component (note them as blocked)
   - After completing all possible components, commit, push, and signal `debug` as the next stage (see Stage Transition Signal)

5. **Proceed to the next batch** once all components in the current batch pass verification (or are documented as failures).

### Step 3: Code Review Pass

After all components are implemented and verified, run `/code-review --fix` as a cleanup pass on the changed code. **Skip this step entirely if any component failed verification** -- there is no point reviewing code that will change during a debug cycle.

`/code-review` is a sub-skill that returns control to you when it finishes. **Returning from `/code-review` is NOT the end of this stage.** Steps 4 and 5 below are mandatory and must still run after `/code-review` completes. Do not declare the stage done, do not skip writing Execute.md, do not skip the commit/push, and do not post the PR comment until Step 5.

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

4. Record these results for inclusion in Step 4's Execute.md write -- specifically the "Code Review Pass" section. If `/code-review` made no changes, record "No changes recommended."

5. **Continue immediately to Step 4.** Do not stop, do not summarize back to the user, do not commit yet -- the stage is not complete until Step 5 finishes.

### Step 4: Write Execute.md

After all possible components are implemented, write the complete execution log to `./claude-work/$0/Execute.md`:

```
# Execution Log: Issue #<number>

## Summary
Brief overview: what was implemented, how long it took, any issues encountered.

## Components Completed

### Component 1: <name>
- **Status:** Complete
- **Files changed:** list of files
- **Verification:** All checks passed
- **Notes:** Any implementation decisions or deviations from plan

### Component 2: <name>
- **Status:** Failed -- requires debug
- **Issue encountered:** <brief description>
- **Verification check:** <what was run>
- **Error output:** <exact error>
...

## Failures Requiring Debug

### Failure 1: <component name>
- **Verification check:** <what was run>
- **Error output:** <exact error>
- **Blocked components:** <components that depend on this one and were skipped>
- **Context:** <any relevant observations about why it might be failing>

## Code Review Pass
What `/code-review` found and changed (or "No changes recommended" or "Skipped -- component failures require debug"):
- `path/to/file.ts` -- <what was simplified>
- ...

## Implementation Notes
Any observations, deviations from the plan, or things the verify/review stages should be aware of. If any component had to be reduced in scope, explain WHY and confirm the user approved that reduction (cross-reference Interview.md or the user message that authorized it).

## Files Changed
Complete list of all files added, modified, or deleted.
```

### Step 5: Commit and Push

```bash
git add -A
git commit -m "claude-work(execute): implementation complete for issue #$0"
git push
```

Post a summary to the PR thread:
```bash
gh pr comment --body "<execution summary>"
```

## Stage Transition Signal

When running under the `work-issue` orchestrator, you can request a transition to a different stage by writing the target stage name to `./claude-work/$0/.next-stage`.

**Rules:**
- Write exactly one stage name, nothing else
- Only write this file if you want a NON-DEFAULT transition
- If you do not write this file, the orchestrator advances to `verify` (default)
- The orchestrator validates your request -- invalid transitions are ignored

**When to signal:**
- `debug` -- if any component's verification failed and you could not complete it. Document all failures in Execute.md first, then signal debug:
  ```bash
  echo "debug" > ./claude-work/$0/.next-stage
  ```
  The orchestrator will run a debug session, then return to execute to continue from where you left off.
- Default (advance to verify) is correct when all components are implemented and their individual verification checks pass.

## Important Notes

- **Do not modify** Issue.md, Research.md, Interview.md, or Plan.md.
- **Do not attempt to fix verification failures.** Document them and signal debug.
- **Commit at reasonable intervals** -- if a large independent component is complete and verified, commit it before moving on. Do not wait until the very end to commit everything.
- **When parallelizing**, ensure agents work on different files. If two components touch the same file, implement them sequentially.
- If the plan has an error or something is impossible to implement as specified, note it in Execute.md and ask the user how to proceed rather than silently deviating.

## Re-trigger Behavior

If re-triggered (e.g., after a debug session fixed a failing component), read the existing Execute.md and Debug.md first. Identify which components were already completed successfully and skip them. Understand what the debug session fixed. Continue implementing from where the previous execution left off. Append a new section:

```
---

## Continued Execution (after debug)

### Debug Resolution
<summary of what Debug.md reported as the fix>

### Components Completed in This Pass
...
```
