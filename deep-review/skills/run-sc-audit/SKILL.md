---
name: run-sc-audit
description: Execute sc-auditor smart contract security audit and collect results. Invoke with /deep-review:run-sc-audit <session-number>.
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash, Agent, Write, Edit, Skill, AskUserQuestion, WebSearch, WebFetch
---

# Run SC-Audit Phase

You are performing the **run-sc-audit** stage of a deep codebase review. Your job is to execute the sc-auditor smart contract security audit and collect its output into a summary document for the subsequent plan and review stages.

## Workflow Context

This skill is one stage of a deep review workflow orchestrated by the `deep-review` CLI. This stage only runs when sc-auditor has been configured by the preceding plan-sc-audit stage.

- **Branch:** `claude/review/<session-number>` (created by the orchestrator during setup)
- **Work directory:** `./claude-reviews/<session-number>/` -- each stage produces one document here
- **Document ownership:** You may READ any prior document. Only WRITE to your own output document inside `./claude-reviews/$0/` (where `$0` is the session number passed as your argument). Never create files, directories, or write anywhere else under `./claude-reviews/` except your output document. When re-triggered, APPEND new sections -- never delete or overwrite existing content. Mark in-place edits with `> [IN-PLACE EDIT during <stage> phase]: <reason>`.
- **Commits:** Format: `claude-review(<stage>): <description> [session #<N>]`. Commit and push after completing the stage.
- **PR updates:** Post a summary to the PR thread (via `gh pr comment`) after completing the stage.
- **No code edits:** This stage does NOT edit source code. It runs the audit tool and produces review documents.
- **Subagent write boundary:** Subagents in this stage must NOT create, edit, or write any files under `./claude-reviews/`. Only this parent session writes the output document.

## Context
- **Session number:** $0 (the review session number passed as your argument)
- **Work directory:** `./claude-reviews/$0/`
- **Input documents:** `./claude-reviews/$0/ScAuditPlan.md`, `./.sc-auditor.config.json`
- **Output document:** `./claude-reviews/$0/ScAuditResults.md`

## Instructions

### Step 1: Read ScAuditPlan.md

Read `./claude-reviews/$0/ScAuditPlan.md` to determine:
- The audit target directory
- Expected output locations
- Configuration parameters
- Which tools are available

### Step 2: Set SC_AUDITOR_CONFIG and Invoke sc-auditor

Ensure the `SC_AUDITOR_CONFIG` environment variable points to the config file so sc-auditor picks it up:

```bash
export SC_AUDITOR_CONFIG="$(git rev-parse --show-toplevel)/.sc-auditor.config.json"
```

Then run the sc-auditor security audit by invoking its skill command. Use the Skill tool:

```
Skill({ skill: "security-auditor", args: "<target-directory>" })
```

Where `<target-directory>` is the audit target from ScAuditPlan.md.

**Important notes:**
- sc-auditor runs as a full audit session with its own internal phases (setup, map, hunt, attack, verify, report)
- It has **user gates** after MAP (scope confirmation) and HUNT (hotspot selection) -- the user will be prompted directly
- The audit may take significant time depending on project size and mode
- sc-auditor writes checkpoints to `.sc-auditor-work/checkpoints/` for crash recovery

### Step 3: Collect Output

After sc-auditor completes, collect its output artifacts:

```bash
# Check for report output
ls -la ./claude-reviews/$0/sc-audit/ 2>/dev/null || echo "No report in expected location"

# Check for checkpoint files (fallback if report location differs)
ls -la .sc-auditor-work/checkpoints/ 2>/dev/null || echo "No checkpoints found"

# Check for PoC files
ls -la .sc-auditor-work/pocs/ 2>/dev/null || echo "No PoC files"

# Also check the default 'audits/' directory in case config wasn't picked up
ls -la ./audits/ 2>/dev/null || echo "No audits/ directory"
```

Read all available output:
- The audit report (search in `./claude-reviews/$0/sc-audit/`, `./audits/`, and `.sc-auditor-work/`)
- Checkpoint files for structured findings data
- PoC test files for proven vulnerabilities

### Step 4: Summarize Findings

Parse the sc-auditor output and categorize findings by their proof status:

- **Proved** -- Findings with executable proof (Foundry PoC, Echidna invariant break, Halmos counterexample)
- **Confirmed** -- Findings verified by both attack and skeptic agents (judge_confirmed)
- **Candidate** -- Plausible findings awaiting proof or with degraded confidence
- **Design Tradeoff** -- Documented behavior that creates attack surface but is accepted risk
- **Discarded** -- Findings invalidated by the Devil's Advocate protocol

