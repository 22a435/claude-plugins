---
name: interview
description: Resolve ambiguities, present tool recommendations for approval, gather review priorities. Invoke with /deep-review:interview <session-number>.
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash, Agent, Write, Edit, AskUserQuestion
---

# Interview Phase

You are performing the **interview** stage of a deep codebase review. Your job is to resolve ambiguities, present tool recommendations for user approval, and gather review priorities.

## Workflow Context

This skill is one stage of a multi-stage deep review workflow orchestrated by the `deep-review` CLI.

- **Branch:** `claude/review/<session-number>` (created by the orchestrator during setup)
- **Work directory:** `./claude-reviews/<session-number>/` -- each stage produces one document here
- **Document ownership:** You may READ any prior document. Only WRITE to your own output document inside `./claude-reviews/$0/` (where `$0` is the session number passed as your argument). Never create files, directories, or write anywhere else under `./claude-reviews/`. When re-triggered, APPEND new sections -- never delete or overwrite existing content. Mark in-place edits with `> [IN-PLACE EDIT during <stage> phase]: <reason>`.
- **Commits:** Format: `claude-review(<stage>): <description> [session #<N>]`. Commit and push after completing the stage.
- **PR updates:** Post a summary to the PR thread (via `gh pr comment`) after completing the stage.

## Context
- **Session number:** $0 (the review session number passed as your argument)
- **Work directory:** `./claude-reviews/$0/`
- **Input documents:** `./claude-reviews/$0/Session.md`, `./claude-reviews/$0/Context.md` (and `Interview.md`, `UpdateTooling.md` if re-triggered)
- **Output document:** `./claude-reviews/$0/Interview.md`

## Instructions

### Step 1: Read Input Documents

Read `Context.md` in full. If this is a re-trigger, also read the existing `Interview.md` and `UpdateTooling.md` (if it exists) to understand what has already been decided and what tools were installed.

### Step 2: SC-Auditor Recommendation (Solidity Projects Only)

If Context.md contains a "Solidity / Smart Contract Context" section (indicating Solidity files were detected), **strongly recommend sc-auditor** before presenting other tools:

```
AskUserQuestion({
  questions: [{
    question: "This project contains Solidity smart contracts. sc-auditor provides specialized security analysis with parallel vulnerability hunt lanes, adversarial falsification (Devil's Advocate protocol), and proof generation. It also uses Slither, Aderyn, Echidna, Halmos, and Foundry as subtools, and cross-references findings against real-world exploits via Solodit. Enable sc-auditor for this review?",
    header: "SC-Audit",
    options: [
      { label: "Approve (Recommended)", description: "Run sc-auditor as a dedicated audit stage before the main review. Requires Node.js 22+." },
      { label: "Reject", description: "Skip sc-auditor -- use only the standard review pipeline for security" }
    ],
    multiSelect: false
  }]
})
```

If approved, ask about Solodit API key:
```
AskUserQuestion({
  questions: [{
    question: "sc-auditor can cross-reference findings against real-world confirmed exploits via the Solodit API. Do you have a Solodit API key available?",
    header: "Solodit",
    options: [
      { label: "Yes, it's set", description: "SOLODIT_API_KEY is in my environment or .env file" },
      { label: "No", description: "Skip Solodit cross-referencing -- audit still works without it" }
    ],
    multiSelect: false
  }]
})
```

Record the sc-auditor decision in Interview.md under a dedicated section. If approved, this will trigger the `plan-sc-audit` stage after interview completes.

### Step 3: Present Tool Recommendations

Use `AskUserQuestion` to present recommended tools from Context.md for approval. Group tools by category.

**For each category of tools** (static analysis, security, dependency, etc.):

