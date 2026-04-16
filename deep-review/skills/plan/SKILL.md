---
name: plan
description: Create a comprehensive review plan based on context, interview, and available tools. Requires user approval. Invoke with /deep-review:plan <session-number>.
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash, Agent, Write, Edit, AskUserQuestion
---

# Planning Phase

You are performing the **planning** stage of a deep codebase review. Your job is to create a thorough review plan that defines which sub-reviewers to launch, what tools to use, and how to scope the review.

## Workflow Context

This skill is one stage of a multi-stage deep review workflow orchestrated by the `deep-review` CLI.

- **Branch:** `claude/review/<session-number>` (created by the orchestrator during setup)
- **Work directory:** `./claude-reviews/<session-number>/` -- each stage produces one document here
- **Document ownership:** You may READ any prior document. Only WRITE to your own output document inside `./claude-reviews/$0/` (where `$0` is the session number passed as your argument). Never create files, directories, or write anywhere else under `./claude-reviews/`. You may edit Plan.md in place freely -- git history serves as the audit trail. No append-only constraint applies to this stage.
- **Commits:** Format: `claude-review(plan): <description> [session #<N>]`. Use `claude-review(plan): draft plan [session #$0]` for the initial write and `claude-review(plan): revise plan -- <summary> [session #$0]` for subsequent edits. Commit and push after writing the initial draft AND after each round of revisions.
- **PR updates:** Post a summary to the PR thread (via `gh pr comment`) after completing the stage.
- **Subagent cost optimization:** Downgrade information-gathering agents (Explore, web research, context7) to `model: "sonnet"`. Keep the parent session's model for planning and judgment.
- **Subagent write boundary:** Subagents in this stage must NOT create, edit, or write any files under `./claude-reviews/`. Only this parent session writes the output document. Include this constraint in every subagent prompt you compose.

## Context
- **Session number:** $0 (the review session number passed as your argument)
- **Work directory:** `./claude-reviews/$0/`
- **Input documents:** `./claude-reviews/$0/Context.md`, `./claude-reviews/$0/Interview.md`, `./claude-reviews/$0/UpdateTooling.md` (if exists), `./claude-reviews/$0/ScAuditResults.md` (if exists -- from sc-auditor stage)
- **Output document:** `./claude-reviews/$0/Plan.md`

## Instructions

### Step 1: Read All Input Documents

Read `Context.md`, `Interview.md`, and `UpdateTooling.md` (if it exists) in full. Cross-reference the interview decisions against the context findings. Understand:
- What the project is and how it's structured
- What tools are available (pre-existing + newly installed)
- What the user's review priorities are
- What is out of scope
- What derived interfaces to include

**If `ScAuditResults.md` exists** (from the sc-auditor stage), read it in full. This contains specialized smart contract security findings with proof status (proved/confirmed/candidate/design_tradeoff/discarded). These findings should heavily inform the plan:
- The Security sub-reviewer should **validate and expand** sc-auditor findings, not re-discover them
- The Security sub-reviewer should focus on areas sc-auditor did NOT cover (non-Solidity code, deployment scripts, off-chain components, infrastructure)
- The Architecture sub-reviewer should consider structural issues from sc-auditor's system map
- sc-auditor's proved/confirmed findings should be highlighted in the plan as high-priority remediation targets
- sc-auditor's design_tradeoff findings should be flagged for the Documentation sub-reviewer

If needed, use Explore agents with `model: "sonnet"` to do targeted codebase lookups to inform the plan.

### Step 2: Draft the Plan

Create a comprehensive review plan. The plan determines exactly which sub-reviewers will run and what scope each covers.

**Plan structure:**