### Step 5: Write ScAuditResults.md

Write `./claude-reviews/$0/ScAuditResults.md`:

```
# SC-Audit Results: Session #<N>

## Executive Summary
Brief overview of what sc-auditor found. Overall security assessment.

## Statistics
- **Total findings:** <N>
- **Proved:** <N> (with executable proof)
- **Confirmed:** <N> (verified by adversarial protocol)
- **Candidate:** <N> (plausible, unproven)
- **Design Tradeoff:** <N> (accepted risk)
- **Discarded:** <N> (invalidated)
- **Static analysis findings:** <N> (Slither + Aderyn, pre-filtered)
- **Hunt lanes executed:** <N>/6
- **Proof artifacts generated:** <N>

## Critical & High Severity Findings

For each critical or high finding:

### Finding: <title>
- **Severity:** CRITICAL / HIGH
- **Status:** proved / confirmed / candidate
- **Proof:** <proof type and path, or "none">
- **Affected files:** <list>
- **Description:** <what was found>
- **Attack scenario:** <how it could be exploited>
- **DA Verdict:** <sustained/escalated with score summary>
- **Solodit precedent:** <matching real-world exploits, if any>
- **Recommendation:** <suggested fix>

## Medium Severity Findings

Same format, can be more concise for each finding.

## Low / Informational Findings

Brief list with title, status, and one-line description.

## Design Tradeoffs

For each design tradeoff:
- **Title:** <what behavior>
- **Risk:** <what attack surface it creates>
- **Rationale:** <why it may be acceptable>
- **Recommendation:** <document or mitigate>

## Proof Artifacts

| Finding | Proof Type | File Path | Result |
|---------|-----------|-----------|--------|
| <title> | foundry_poc | .sc-auditor-work/pocs/<id>_poc.t.sol | PASS/FAIL |
| <title> | echidna | <path> | Invariant broken |
| ...     | ...       | ...       | ...    |

## Areas Most Affected
Which contracts/modules had the most findings. Helps prioritize remediation.

## Recommendations for Deep Review
How the plan and review stages should incorporate these findings:
- Which findings should be prioritized for remediation
- Which areas need additional (non-security) review attention
- Which design tradeoffs should be flagged for documentation review
- What sc-auditor did NOT cover (non-Solidity code, off-chain components, deployment scripts)
```

### Step 6: Commit, Push, and Comment

```bash
git add ./claude-reviews/$0/ScAuditResults.md
# Also add any sc-auditor output files that should be tracked
git add ./claude-reviews/$0/sc-audit/ 2>/dev/null || true
git commit -m "claude-review(run-sc-audit): sc-auditor analysis complete [session #$0]"
git push
```

Post summary to PR:
```bash
gh pr comment "claude/review/$0" --body "**SC-Audit Complete**

<executive summary>

**Findings:** <N> total (<N> proved, <N> confirmed, <N> candidate, <N> design tradeoff, <N> discarded)

Critical/High findings: <brief list of titles>

See \`claude-reviews/$0/ScAuditResults.md\` for full results."
```

## Stage Transition Signal

**Rules:**
- Write exactly one stage name, nothing else
- Only write this file if you want a NON-DEFAULT transition
- If you do not write this file, the orchestrator advances to `plan` (default)

**When to signal:**
- Default (advance to plan) is correct in all normal cases.

## Handling Partial Results

If sc-auditor fails or completes only partially:

1. Check `.sc-auditor-work/checkpoints/` for whatever phases completed
2. Summarize available results in ScAuditResults.md
3. Note which phases completed and which didn't in the summary
4. Add a section:

```
## Incomplete Audit
- **Phases completed:** <list>
- **Phase failed:** <which phase and error>
- **Available data:** <what we can still use>
- **Recommendation:** <whether to retry or proceed with partial results>
```

5. Proceed to plan stage -- partial sc-auditor results are still valuable

## Re-trigger Behavior

If re-triggered and `ScAuditResults.md` already exists:

1. Read existing ScAuditResults.md
2. Check if ScAuditPlan.md has been updated
3. Re-run sc-auditor if configuration changed
4. Append to ScAuditResults.md:

```
---

## Re-audit (triggered during <stage> phase)

### Reason
<why re-audit was needed>

### Updated Findings
<new or changed findings>

### Updated Statistics
<revised totals>
```