Call `AskUserQuestion` with one question per tool in that category (up to 4 per call -- split into multiple calls if a category has more):
- `header`: category abbreviation (e.g. "Security", "Static", "Deps", "Quality")
- `question`: "[Tool name]: [what it does and what it catches]. Install: `[command]`. Persistence risk: [low/medium/high]. Approve this tool?"
- `options`:
  - `label`: "Approve", `description`: "Install and use in this review"
  - `label`: "Reject", `description`: "Skip this tool"
  - `label`: "Defer", `description`: "Decide later, after seeing other results"
- `multiSelect: false` (these are mutually exclusive per tool)

**If no tools were recommended**, skip to Step 4.

**After all tool questions are answered**, ask about additional tools:
```
AskUserQuestion({
  questions: [{
    question: "Are there any additional tools you'd like to include that weren't recommended?",
    header: "More Tools",
    options: [
      { label: "No, proceed", description: "The approved set is sufficient" },
      { label: "Yes", description: "I have tools to add -- describe in Other" }
    ],
    multiSelect: false
  }]
})
```

If the user selects "Yes" and provides tool names via "Other", record them as user-requested tools.

**Handle batch responses:** If the user's free-text "Other" response on any tool question says "approve all" or "reject all", apply that decision to all remaining unanswered tool questions without asking further.

### Step 4: Gather Review Priorities

Use `AskUserQuestion` to gather review priorities. Split into two calls (2 questions each) to keep each focused:

**Call 1 -- priorities and focus:**

```
AskUserQuestion({
  questions: [
    {
      question: "Which review aspects matter most to you? Select all that are high priority.",
      header: "Priorities",
      options: [pick the top 4 most relevant to this project from: security, performance, code quality, architecture, testing, dependencies, documentation -- choose based on what Context.md revealed],
      multiSelect: true
    },
    {
      question: "Are there specific directories, modules, or concerns to focus on? Select any known problem areas, or use Other to describe.",
      header: "Focus Areas",
      options: [derive 2-4 options from Context.md findings -- e.g. specific modules that appeared complex, directories with high dependency counts, areas flagged in open questions],
      multiSelect: true
    }
  ]
})
```

**Call 2 -- exclusions and concerns:**

```
AskUserQuestion({
  questions: [
    {
      question: "Any areas to explicitly exclude from the review?",
      header: "Out of Scope",
      options: [derive 2-4 options from Context.md -- e.g. generated code directories, vendored dependencies, legacy modules, test fixtures],
      multiSelect: true
    },
    {
      question: "Anything specific you'd like the review to look for? Select any that apply, or describe in Other.",
      header: "Concerns",
      options: [derive 2-4 options from Context.md open questions or common concerns for the detected tech stack -- e.g. "Memory leaks", "API backward compat", "Secret exposure", "Circular deps"],
      multiSelect: true
    }
  ]
})
```

### Step 5: Ask About Derived Interfaces

If Context.md detected derived interfaces, use `AskUserQuestion` to confirm them:

```
AskUserQuestion({
  questions: [
    {
      question: "Context analysis detected these derived interfaces: [list them]. Which are accurate and should be included in the review?",
      header: "Interfaces",
      options: [list up to 4 detected interfaces -- label: interface name, description: what was detected. If more than 4, batch into multiple calls],
      multiSelect: true
    },
    {
      question: "Are there any additional interfaces, APIs, or SDKs not listed above that should be reviewed?",
      header: "Undocumented",
      options: [
        { label: "No", description: "The detected set is complete" },
        { label: "Yes", description: "I'll describe them -- use Other" }
      ],
      multiSelect: false
    }
  ]
})
```

If Context.md detected no derived interfaces, skip this step entirely.

### Step 6: Resolve Open Questions

Use `AskUserQuestion` to resolve open questions from Context.md.

**Constructing questions from Context.md:**
- Group questions by topic
- For each group, call `AskUserQuestion` with 1-4 questions
- For each question: set `header` to a short topic label, write the open question as `question` with added context, and provide 2-4 options representing plausible answers or approaches
- Use `multiSelect: false` for mutually exclusive choices, `multiSelect: true` when multiple answers can apply

