---
name: review
description: Execute the deep review -- launch parallel sub-reviewers, run tools, compile findings into comprehensive Review.md. Invoke with /deep-review:review <session-number>.
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash, Agent, Write, Edit, WebSearch, WebFetch, Skill
---

# Deep Review Phase

You are performing the **review** stage of a deep codebase review. This is the core stage of the workflow. Your job is to execute the review plan by running automated tools, launching parallel sub-reviewers, and compiling all findings into a comprehensive Review.md.

## Workflow Context

This skill is one stage of a multi-stage deep review workflow orchestrated by the `deep-review` CLI.

- **Branch:** `claude/review/<session-number>` (created by the orchestrator during setup)
- **Work directory:** `./claude-reviews/<session-number>/` -- each stage produces one document here
- **Sub-reviews directory:** `./claude-reviews/<session-number>/sub-reviews/` -- sub-reviewers write here
- **Document ownership:** You may READ any prior document. Only WRITE to `./claude-reviews/$0/Review.md` and files inside `./claude-reviews/$0/sub-reviews/`. Sub-reviewer agents may ONLY write to their own assigned file in `sub-reviews/`. The parent session writes `Review.md`.
- **Commits:** Format: `claude-review(<stage>): <description> [session #<N>]`. Commit and push after completing the stage.
- **PR updates:** Post the executive summary to the PR thread (via `gh pr comment`) after completing the stage.
- **Subagent role:** Sub-reviewer agents perform analysis and pattern-matching against the codebase. The parent session handles synthesis, cross-referencing, severity judgments, and writing Review.md. All subagents inherit the parent session's model unless explicitly overridden.
- **No code edits:** This stage does NOT edit any source code. It only produces review documents. The remediation stage handles code changes.
- **No self-loop:** Do not use `/loop`, `ScheduleWakeup`, or recursive `claude` invocations to re-run this skill. For short waits, run the command synchronously with `Bash` (it blocks until completion); for long waits, use `Bash` with `run_in_background` and `Monitor`. If you cannot finish in one pass, commit your partial progress and write your own stage name to `.next-stage` -- the orchestrator re-enters the stage within its loop-safety limits. Never re-invoke yourself.
- **Deferral hierarchy (never silently drop, never over-file):** Pre-existing bugs are not grounds for dismissal -- leave the codebase in the best working order regardless of origin. When work surfaces that you will not finish in this PR, walk this hierarchy and stop at the first tier that fits: **(1) Fix it in this PR** -- the default, and hard; "complex", "tedious", "touches many files", or "would take a while" are NOT reasons to defer, only a genuine Create-Issue criterion is (a tradeoff the user must decide / architectural refactor / high blast radius / team discussion / breaking upgrade / benchmark-needed). **(2) Append to a follow-up already filed in this run** -- if a follow-up you filed (or will file) this run naturally covers it, add it there rather than opening a second issue. **(3) Append to an existing open backlog issue** -- before filing anything new, search the backlog (`gh issue list --state open --limit 200 --json number,title,labels,body`); if an open issue already covers the area, comment the new context onto it instead of creating a duplicate. **(4) File one new, bundled issue** -- only if no tier above fits; bundle every co-deferred finding from this run that shares a subsystem or design decision into the SAME issue (one well-scoped issue, never one-per-finding). Filing a follow-up is a commitment that the proper fix exceeds this PR's scope -- not a way to avoid work; never leave a deferred finding as a document-only note, and record which tier each deferral took and why.
- **Read issues in full:** When you read a GitHub issue, read the *entire* thread -- the body **and every comment/reply** -- plus any linked issues, PRs, commits, or docs that look relevant. Critical scope and context often live in replies, not the original body; missing them causes under-scoped work. Treat the whole thread as the source of truth for what the issue actually asks.

## Context
- **Session number:** $0 (the review session number passed as your argument)
- **Work directory:** `./claude-reviews/$0/`
- **Input documents:** `./claude-reviews/$0/Plan.md` (primary), plus Context.md, Interview.md, UpdateTooling.md, ScAuditResults.md (if exists)
- **Output documents:** `./claude-reviews/$0/Review.md`, `./claude-reviews/$0/sub-reviews/*.md`

## Instructions

### Step 1: Read the Plan

Read `Plan.md` in full. This defines:
- Which sub-reviewers to launch
- What tools to run
- The scope and focus for each sub-reviewer
- Review priorities

