---
name: review
description: Code quality review of all changes. Checks correctness, style, security, documentation. Requires user approval for functional changes. Invoke with /issue-workflow:review <issue-number>.
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash, Agent, Write, Edit, WebSearch, WebFetch, Skill
---

# Review Phase

You are performing the **review** stage of an issue workflow. Implementation and verification are complete. Your job is to review all changes for quality, correctness, security, and completeness.

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
- **All documents available for reference** (read as needed, do not modify others)
- **Output document:** `./claude-work/$0/Review.md`

## Instructions

### Step 1: Gather Review Context

**Diff against `origin/main` (the canonical upstream), never local `main`.** The orchestrator does not keep local `main` current, so it is almost always stale -- diffing against it folds other people's upstream commits into the review and misrepresents what this branch actually changed. Fetch first:

```bash
git fetch origin main
```

1. Get the full diff of all changes on this branch:
   ```bash
   git diff origin/main...HEAD
   ```

2. Get the list of changed files:
   ```bash
   git diff origin/main...HEAD --name-only
   ```

3. Read the Plan.md for context on intended design
4. Read Execute.md for implementation notes
5. Read Verify.md for any edge cases or resolved issues

### Step 2: Discover Repo-Local Review Tooling

Before running your own review passes, check the repo being reviewed for custom review skills, subagents, or tooling that should be incorporated. Search for:

1. **Custom Claude skills/commands:** Look in `.claude/skills/`, `.claude/commands/`, and any `CLAUDE.md` files for review-related skills or slash commands (e.g., anything with "review", "lint", "audit", "check", "analyze" in the name or description).

2. **Review subagent definitions:** Look for agent configuration files (e.g., `.claude/agents/`, agent YAML/JSON/MD files) that define review-focused subagents.

3. **Automated analysis scripts:** Look for review-oriented scripts or tooling (e.g., `scripts/review*`, `scripts/lint*`, `scripts/audit*`, Makefiles with `lint`/`check`/`review` targets, CI config files with analysis steps that can be run locally).

4. **Static analysis and linter configs:** Look for configuration files that indicate available analysis tools (e.g., `.eslintrc*`, `pyproject.toml` with ruff/mypy/pylint sections, `.golangci.yml`, `clippy.toml`, `biome.json`, `.rubocop.yml`, etc.). If the tooling is installed or installable, plan to run it.

**How to search** (run in parallel):
```
# Skills and commands
find .claude/ -type f 2>/dev/null | head -50
# Review-related scripts
find . -maxdepth 3 -type f \( -name '*review*' -o -name '*lint*' -o -name '*audit*' -o -name '*check*' -o -name '*analyze*' \) -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null
# Makefile targets
grep -iE '^\S*(?:review|lint|check|audit|analyze)\S*:' Makefile makefile GNUmakefile 2>/dev/null
# Agent definitions
find . -maxdepth 3 -type f -path '*agent*' -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null
```

**What to do with discovered tooling:**

- **Custom skills/commands:** Invoke them (via `/skill-name` or by reading and following their instructions) and collect their output. If a skill produces a document, read it.
- **Subagents:** Launch them as parallel Agent calls alongside your own review agents in Step 3, passing the diff or changed file list as context.
- **Scripts and linters:** Run them via Bash and capture their output. If they produce structured findings (warnings, errors), parse them into the Critical/Important/Suggestion categories.
- **If nothing is found:** Proceed normally -- the built-in review passes in Step 3 are always run regardless.

Record what repo-local tooling you discovered (or that none was found) so it can be included in the Review.md output.

### Step 3: Conduct Parallel Reviews

Launch parallel review agents for different aspects. Include any repo-local review subagents or skills discovered in Step 2 alongside these built-in passes:

**Correctness Review:**
- Does the code do what the plan intended?
- Are there logic errors, off-by-one errors, or missing edge cases?
- Are error paths handled properly?
- Are there race conditions or concurrency issues?

**Security Review:**
- Input validation and sanitization
- Authentication and authorization
- Injection vulnerabilities (SQL, XSS, command injection)
- Secrets or credentials in code
- Dependency vulnerabilities

**Code Quality Review:**
- Code style consistent with the rest of the repo
- Naming conventions followed
- Appropriate abstractions (not over-engineered, not under-engineered)
- Dead code or unnecessary complexity
- DRY violations or unnecessary duplication

**Documentation Review:**
- Does the repo's CLAUDE.md need updates (new commands, changed patterns)?
- Do README or other docs need updates?
- Are new public APIs documented?
- Are complex logic sections adequately commented?

**Test Review:**
- Are new tests adequate? Do they cover edge cases?
- Are existing tests still valid or do they need updates?
- Is test coverage appropriate for the changes?

