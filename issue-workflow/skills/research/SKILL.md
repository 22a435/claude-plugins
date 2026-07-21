---
name: research
description: Deep research phase for issue resolution. Investigates codebase, web resources, and library documentation. Invoke with /issue-workflow:research <issue-number>.
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash, Agent, Edit, Write, WebSearch, WebFetch
---

# Research Phase

You are performing the **research** stage of an issue workflow.

## Workflow Context

This skill is one stage of a multi-stage issue-to-PR workflow orchestrated by the `work-issue` CLI.

- **Branch:** `claude/<issue-number>` (created by the orchestrator during setup)
- **Work directory:** `./claude-work/<issue-number>/` -- each stage produces one document here
- **Document ownership:** You may READ any prior document. Only WRITE to your own output document inside `./claude-work/$0/` (where `$0` is the numeric GitHub issue ID passed as your argument). Never create files, directories, or write anywhere else under `./claude-work/`. When re-triggered, APPEND new sections -- never delete or overwrite existing content. Mark in-place edits with `> [IN-PLACE EDIT during <stage> phase]: <reason>`.
- **Commits:** Format: `claude-work(<stage>): <description> [#<issue>]`. Commit and push after completing the stage.
- **PR updates:** Post a summary to the PR or issue thread (via `gh pr comment` or `gh issue comment`) after each stage.
- **Subagent write boundary:** Subagents in this stage must NOT create, edit, or write any files under `./claude-work/`. Only this parent session writes the output document. Include this constraint in every subagent prompt you compose.
- **No self-loop:** Do not use `/loop`, `ScheduleWakeup`, or recursive `claude` invocations to re-run this skill. For short waits, run the command synchronously with `Bash` (it blocks until completion); for long waits, use `Bash` with `run_in_background` and `Monitor`. If you cannot finish in one pass, commit your partial progress and write your own stage name to `.next-stage` -- the orchestrator re-enters the stage within its loop-safety limits. Never re-invoke yourself.
- **Deferral hierarchy (never silently drop, never over-file):** Pre-existing bugs are not grounds for dismissal -- leave the codebase in the best working order regardless of origin. When work surfaces that you will not finish in this PR, walk this hierarchy and stop at the first tier that fits: **(1) Fix it in this PR** -- the default, and hard; "complex", "tedious", "touches many files", or "would take a while" are NOT reasons to defer, only a genuine Create-Issue criterion is (a tradeoff the user must decide / architectural refactor / high blast radius / team discussion / breaking upgrade / benchmark-needed). **(2) Append to a follow-up already filed in this run** -- if a follow-up you filed (or will file) this run naturally covers it, add it there rather than opening a second issue. **(3) Append to an existing open backlog issue** -- before filing anything new, search the backlog (`gh issue list --state open --limit 200 --json number,title,labels,body`); if an open issue already covers the area, comment the new context onto it instead of creating a duplicate. **(4) File one new, bundled issue** -- only if no tier above fits; bundle every co-deferred finding from this run that shares a subsystem or design decision into the SAME issue (one well-scoped issue, never one-per-finding). Filing a follow-up is a commitment that the proper fix exceeds this PR's scope -- not a way to avoid work; never leave a deferred finding as a document-only note, and record which tier each deferral took and why.
- **Read issues in full:** When you read a GitHub issue, read the *entire* thread -- the body **and every comment/reply** -- plus any linked issues, PRs, commits, or docs that look relevant. Critical scope and context often live in replies, not the original body; missing them causes under-scoped work. Treat the whole thread as the source of truth for what the issue actually asks.
- **Session result:** After your final commit/push and PR/issue comment, as the very LAST step of the session, write `./claude-work/$0/.session-result.json` (overwrite if present; do NOT commit it): `{"stage": "<this stage>", "outcome": "complete|partial|blocked", "next_stage_signal": "<stage written to .next-stage, or null>", "summary": "<1-3 factual sentences on what happened>", "artifacts": ["<key files produced or changed>"], "follow_ups": ["<issue refs filed, if any>"], "timestamp": "<UTC ISO-8601>"}`. External tooling reads this file to understand session state -- write it even when blocked or partial.
- **Abandoning:** If you conclude the ISSUE itself should not ship (already fixed on main, obsolete, invalid, superseded -- not merely difficult), do not tear anything down yourself: record your reasoning in your stage document, write `abandon` to `./claude-work/$0/.next-stage`, and end the session. A dedicated user-gated abandon stage will present the case and act only on explicit user approval.

## Context
- **Issue number:** $0 (numeric GitHub issue ID -- not a title, keyword, or topic name)
- **Work directory:** `./claude-work/$0/`
- **Input document:** `./claude-work/$0/Issue.md`
- **Output document:** `./claude-work/$0/Research.md`

## Instructions

### Step 1: Read the Issue