Also read `Context.md` for project context and `UpdateTooling.md` for available tools and their commands.

**If `ScAuditResults.md` exists**, read it in full. This contains sc-auditor's smart contract security findings. When composing the Security sub-reviewer prompt:
- Include a summary of sc-auditor findings (proved, confirmed, candidate, design_tradeoff counts)
- Instruct the Security sub-reviewer to **validate and cross-reference** sc-auditor findings, not re-discover them
- Direct the Security sub-reviewer to focus on areas sc-auditor did NOT cover: non-Solidity code in the repo, deployment scripts, CI/CD security, off-chain components, infrastructure
- For each sc-auditor candidate finding, ask the Security sub-reviewer to assess whether it agrees or disagrees with the classification

### Step 2: Run Automated Tools

Execute all automated tools listed in the plan. Capture their output for sub-reviewers to consume:

```bash
mkdir -p ./claude-reviews/$0/sub-reviews/.tool-output
```

For each tool in the plan's "Automated Tool Runs" table:
```bash
<tool-command> > ./claude-reviews/$0/sub-reviews/.tool-output/<tool-name>.json 2>&1
# or .txt if the tool doesn't support JSON output
```

If a tool fails to run, record the error and continue with other tools. Sub-reviewers can proceed with manual analysis even without tool output.

### Step 3: Launch Parallel Sub-Reviewers

Launch sub-reviewer agents **in parallel** as defined in Plan.md.

**Sub-reviewer prompt template** (adapt for each reviewer):

```
You are the <NAME> sub-reviewer for deep review session #<N> of <repo>.
Your task is to examine the entire codebase and produce a thorough <NAME> review.

## Project Context
<Summary from Context.md -- tech stack, architecture, key patterns>

## Your Scope
<From Plan.md -- specific focus areas, directories, exclusions>

## Tools and Data Available
<Paths to relevant tool output files in sub-reviews/.tool-output/>
<Commands you can run for additional analysis>

## Review Priorities
<From Interview.md -- what matters most to the user>

## Instructions
<Sub-reviewer-specific analysis instructions from Plan.md>

Examine the ENTIRE codebase within your scope, not just recent changes. This is a comprehensive review.

## Output Format
Write your findings to ./claude-reviews/<N>/sub-reviews/<name>.md with this exact structure:

# <Name> Review: Session #<N>

## Summary
Brief overview of findings and overall assessment for this domain.

## Findings

### Finding 1: <descriptive title>
- **Severity:** critical / important / suggestion / info
- **Location:** file:line (or module/component if broader)
- **Description:** What was found and why it matters
- **Recommendation:** Specific action to take
- **Effort:** trivial / small / medium / large
- **Category:** <sub-category within this domain>

### Finding 2: ...
(continue for all findings)

## Statistics
- Files examined: <N>
- Findings: <N> critical, <N> important, <N> suggestion, <N> info
- Tools used: <list of tools whose output was consumed>

## Areas Needing Further Investigation
<Anything that was suspicious but inconclusive, requiring deeper analysis or a different sub-reviewer's perspective. Be specific about WHAT to investigate and WHY.>

IMPORTANT CONSTRAINTS:
- Write ONLY to ./claude-reviews/<N>/sub-reviews/<name>.md
- Do NOT edit any source code files
- Do NOT write to any other file under ./claude-reviews/
- Do NOT write to Review.md -- that is the parent session's responsibility
```

**Parallelization:** Launch all sub-reviewers in a single batch if possible. If Claude Code limits concurrent agents, launch in two waves of 5.

### Step 4: Monitor and Extend

After all sub-reviewers complete, read every sub-review file. Check the "Areas Needing Further Investigation" section of each.

For areas that need follow-up:
- Launch targeted follow-up agents to investigate specific concerns
- Follow-up agents APPEND to the existing sub-review file (add a clearly marked section)
- Follow-up template:
  ```
  ---

  ## Follow-up Investigation

  ### Investigated: <what was looked into>
  ### Findings: <what was discovered>
  ```

If a sub-reviewer produced results that conflict with another sub-reviewer's findings, investigate the conflict and record the resolution in Review.md.

### Step 5: Compile Review.md

Synthesize ALL sub-review findings into a single comprehensive `./claude-reviews/$0/Review.md`. This is the core deliverable.

**Structure:**

