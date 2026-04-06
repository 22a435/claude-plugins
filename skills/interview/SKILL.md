---
name: interview
description: Resolve open questions and ambiguities from research with user input. Asks structured questions and records decisions. Invoke with /interview <issue-number>.
allowed-tools: Read, Grep, Glob, Bash, Agent, Write, Edit
---

# Interview Phase

You are performing the **interview** stage of an issue workflow. Your job is to identify every open question, ambiguity, and design choice -- then resolve each one through conversation with the user.

## Workflow Context

This skill is one stage of an 8-stage issue-to-PR workflow orchestrated by the `work-issue` CLI.

- **Branch:** `claude/<issue-number>` (created by the orchestrator during setup)
- **Work directory:** `./claude-work/<issue-number>/` -- each stage produces one document here
- **Document ownership:** You may READ any prior document. Only WRITE to your own output document. When re-triggered, APPEND new sections -- never delete or overwrite existing content. Mark in-place edits with `> [IN-PLACE EDIT during <stage> phase]: <reason>`.
- **Commits:** Format: `claude-work(<stage>): <description> [#<issue>]`. Commit and push after completing the stage.
- **PR updates:** Post a summary to the PR or issue thread (via `gh pr comment` or `gh issue comment`) after each stage.
- **Subagent cost optimization:** Downgrade information-gathering agents (Explore, web research, context7) to `model: "sonnet"`. Keep the parent session's model for implementation and reasoning agents.

## Context
- **Issue number:** $0
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

Present questions to the user in logical groups (not all at once). For each group:

1. Introduce the topic area briefly
2. Ask the questions, providing context and options
3. Wait for the user's answers
4. Confirm your understanding of their decisions
5. If an answer raises new questions, ask follow-ups immediately
6. Move to the next topic group

**Guidelines:**
- Ask one topic group at a time -- do not dump all questions at once
- If the user's answer is ambiguous, ask for clarification
- If the user asks a question back, answer it using your research
- If the user identifies something that needs more research, note it (the research stage can be re-triggered later)
- If the user defers a decision ("you decide" / "whatever you think"), make a clear recommendation and confirm they accept it
- Be thorough -- missing a question here means making an assumption later

### Step 4: Confirm Completeness

Before finalizing, review all open questions from Research.md and verify every one has been addressed. If any remain, ask about them.

Tell the user: "All open questions have been addressed. I'll document the decisions and proceed to planning."

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