Read `./claude-work/$0/Issue.md` carefully -- **including the `## Discussion Thread` section**, not just the issue body. The orchestrator captures the full comment thread there because scope, constraints, and acceptance criteria are frequently added in replies rather than the original body; treat the whole thread as the source of truth. Then follow any linked issues, PRs, commits, or docs referenced in the body or comments that look relevant (`gh issue view`, `gh pr view`, web fetch) and fold that context in. Understand the full scope of what is being requested, including any constraints, preferences, or acceptance criteria mentioned anywhere in the thread.

### Step 2: Conduct Parallel Research

Launch multiple research efforts simultaneously using parallel subagents. Aim for thoroughness -- it is far better to over-research than to under-research at this stage.

**Codebase Investigation** -- launch Explore agents (2-3 in parallel) to:
- Find all files, modules, and functions relevant to the issue
- Map the architecture of the affected areas
- Identify integration points, dependencies, and coupling
- Understand existing patterns, conventions, and code style
- Find related tests and their coverage
- Check for existing similar implementations that could be reused or extended
- Look at recent git history in affected areas for context

**External Research** -- launch general-purpose agents with web access to:
- Search for best practices relevant to the task
- Find known issues, gotchas, or pitfalls for the approach
- Look up relevant discussions, blog posts, or documentation
- Check for security considerations

**Library Documentation** -- launch agents using context7 MCP to:
- Look up exact API documentation for any libraries, frameworks, or tools involved
- Check version-specific behavior, breaking changes, and migration guides
- Verify function signatures, configuration options, and default values
- Find usage examples from official documentation

### Step 3: Analyze and Document

Synthesize all research findings. Critically:

- **Leave open questions OPEN.** Do not make design decisions. For each open question, document the available options, their tradeoffs, and any contingencies that depend on the answer. The interview phase will resolve these with user input.
- **Be explicit about uncertainty.** If something is unclear, flag it rather than assuming.
- **Document dependencies and risks.** What could go wrong? What are the prerequisites?

### Step 4: Write Research.md

Write `./claude-work/$0/Research.md` with the following structure:

```
# Research Report: Issue #<number>

## Summary
Brief overview of what was investigated and the key findings.

## Codebase Analysis

### Relevant Files and Modules
List of files that will need to be read, modified, or created, with brief descriptions of their role.

### Current Architecture
How the affected area currently works. Include data flow, key abstractions, and entry points.

### Integration Points
Where the new work connects to existing code. APIs, shared state, event flows, etc.

### Existing Patterns and Conventions
Code style, naming conventions, error handling patterns, testing patterns used in the affected area.

### Test Coverage
What tests exist for the affected area. What testing frameworks and patterns are used.

## External Research

### Best Practices
What the community/industry recommends for this type of work.

### Known Issues and Gotchas
Pitfalls, footguns, or non-obvious behavior to watch for.

### Relevant Resources
Links and references that may be useful during implementation.

## Library and API Documentation
API details, configuration options, and version-specific notes for any libraries involved.

## Dependencies and Risks

### Prerequisites
Things that must be true or in place before implementation can begin.

### Risks
What could go wrong. Include likelihood and severity if possible.

### Backward Compatibility
Will this break anything for existing users, callers, or dependents?

## Open Questions
For each unresolved question:
- **Question:** What needs to be decided?
- **Options:** What are the choices?
- **Tradeoffs:** Pros and cons of each option
- **Recommendation:** Preliminary lean with reasoning (if any)
- **Impact:** What depends on this decision?
```

### Step 5: Commit and Push

```bash
git add ./claude-work/$0/Research.md
git commit -m "claude-work(research): complete research for issue #$0"
git push
```

### Step 6: Comment on Issue Thread

Post a summary to the GitHub issue:

```bash
gh issue comment $0 --body "<summary>"
```

The summary should include:
- Key findings (5-10 bullet points)
- Number of open questions identified
- Notable risks or dependencies discovered
- Reference to the full report in `./claude-work/$0/Research.md`

## Stage Transition Signal

When running under the `work-issue` orchestrator, you can request a transition to a different stage by writing the target stage name to `./claude-work/$0/.next-stage`.

**Rules:**
- Write exactly one stage name, nothing else
- Only write this file if you want a NON-DEFAULT transition
- If you do not write this file, the orchestrator advances to `interview` (default)
- The orchestrator validates your request -- invalid transitions are ignored

**When to signal:**
- If your research reveals that the issue needs immediate user clarification before more research would be useful, signal `interview`:
  ```bash
  echo "interview" > ./claude-work/$0/.next-stage
  ```
- If your findings invalidate initial assumptions and you need a completely fresh research pass, signal `research`:
  ```bash
  echo "research" > ./claude-work/$0/.next-stage
  ```
- In most cases, do NOT write a signal file. The default (advance to interview) is correct.

## Re-trigger Behavior

If this skill is invoked again after initial completion (e.g., a later stage identified something that needs more research), **append** to the existing Research.md. Add a clearly marked new section:

```
---

## Additional Research (triggered during <stage> phase)

### Reason for Re-investigation
<why this research was needed>

### Findings
<new findings>
```

Do not modify the original research sections unless correcting a factual error (mark in-place edits clearly).