### Step 4: Compile Review Findings

Aggregate findings from **all sources** -- both the built-in review passes (Step 3) and any repo-local tooling (Step 2). Deduplicate overlapping findings, preferring the more specific or actionable version. If repo-local tools produced their own severity ratings, map them into the categories below.

Categorize each finding:
- **Critical:** Must fix before merge (bugs, security issues, data loss risks)
- **Important:** Should fix (code quality, missing tests, documentation gaps)
- **Suggestion:** Nice to have (style improvements, minor optimizations)

**Severity is determined by current impact, not by origin.** A finding's severity reflects its effect on correctness, security, or quality *today* -- NOT whether it predates this PR. "Pre-existing" is never a valid reason to downgrade or dismiss a finding. The goal is to leave the codebase in the best working order regardless of where a bug came from.

The only legitimate reasons to lower severity or route a finding away from "fix now" are the **Create-Issue criteria**: the proper fix requires tradeoffs the user should decide, architectural refactoring, high blast radius, team discussion, breaking upgrades, or performance benchmarking. These findings do not get dismissed -- they get filed as follow-up issues per Step 5a. Silent dismissal is never acceptable.

### Step 5: Handle Findings by Severity

Route each finding into one of three lanes based on the scope of its proper fix:

**Lane A -- Critical/Important with a clear, bounded fix:**
- Do NOT attempt to fix these directly during review
- Document them thoroughly in Review.md with full details (see Step 7)
- After completing the review, signal `debug` as the next stage
- The debug stage will investigate root causes and apply fixes with proper verification
- This lane is the default for Critical/Important findings unless a Create-Issue criterion clearly applies

**Lane B -- Critical/Important that meets a Create-Issue criterion** (tradeoffs / architecture / high blast radius / team discussion / breaking upgrade / benchmark-needed):
- File a follow-up GitHub issue in Step 5a with full context
- If a safe, low-risk short-term mitigation exists (e.g., a minimal guard, revert, or workaround that does not commit to the larger design), route that mitigation to `debug` as a Lane-A finding; the follow-up issue captures the real fix
- If no safe mitigation exists, document clearly in Review.md why merge may still proceed and ensure the follow-up issue captures the full context
- Never let a Create-Issue finding remain as a document-only note -- it must become a real issue

**Lane C -- Suggestions** (style improvements, minor optimizations, documentation, comments):
- For non-functional changes: implement them without asking unless you're unsure. Pre-existing status does NOT exempt a suggestion from being applied -- if you touched or reviewed the area, the cleanup is in scope
- For changes affecting features or functionality: present them to the user, get approval, then implement approved changes
- If a suggestion meets the Create-Issue criteria (e.g., a broader style/architecture cleanup that should not be bundled into this PR), file it as a follow-up issue per Step 5a rather than dropping it
- Record all decisions

### Step 5a: File Follow-up Issues (search backlog, bundle, then create)

Every finding routed to Lane B above (and any Lane-C suggestion that meets the Create-Issue criteria) must end up on a real GitHub issue -- do not rely on Review.md alone. But apply the **Deferral hierarchy** from the Workflow Context: do not auto-create one issue per finding. Work the deferred set as a batch:

1. **Search the backlog first.** Pull the open issues once:
   ```bash
   gh issue list --state open --limit 200 --json number,title,labels,body > /tmp/backlog-$0.json
   ```
   For each deferred finding, check whether an open issue already covers the same area/subsystem. If so, **append** the new context as a comment instead of creating a duplicate:
   ```bash
   gh issue comment <existing-#> --body "<finding + why it surfaced during review of PR #<pr-number> for issue #<issue-number>. See ./claude-work/$0/Review.md>"
   ```
2. **Bundle the remainder.** Group every genuinely-new finding that shares a subsystem or a design decision into the SAME new issue -- one well-scoped, single-PR-sized issue per cluster, never one-per-finding. Only split into multiple new issues when the clusters are genuinely independent (could be worked in parallel with no shared decision).
3. **Create the bundled issue(s).** Auto-create without asking; the `followup,from-pr-#<pr-number>` label makes spurious ones easy to find and close:
   ```bash
   gh issue create \
     --title "<concise title describing the cluster>" \
     --body "<body content per template below>" \
     --label "followup,from-pr-#<pr-number>"
   ```