```
# Review Plan: Session #<N>

## Overview
What is being reviewed, the overall approach, and expected depth.

## Sub-Reviewers

### Sub-Reviewer 1: Security
- **Focus:** SAST, secrets detection, dependency vulnerabilities, auth/authz, injection vectors, crypto usage
- **Tools:** <list of tools this sub-reviewer will use and their commands>
- **Scope:** <directories/files to cover, any exclusions>
- **Output:** sub-reviews/security.md

### Sub-Reviewer 2: Code Quality
- **Focus:** Complexity hotspots, duplication, dead code, naming consistency
- **Tools:** <list>
- **Scope:** <scope>
- **Output:** sub-reviews/code-quality.md

### Sub-Reviewer 3: Architecture
- **Focus:** Modularity, coupling analysis, dependency direction, layering violations, circular dependencies
- **Tools:** <list>
- **Scope:** <scope>
- **Output:** sub-reviews/architecture.md

### Sub-Reviewer 4: Documentation
- **Focus:** README completeness, CLAUDE.md accuracy, API doc coverage, inline comment quality. Identify CLAUDE.md sections containing large content blocks that should reference dedicated docs files instead.
- **Tools:** <list>
- **Scope:** <scope>
- **Output:** sub-reviews/documentation.md

### Sub-Reviewer 5: Style/Formatting
- **Focus:** Formatting consistency, style guide adherence, naming conventions, file organization
- **Tools:** <list>
- **Scope:** <scope>
- **Output:** sub-reviews/style-formatting.md

### Sub-Reviewer 6: Testing
- **Focus:** Test coverage, test quality, edge case coverage, test organization, untested public APIs
- **Tools:** <list>
- **Scope:** <scope>
- **Output:** sub-reviews/testing.md

### Sub-Reviewer 7: Dependencies
- **Focus:** Outdated dependencies, vulnerabilities, unused deps, version pinning, license compatibility
- **Tools:** <list>
- **Scope:** <scope>
- **Output:** sub-reviews/dependencies.md

### Sub-Reviewer 8: Performance
- **Focus:** N+1 queries, unbounded operations, missing caching, large allocations, resource cleanup
- **Tools:** <list>
- **Scope:** <scope>
- **Output:** sub-reviews/performance.md

### Sub-Reviewer 9: Derived Interfaces (if applicable)
- **Focus:** SDK/API/RPC/MCP/WebUI consistency with core codebase, generated type sync, API contract documentation
- **Tools:** <list>
- **Scope:** <scope>
- **Output:** sub-reviews/derived-interfaces.md

### Sub-Reviewer 10: Simplification
- **Focus:** Code size reduction opportunities, unnecessary indirection, over-engineering, opportunities to merge abstractions, simpler alternatives
- **Tools:** <list>
- **Scope:** <scope>
- **Output:** sub-reviews/simplification.md

## SC-Auditor Findings Integration
(Include this section ONLY if ScAuditResults.md exists)
How sc-auditor findings are incorporated:
- **Proved/Confirmed findings:** <count> -- these are validated vulnerabilities that should be prioritized for remediation
- **Candidate findings:** <count> -- plausible but unproven; Security sub-reviewer should assess these
- **Design tradeoffs:** <count> -- Documentation sub-reviewer should verify these are properly documented
- **Security sub-reviewer scope adjustment:** Focus on non-Solidity security (off-chain, deployment, infrastructure) and validation/expansion of sc-auditor findings rather than re-discovery
- **Areas sc-auditor did not cover:** <list of non-Solidity code areas>

## Automated Tool Runs
Which tools will be run before sub-reviewers launch, and how their output feeds into sub-reviews:
| Tool | Command | Output Location | Consumed By |
|------|---------|----------------|-------------|
| ruff | `ruff check . --output-format json` | `.tool-output/ruff.json` | Code Quality, Style |
| ...  | ...     | ...            | ...         |

## Review Priorities (from Interview)
Ordered list of priorities that determines relative depth of each sub-reviewer.

## Out of Scope
Directories, modules, or aspects excluded from the review.

## Execution Notes
Any special considerations for the review stage (e.g., large codebase may need batched sub-reviewers).
```

**Adapting sub-reviewers to the project:**
- For small projects: combine related sub-reviewers (e.g., merge Style and Code Quality)
- For projects without derived interfaces: omit Sub-Reviewer 9
- For projects in a single language: focus tools on that language
- Respect the user's priority ordering from the interview

### Step 3: Write Plan.md and Commit

Write the drafted plan to `./claude-reviews/$0/Plan.md`. Commit and push:

```bash
git add ./claude-reviews/$0/Plan.md
git commit -m "claude-review(plan): draft plan [session #$0]"
git push
```

### Step 4: Present the Plan to the User

Present the full plan to the user as text. Then use the `AskUserQuestion` tool to collect their decision:

```
AskUserQuestion({
  questions: [{
    question: "How would you like to proceed with this review plan?",
    header: "Plan Review",
    options: [
      { label: "Approve", description: "Plan looks good -- proceed to the review" },
      { label: "Request edits", description: "Adjust sub-reviewers, scope, or other sections" },
      { label: "Need more tools", description: "Escalate to interview or update-tooling for additional tools" }
    ],
    multiSelect: false
  }]
})
```

The user can also select "Other" to provide free-text feedback.

### Step 5: Handle Feedback

Based on the user's `AskUserQuestion` response:

**"Approve"** -- Proceed. The orchestrator advances to `review` by default.

**"Request edits"** (or "Other" with edit instructions):
- Edit `./claude-reviews/$0/Plan.md` in place
- Commit and push:
  ```bash
  git add ./claude-reviews/$0/Plan.md
  git commit -m "claude-review(plan): revise plan -- <brief summary> [session #$0]"
  git push
  ```
- Present the updated plan and return to Step 4 (re-invoke `AskUserQuestion` for approval)

**"Need more tools"** (or "Other" requesting tools):
- Note what tools are needed
- Write the signal file:
  ```bash
  echo "interview" > ./claude-reviews/$0/.next-stage
  # or if tools are already approved but not installed:
  echo "update-tooling" > ./claude-reviews/$0/.next-stage
  ```

## Stage Transition Signal

**Rules:**
- Write exactly one stage name, nothing else
- Only write this file if you want a NON-DEFAULT transition
- If you do not write this file, the orchestrator advances to `review` (default)

**When to signal:**
- `interview` -- if the user wants to discuss more tools or change priorities
- `update-tooling` -- if the user approved new tools that need installing
- `plan` -- if you need a fresh pass (should be rare)
- Default (advance to review) is correct when the user approves the plan.

## Re-trigger Behavior

If re-triggered and `./claude-reviews/$0/Plan.md` already exists:

1. Read the existing Plan.md
2. Present it to the user, then use `AskUserQuestion` to ask how to proceed:
   ```
   AskUserQuestion({
     questions: [{
       question: "This plan already exists from a previous run. How would you like to proceed?",
       header: "Prior Plan",
       options: [
         { label: "Approve", description: "Plan looks good as-is -- proceed to the review" },
         { label: "Request edits", description: "Adjust sub-reviewers, scope, or other sections" },
         { label: "Need more tools", description: "Escalate to interview or update-tooling for additional tools" }
       ],
       multiSelect: false
     }]
   })
   ```
3. If edits requested: edit in place (git history serves as audit trail)
4. Commit, push, and return to Step 4 to re-invoke `AskUserQuestion` for approval
