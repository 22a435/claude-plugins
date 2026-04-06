---
name: review
description: Code quality review of all changes. Checks correctness, style, security, documentation. Requires user approval for functional changes. Invoke with /review <issue-number>.
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
- **Subagent cost optimization:** Review agents performing code analysis should use `model: "sonnet"` -- they are scanning for patterns and reporting findings. Keep the parent session's model for synthesizing results and making severity judgments.
- **Subagent write boundary:** Subagents in this stage must NOT create, edit, or write any files under `./claude-work/`. Only this parent session writes the output document. Include this constraint in every subagent prompt you compose.

## Context
- **Issue number:** $0 (numeric GitHub issue ID -- not a title, keyword, or topic name)
- **Work directory:** `./claude-work/$0/`
- **All documents available for reference** (read as needed, do not modify others)
- **Output document:** `./claude-work/$0/Review.md`

## Instructions

### Step 1: Gather Review Context

1. Get the full diff of all changes on this branch:
   ```bash
   git diff main...HEAD
   ```

2. Get the list of changed files:
   ```bash
   git diff main...HEAD --name-only
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

### Step 5: Handle Findings by Severity

**Critical and Important findings** (bugs, security issues, data loss risks, code quality issues requiring code changes):
- Do NOT attempt to fix these directly during review
- Document them thoroughly in Review.md with full details (see Step 7)
- After completing the review, signal `debug` as the next stage
- The debug stage will investigate root causes and apply fixes with proper verification

**Suggestion findings** (style improvements, minor optimizations, documentation, comments):
- For non-functional changes: implement them without asking unless you're unsure
- For changes affecting features or functionality: present them to the user, get approval, then implement approved changes
- Record all decisions

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

Post summary to PR:
```bash
gh pr comment --body "<review summary and final assessment>"
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