Each new issue's body must include:
- **Description** of the problem(s) or opportunity -- if the issue bundles several findings, list each as a checklist item so the bundle is clearly one scope of work
- **Exact finding(s)** quoted from Review.md (so future readers see the original context)
- **Suggested approach** if one is known (otherwise note "approach TBD")
- **Why deferred**: which Create-Issue criterion applies (tradeoff / architecture / blast radius / team discussion / breaking upgrade / benchmark-needed / out-of-scope)
- **Cross-reference** line: `Identified during review of PR #<pr-number> for issue #<issue-number>. See ./claude-work/<issue>/Review.md` (use `gh pr view --json number` to get the PR number if unknown)

Capture the returned issue number and URL (and any existing-issue numbers you appended to). Record them in Review.md's "Follow-up Issues Created" section (see Step 7), noting for each finding which hierarchy tier it took (appended to #n / new bundled #n).

**Reminder -- when to file, when to fix:** The Create-Issue criteria are narrow on purpose. If a Critical/Important finding is a bounded bug fix -- even a hairy one -- it goes to `debug`, not to a follow-up issue. Filing a follow-up is a commitment that the *proper* fix exceeds this PR's scope, not a way to avoid work.

### Step 6: Implement Approved Suggestion Changes

Apply all approved **Suggestion**-level changes and non-functional improvements. Track what was changed.

Do NOT implement Critical or Important findings -- those are handled by the debug stage.

### Step 7: Write Review.md

```
# Code Review: Issue #<number>

## Summary
- **Files reviewed:** <N>
- **Findings:** <N critical, N important, N suggestions>
- **Changes made:** <N items addressed>
- **Code changes made:** <yes/no -- if yes, signals verify for orchestrator-level re-verification>
- **Follow-up issues filed:** <N -- list numbers, or "none">
- **Repo-local tooling used:** <list of discovered skills/subagents/linters, or "none found">

## Repo-Local Tooling Results
<If any repo-local review skills, subagents, scripts, or linters were discovered and run, summarize each tool's output here. Include the tool name, how it was invoked, and its key findings. Omit this section if no repo-local tooling was found.>

## Review Findings

### Critical
<findings, decisions, and resolutions>

### Important
<findings, decisions, and resolutions>

### Suggestions
<findings, decisions, and resolutions>

## Follow-up Issues Created

<One subsection per issue touched in Step 5a -- both newly-created bundles and existing issues you appended to. If none were filed, write the single line: "None -- all findings were either fixed or routed to debug.">

### Issue #<n>: <title>
- **URL:** <gh url>
- **Tier:** <new bundled issue | appended to existing #n>
- **Source finding(s):** <quote or section reference back to Review Findings above -- list all findings bundled here>
- **Why deferred:** <criterion: tradeoff / architecture / blast radius / team-discussion / breaking-upgrade / benchmark-needed / out-of-scope>
- **Mitigation applied in this PR:** <yes -- describe | no>

## Changes Made During Review
List of changes applied, with rationale.

## Documentation Updates
What documentation was added or updated.

## Final Assessment
Overall quality assessment. Is the code ready for merge?
```

### Step 8: Commit, Push, and Comment

**Important:** Commit ALL files changed during this stage -- both the review document and any code files modified as part of suggestion-level fixes. Do not commit only Review.md.

```bash
git add -A
git commit -m "claude-work(review): review complete for issue #$0"
git push
```

Post summary to PR. The comment MUST include a `Deferred (follow-up issues):` line -- either a list of issue numbers/URLs filed in Step 5a, or the literal word `none`. Never omit this line silently; it is how the reviewer sees what was deferred.

```bash
gh pr comment --body "<review summary and final assessment

Deferred (follow-up issues): #<n1>, #<n2>  # or 'none'>"
```

## Stage Transition Signal

When running under the `work-issue` orchestrator, you can request a transition to a different stage by writing the target stage name to `./claude-work/$0/.next-stage`.

**Rules:**
- Write exactly one stage name, nothing else
- Only write this file if you want a NON-DEFAULT transition
- If you do not write this file, the orchestrator advances to `integrate` (default)
- The orchestrator validates your request -- invalid transitions are ignored

**When to signal:**
- `debug` -- if any Critical or Important findings were identified that require root cause investigation and code fixes. This takes priority over `verify`:
  ```bash
  echo "debug" > ./claude-work/$0/.next-stage
  ```
  The orchestrator will run a debug session, then return to review for a fresh review pass.
- `verify` -- if Suggestion-level code changes were made during review (beyond documentation-only changes) but no Critical/Important issues were found:
  ```bash
  echo "verify" > ./claude-work/$0/.next-stage
  ```
- Default (advance to integrate) is correct when no code changes were made and no Critical/Important issues were found.

## Re-trigger Behavior

If re-triggered (e.g., after integration), append a new section:

```
---

## Re-review (triggered during <stage> phase)

### Scope
<what needed re-review and why>

### Findings
...

### Changes Made
...
```
