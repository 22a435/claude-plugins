---
name: interview
description: Resolve open questions and ambiguities from research with user input. Asks structured questions and records decisions. Invoke with /issue-workflow:interview <issue-number>.
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash, Agent, Write, Edit, AskUserQuestion
---

# Interview Phase

You are performing the **interview** stage of an issue workflow. Your job is to identify every open question, ambiguity, and design choice -- then resolve each one through conversation with the user.

## Workflow Context

This skill is one stage of an 8-stage issue-to-PR workflow orchestrated by the `work-issue` CLI.

- **Branch:** `claude/<issue-number>` (created by the orchestrator during setup)
- **Work directory:** `./claude-work/<issue-number>/` -- each stage produces one document here
- **Document ownership:** You may READ any prior document. Only WRITE to your own output document inside `./claude-work/$0/` (where `$0` is the numeric GitHub issue ID passed as your argument). Never create files, directories, or write anywhere else under `./claude-work/`. When re-triggered, APPEND new sections -- never delete or overwrite existing content. Mark in-place edits with `> [IN-PLACE EDIT during <stage> phase]: <reason>`.
- **Commits:** Format: `claude-work(<stage>): <description> [#<issue>]`. Commit and push after completing the stage.
- **PR updates:** Post a summary to the PR or issue thread (via `gh pr comment` or `gh issue comment`) after each stage.
- **No self-loop:** Do not use `/loop`, `ScheduleWakeup`, or recursive `claude` invocations to re-run this skill. For short waits, run the command synchronously with `Bash` (it blocks until completion); for long waits, use `Bash` with `run_in_background` and `Monitor`. If you cannot finish in one pass, commit your partial progress and write your own stage name to `.next-stage` -- the orchestrator re-enters the stage within its loop-safety limits. Never re-invoke yourself.
- **Deferral hierarchy (never silently drop, never over-file):** Pre-existing bugs are not grounds for dismissal -- leave the codebase in the best working order regardless of origin. When work surfaces that you will not finish in this PR, walk this hierarchy and stop at the first tier that fits: **(1) Fix it in this PR** -- the default, and hard; "complex", "tedious", "touches many files", or "would take a while" are NOT reasons to defer, only a genuine Create-Issue criterion is (a tradeoff the user must decide / architectural refactor / high blast radius / team discussion / breaking upgrade / benchmark-needed). **(2) Append to a follow-up already filed in this run** -- if a follow-up you filed (or will file) this run naturally covers it, add it there rather than opening a second issue. **(3) Append to an existing open backlog issue** -- before filing anything new, search the backlog (`gh issue list --state open --limit 200 --json number,title,labels,body`); if an open issue already covers the area, comment the new context onto it instead of creating a duplicate. **(4) File one new, bundled issue** -- only if no tier above fits; bundle every co-deferred finding from this run that shares a subsystem or design decision into the SAME issue (one well-scoped issue, never one-per-finding). Filing a follow-up is a commitment that the proper fix exceeds this PR's scope -- not a way to avoid work; never leave a deferred finding as a document-only note, and record which tier each deferral took and why.
- **Read issues in full:** When you read a GitHub issue, read the *entire* thread -- the body **and every comment/reply** -- plus any linked issues, PRs, commits, or docs that look relevant. Critical scope and context often live in replies, not the original body; missing them causes under-scoped work. Treat the whole thread as the source of truth for what the issue actually asks.

## Context
- **Issue number:** $0 (numeric GitHub issue ID -- not a title, keyword, or topic name)
- **Work directory:** `./claude-work/$0/`
- **Input documents:** `./claude-work/$0/Issue.md`, `./claude-work/$0/Research.md`
- **Output document:** `./claude-work/$0/Interview.md`

## Instructions

### Step 1: Read Input Documents

Read both `Issue.md` and `Research.md` in full. Pay close attention to:
- The "Open Questions" section of Research.md
- Any ambiguities or implicit assumptions in the issue text
- Design choices that could go multiple ways
- Edge cases or error handling approaches not specified
- Performance, security, or UX tradeoffs

### Step 2: Prepare Questions

Compile a complete list of everything that needs user input. Group questions by topic. For each question:
- Provide context (why this matters, what depends on the answer)
- Present the options identified during research with their tradeoffs
- Include your recommendation if you have one (with reasoning)

### Step 3: Conduct the Interview

Use the `AskUserQuestion` tool to present questions to the user. Process one topic group at a time.

**For each topic group:**