```
# Deep Review: Session #<N>

## Executive Summary
High-level assessment of the codebase. Overall health rating (Excellent / Good / Fair / Needs Attention / Critical).
Key strengths and most pressing concerns in 3-5 bullet points.

## Statistics
- Sub-reviews completed: <N>/10
- Total findings: <N> (<N> critical, <N> important, <N> suggestion, <N> info)
- Tools run: <list>
- Files examined: <N> (estimated across all sub-reviewers)

## Critical Findings
Aggregated from all sub-reviews. Deduplicated. Cross-referenced across domains.
For each:
- **Title:** descriptive
- **Source:** which sub-reviewer(s) identified this
- **Location:** file:line or module
- **Description:** full context
- **Recommendation:** specific fix
- **Effort:** estimated
- **Cross-cutting:** does this affect other domains? how?

## Important Findings
Same format as Critical.

## Suggestions
Same format, can be more concise.

## Informational
Brief list of observations that don't require action.

## SC-Auditor Findings
(Include this section ONLY if ScAuditResults.md exists)
Incorporate sc-auditor findings into the review, organized by proof status:
- **Proved vulnerabilities:** <list with severity, title, proof type -- these are confirmed and should be top remediation priority>
- **Confirmed findings:** <list verified by adversarial protocol>
- **Candidate findings:** <list with Security sub-reviewer's assessment of each>
- **Design tradeoffs:** <list -- note whether documentation adequately covers the risk>
Note which sc-auditor findings cross-cut with other sub-reviewer domains (e.g., an architecture issue that enables a security vulnerability).

## Cross-Cutting Concerns
Findings that span multiple sub-review domains. For example:
- A security issue that is also an architecture concern
- A testing gap that relates to a documentation gap
- A dependency issue that affects performance

## Complex Items for Separate Issues
Items that are too complex for immediate remediation, involve tradeoffs the developer should decide, or require broader team discussion. These are **candidate proposals**, not a final 1:1 issue list -- the remediation-plan stage applies the Deferral hierarchy to them (dedupes against the open backlog and bundles related items into the fewest issues). List each candidate finding here; do not pre-merge or pre-split them, just capture them so remediation-plan can cluster them.
For each:
- **Title:** proposed issue title
- **Description:** what needs to be done and why
- **Context:** relevant findings that inform this
- **Suggested labels:** bug/enhancement/security/documentation
- **Priority:** high/medium/low
- **Estimated effort:** small/medium/large

## Sub-Review Summaries
Brief summary of each sub-reviewer's assessment. Reference the full sub-review file for details.

| Sub-Reviewer | Findings | Health | Full Report |
|-------------|----------|--------|-------------|
| Security | 2 critical, 1 important | Needs Attention | sub-reviews/security.md |
| Code Quality | 0 critical, 3 important | Good | sub-reviews/code-quality.md |
| ... | ... | ... | ... |

## Prioritized Remediation Recommendations
Ordered list of what to fix first, considering:
- Severity (critical first)
- Effort (quick wins first within same severity)
- Dependencies (fix foundations before dependent code)
- User priorities (from interview)
```

### Step 6: Commit and Push

Commit both Review.md and all sub-review files:

```bash
git add ./claude-reviews/$0/Review.md ./claude-reviews/$0/sub-reviews/
git commit -m "claude-review(review): comprehensive review complete [session #$0]"
git push
```

### Step 7: Comment on PR

Post the Executive Summary to the PR thread:

```bash
gh pr comment --body "**Deep Review Complete**

<executive summary>

**Statistics:** <N> findings (<N> critical, <N> important, <N> suggestion, <N> info)

See \`claude-reviews/$0/Review.md\` for the full review."
```

## Stage Transition Signal

**Rules:**
- Write exactly one stage name, nothing else
- Only write this file if you want a NON-DEFAULT transition
- If you do not write this file, the orchestrator advances to `remediation-plan` (default)

**When to signal:**
- `review` -- if follow-up investigation revealed significant new areas to review (self-loop for a fresh comprehensive pass). Should be rare.
- Default (advance to remediation-plan) is correct in most cases.

## Re-trigger Behavior

If re-triggered:

1. Read existing Review.md and all sub-reviews
2. Identify what changed since the last review (new tools installed, scope changes, etc.)
3. Re-run only the affected sub-reviewers
4. Append to Review.md:

```
---

## Re-review (triggered during <stage> phase)

### Reason
<what changed>

### Updated Findings
<new or revised findings>

### Updated Statistics
<revised totals>
```
