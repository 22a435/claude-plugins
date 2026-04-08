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
- **Subagent cost optimization:** Implementation agents should keep this session's model (do NOT specify a model override). Information-gathering agents (Explore, web research, context7 lookups) should use `model: "sonnet"` to reduce cost.
- **Subagent write boundary:** Subagents must NOT create, edit, or write any files under `./claude-work/`. They may modify source code files elsewhere in the repo. Only this parent session writes to `./claude-work/$0/`. Include this constraint in every subagent prompt you compose.

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

1. **Launch parallel subagents** -- one general-purpose Agent per independent component. Each agent's prompt should include:
   - The specific component description from the plan
   - The files to modify/create
   - The implementation details
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

### Step 3: Simplification Pass

After all components are implemented and verified, run `/simplify` as a cleanup pass on the changed code. **Skip this step entirely if any component failed verification** -- there is no point simplifying code that will change during a debug cycle.

1. Get the list of files changed during execution:
   ```bash
   git diff --name-only HEAD
   ```

2. Invoke `/simplify` to review the changed code for opportunities to improve reuse, quality, and efficiency.

3. Record what `/simplify` changed (if anything) for inclusion in Execute.md.

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

## Simplification Pass
What `/simplify` found and changed (or "No changes recommended" or "Skipped -- component failures require debug"):
- `path/to/file.ts` -- <what was simplified>
- ...

## Implementation Notes
Any observations, deviations from the plan, or things the verify/review stages should be aware of.

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