1. Call `AskUserQuestion` with 1-4 questions for that group. For each question:
   - Set `header` to a short topic label (max 12 chars, e.g. "Auth", "Error Mode", "API Style", "DB Choice")
   - Write a `question` that includes context on why it matters and what depends on the answer
   - Provide 2-4 `options`, each with a `label` (the choice) and `description` (tradeoffs/implications). Derive options from Research.md findings. Mark your recommendation in the description (e.g. "Recommended -- ...")
   - Set `multiSelect: true` only when multiple options can be chosen simultaneously. Use `multiSelect: false` for mutually exclusive design choices
   - The user can always type a free-text "Other" response -- do not waste an option slot on "Other" or "None of the above"

2. After each `AskUserQuestion` call completes, review the responses:
   - If an answer is "Other" with free text, incorporate the user's stated preference
   - If an answer raises new questions, issue a follow-up `AskUserQuestion` before moving to the next topic group
   - If the user defers ("you decide"), make a clear recommendation via a single-question `AskUserQuestion` with options like "Accept recommendation" / "Let me reconsider" so the decision is explicitly recorded

3. Move to the next topic group

**Constructing questions from Research.md:**

Each open question in Research.md typically has: question text, options, tradeoffs, and recommendation. Map these directly:
- Research.md "Question" becomes the `question` field (prepend relevant context)
- Research.md "Options" become `options` (use option name as `label`, tradeoff summary as `description`)
- Research.md "Recommendation" becomes a note in the recommended option's `description`
- If Research.md lists more than 4 options, consolidate the least distinct options or group them -- the user can always use "Other" for anything excluded

**Batching rules:**
- Group questions by topic area (as identified in Step 2)
- If a topic has more than 4 questions, split into multiple `AskUserQuestion` calls
- If a topic has only 1 question, that's fine as a solo call
- Never combine questions from different topic areas in one call

**Guidelines:**
- If the user asks a question back, answer it using your research, then re-ask via `AskUserQuestion` if the original question wasn't resolved
- If the user identifies something that needs more research, note it (the research stage can be re-triggered later)
- Be thorough -- missing a question here means making an assumption later

### Step 4: Confirm Completeness

Review all open questions from Research.md and verify every one has been addressed. If any remain, ask about them via `AskUserQuestion`.

Once all questions are resolved, use `AskUserQuestion` to confirm:

```
AskUserQuestion({
  questions: [{
    question: "All open questions have been addressed. Here are the key decisions: [list 3-5 most impactful decisions]. Ready to proceed to planning?",
    header: "Confirm",
    options: [
      { label: "Proceed", description: "All decisions are captured correctly -- move to planning" },
      { label: "More input", description: "I have additional concerns or corrections" }
    ],
    multiSelect: false
  }]
})
```

If the user selects "More input", gather their additional input via follow-up `AskUserQuestion` calls before finalizing.

### Step 5: Write Interview.md

Write `./claude-work/$0/Interview.md` with this structure:

```
# Interview Record: Issue #<number>

## Summary
Brief overview of key decisions made.

## Decisions

### <Topic Area 1>

**Question:** <the question>
**Decision:** <what was decided>
**Rationale:** <why this was chosen>
**Impact:** <what this decision affects in the implementation>

### <Topic Area 2>
...

## Additional Context from User
Any extra information, preferences, or constraints the user provided during the interview that weren't captured in the original issue.

## Deferred Items
Any items the user chose to defer or that need further research before deciding.

## Constraints and Preferences
Summary of user's stated preferences for implementation approach, code style, priorities, etc.
```

### Step 6: Commit and Push

```bash
git add ./claude-work/$0/Interview.md
git commit -m "claude-work(interview): decisions recorded for issue #$0"
git push
```

### Step 7: Comment on Issue Thread

Post a summary to the GitHub issue:

```bash
gh issue comment $0 --body "<summary>"
```

The summary should include:
- Number of decisions made
- Key decisions and their rationale (brief)
- Any deferred items
- Reference to the full record in `./claude-work/$0/Interview.md`

## Stage Transition Signal

When running under the `work-issue` orchestrator, you can request a transition to a different stage by writing the target stage name to `./claude-work/$0/.next-stage`.

**Rules:**
- Write exactly one stage name, nothing else
- Only write this file if you want a NON-DEFAULT transition
- If you do not write this file, the orchestrator advances to `plan` (default)
- The orchestrator validates your request -- invalid transitions are ignored

**When to signal:**
- If the user identifies something during the interview that requires significant additional research (not just a quick lookup you can do inline), signal `research`:
  ```bash
  echo "research" > ./claude-work/$0/.next-stage
  ```
  The orchestrator will run research and then return through interview again before plan.
- Default (advance to plan) is correct when all questions are resolved.

## Re-trigger Behavior

If re-triggered from a later stage, read the existing Interview.md first. Append a new section:

```
---

## Follow-up Interview (triggered during <stage> phase)

### Reason
<why additional user input was needed>

### New Questions and Decisions
...
```