**Handle deferrals:**
- If the user selects "Other" and writes "you decide" or similar, provide a clear recommendation and record it as the decision
- If the user writes "I don't know" or similar, record it as deferred and note assumptions being made

**Follow-ups:** If an answer is ambiguous or raises new questions, issue a follow-up `AskUserQuestion` call to clarify before moving on.

If Context.md has no open questions, skip this step.

### Step 7: Write Interview.md

Write `./claude-reviews/$0/Interview.md`:

```
# Interview Record: Review Session #<N>

## SC-Auditor Decision
(Include only if Solidity detected)
- **Approved:** yes/no
- **Solodit API:** available/not available
- **Subtools to install:** sc-auditor, slither, aderyn, foundry, echidna, medusa, halmos (as applicable)

## Approved Tools
| Tool | Category | Persist to Repo |
|------|----------|----------------|
| ruff | static-analysis | yes |
| ...  | ...      | ...            |

## Rejected Tools
| Tool | Reason |
|------|--------|
| ...  | ...    |

## User-Requested Tools
Tools the user requested that were not in the original recommendations.

## Review Priorities
Ordered list of what matters most, with user's rationale.

## Focus Areas
Specific directories, modules, or concerns to prioritize.

## Out of Scope
What to skip and why.

## Derived Interfaces to Review
Which interfaces to include and their expected relationship to core code.

## Decisions
All other decisions from the interview, grouped by topic.

## Additional Context from User
Any other context the user provided.
```

### Step 8: Commit, Push, and Comment

```bash
git add ./claude-reviews/$0/Interview.md
git commit -m "claude-review(interview): decisions recorded [session #$0]"
git push
```

Post summary to PR:
```bash
gh pr comment "claude/review/$0" --body "**Interview:** <N> decisions recorded. <N> tools approved. Priority: <top priorities>. Focus areas: <areas>."
```

## Stage Transition Signal

When running under the `deep-review` orchestrator, you can request a transition to a different stage by writing the target stage name to `./claude-reviews/$0/.next-stage`.

**Rules:**
- Write exactly one stage name, nothing else
- Only write this file if you want a NON-DEFAULT transition
- If you do not write this file, the orchestrator advances to `plan` (default)
- The orchestrator validates your request -- invalid transitions are ignored

**When to signal:**
- `update-tooling` -- if any tools were approved for installation:
  ```bash
  echo "update-tooling" > ./claude-reviews/$0/.next-stage
  ```
- `plan-sc-audit` -- if sc-auditor was approved, all tools are already installed (no update-tooling needed), and you're ready to configure the audit:
  ```bash
  echo "plan-sc-audit" > ./claude-reviews/$0/.next-stage
  ```
  Note: if sc-auditor was approved AND other tools also need installing, signal `update-tooling` first. After update-tooling installs everything and returns to interview, signal `plan-sc-audit` on the next pass.
- `interview` -- if you need another round of questions (should be rare):
  ```bash
  echo "interview" > ./claude-reviews/$0/.next-stage
  ```
- Default (advance to plan) is correct when no tools need installing and sc-auditor was NOT approved.

## Re-trigger Behavior

If re-triggered and `./claude-reviews/$0/Interview.md` already exists:

1. Read the existing Interview.md and UpdateTooling.md (if exists)
2. **If the existing Interview.md shows sc-auditor was approved** (in the "SC-Auditor Decision" section) **and this re-trigger is after update-tooling installed the tools**, signal `plan-sc-audit` as the next stage:
   ```bash
   echo "plan-sc-audit" > ./claude-reviews/$0/.next-stage
   ```
   You may skip the full re-interview in this case -- just append a brief note and signal.
3. Otherwise, identify what has changed or what new questions arose
4. Append a new section:

```
---

## Follow-up Interview (triggered during <stage> phase)

### Reason
<why another interview was needed>

### New Decisions
<additional decisions>

### Updated Tools
<any changes to tool approvals>
```
