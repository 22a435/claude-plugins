---
name: plan-sc-audit
description: Configure sc-auditor parameters for smart contract security analysis based on project context and user preferences. Invoke with /deep-review:plan-sc-audit <session-number>.
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash, Agent, Write, Edit, AskUserQuestion
---

# Plan SC-Audit Phase

You are performing the **plan-sc-audit** stage of a deep codebase review. Your job is to configure the sc-auditor smart contract security tool based on the project's structure, complexity, installed tools, and user preferences.

## Workflow Context

This skill is one stage of a deep review workflow orchestrated by the `deep-review` CLI. This stage only runs when the codebase contains Solidity contracts and the user approved sc-auditor during the interview stage.

- **Branch:** `claude/review/<session-number>` (created by the orchestrator during setup)
- **Work directory:** `./claude-reviews/<session-number>/` -- each stage produces one document here
- **Document ownership:** You may READ any prior document. Only WRITE to your own output document inside `./claude-reviews/$0/` (where `$0` is the session number passed as your argument) and to `./.sc-auditor.config.json` in the repo root. Never create files, directories, or write anywhere else under `./claude-reviews/` except your output document. When re-triggered, APPEND new sections -- never delete or overwrite existing content. Mark in-place edits with `> [IN-PLACE EDIT during <stage> phase]: <reason>`.
- **Commits:** Format: `claude-review(<stage>): <description> [session #<N>]`. Commit and push after completing the stage.
- **PR updates:** Post a summary to the PR thread (via `gh pr comment`) after completing the stage.
- **Subagent cost optimization:** Downgrade information-gathering agents to `model: "sonnet"`. Keep the parent session's model for configuration decisions and judgment.
- **Subagent write boundary:** Subagents in this stage must NOT create, edit, or write any files under `./claude-reviews/`. Only this parent session writes the output document.

## Context
- **Session number:** $0 (the review session number passed as your argument)
- **Work directory:** `./claude-reviews/$0/`
- **Input documents:** `./claude-reviews/$0/Context.md`, `./claude-reviews/$0/Interview.md`, `./claude-reviews/$0/UpdateTooling.md`
- **Output documents:** `./claude-reviews/$0/ScAuditPlan.md`, `./.sc-auditor.config.json` (repo root)

## Instructions

### Step 1: Read Input Documents

Read `Context.md`, `Interview.md`, and `UpdateTooling.md` in full. Extract:
- Solidity file count and directory structure
- Frameworks detected (Foundry, Hardhat, Truffle)
- Whether cross-contract interactions exist
- sc-auditor approval status from Interview.md
- Which sc-auditor subtools were installed/detected from UpdateTooling.md
- User's review priorities and security concerns
- Solodit API key availability

### Step 2: Analyze Project Complexity

Extract project complexity data from Context.md's "Solidity / Smart Contract Context" section, which already contains:
- Contract count (number of .sol files)
- Framework (Foundry/Hardhat/Truffle)
- Whether cross-contract interactions exist
- DeFi patterns detected (ERC20, ERC721, ERC4626, oracles, AMMs, flash loans)
- Proxy/upgradeable patterns

Only run additional Glob/Grep queries if Context.md is missing specific data needed for configuration thresholds (e.g., exact contract count for functions_per_category).

### Step 3: Determine Configuration

Based on the analysis, decide each configuration parameter:

**Workflow mode:**
- `"default"` -- Standard projects, straightforward contract logic
- `"deep"` -- Projects with cross-contract interactions, DeFi protocols, complex token mechanics, proxy patterns
- `"benchmark"` -- Competitive audit preparation (strict proof requirements)

If the choice between `default` and `deep` is unclear, ask the user:
```
AskUserQuestion({
  questions: [{
    question: "sc-auditor supports different analysis depth modes. Based on the project complexity, which mode would you prefer?",
    header: "Audit Mode",
    options: [
      { label: "Default", description: "Standard analysis -- good for most projects" },
      { label: "Deep", description: "Extended analysis with adversarial deep lane -- recommended for DeFi/cross-contract projects" },
      { label: "Benchmark", description: "Strict mode -- unproven findings auto-downgraded. For competitive audit prep." }
    ],
    multiSelect: false
  }]
})
```

**Severity filter:**
- Default: `["CRITICAL", "HIGH", "MEDIUM"]`
- If user requested thoroughness in interview or project is small: add `"LOW"`

**Parallel hunters:** `true` (parallel hunt lanes are generally beneficial)

**Proof tools:** Enable each tool that UpdateTooling.md confirms is installed:
- `foundry.enabled`: true if `forge` is available
- `echidna.enabled`: true if `echidna` is available
- `medusa.enabled`: true if `medusa` is available
- `halmos.enabled`: true if `halmos` is available
- `ityfuzz.enabled`: true if `ityfuzz` is available

**Static analysis:**
- `slither.enabled`: true if `slither` is available
- `aderyn.enabled`: true if `aderyn` is available

**functions_per_category:** Scale based on project size:
- Small (<20 contracts): 25
- Medium (20-100 contracts): 50
- Large (>100 contracts): 100

**context_window_budget:** 0.7 default. Increase to 0.85 for smaller focused audits (<20 contracts).

**max_per_category:** 10 for default, 20 for deep mode.

**max_analyses:** 5 for default, 10 for deep mode.

**report_output_dir:** `./claude-reviews/$0/sc-audit`

**witness_required / demote_unproven:** If unclear whether the user wants strict proof requirements, ask:
```
AskUserQuestion({
  questions: [{
    question: "Should sc-auditor require proof (fuzzing/symbolic execution) for high-severity findings? Unproven findings would be downgraded.",
    header: "Proof Rigor",
    options: [
      { label: "No (Recommended)", description: "Report all findings regardless of proof status -- proof is supplementary" },
      { label: "Yes", description: "Require proof for critical/high findings -- unproven ones get downgraded" }
    ],
    multiSelect: false
  }]
})
```

### Step 4: Determine Audit Target

Identify the Solidity source directory from Context.md's Architecture section, which already maps the directory structure. Common Solidity source locations are `src/`, `contracts/`, or `src/contracts/`.

The target should be the source directory containing the contracts to audit, excluding test files and external libraries (node_modules, lib/ for Foundry dependencies). If Context.md doesn't clearly indicate the source directory, use Glob to find it:

```
Glob({ pattern: "**/*.sol", path: "." })
```

### Step 5: Write .sc-auditor.config.json

Write the sc-auditor configuration to `./.sc-auditor.config.json` in the repo root:

```bash
cat > .sc-auditor.config.json << 'CONFIG_EOF'
{
  "default_severity": ["CRITICAL", "HIGH", "MEDIUM"],
  "quality_score": 2,
  "report_output_dir": "./claude-reviews/<session>/sc-audit",

  "static_analysis": {
    "slither": { "enabled": <true/false> },
    "aderyn": { "enabled": <true/false> }
  },

  "llm_reasoning": {
    "functions_per_category": <N>,
    "context_window_budget": <0.7 or 0.85>
  },

  "workflow": {
    "mode": "<default|deep|benchmark>",
    "parallel_hunters": true,
    "autonomous_mode": false,
    "witness_required": <true/false>
  },

  "proof_tools": {
    "foundry": { "enabled": <true/false> },
    "echidna": { "enabled": <true/false> },
    "medusa": { "enabled": <true/false> },
    "halmos": { "enabled": <true/false> },
    "ityfuzz": { "enabled": <true/false> }
  },

  "verify": {
    "demote_unproven": <true/false>
  },

  "findings": {
    "max_per_category": <N>
  },

  "deep_dive": {
    "max_analyses": <N>
  }
}
CONFIG_EOF
```

Replace all placeholders with actual values determined in Step 3.

### Step 6: Write ScAuditPlan.md

Write `./claude-reviews/$0/ScAuditPlan.md`:

```
# SC-Audit Plan: Session #<N>

## Overview
Smart contract security audit using sc-auditor. This stage configures and prepares
the audit; the next stage (run-sc-audit) executes it.

## Audit Target
- **Directory:** <target directory>
- **Contract count:** <N> Solidity files
- **Frameworks:** <Foundry/Hardhat/Truffle>
- **Cross-contract interactions:** yes/no
- **DeFi patterns detected:** <list or none>
- **Proxy/upgradeable contracts:** yes/no

## Configuration
- **Mode:** <default/deep/benchmark> -- <rationale>
- **Severity filter:** <list>
- **Parallel hunters:** enabled
- **Proof tools:** <list of enabled tools>
- **Static analysis:** <list of enabled tools>
- **Functions per category:** <N>
- **Max findings per category:** <N>
- **Max deep-dive analyses:** <N>
- **Witness required:** <yes/no>
- **Demote unproven:** <yes/no>

## Available Subtools
| Tool | Status | Purpose |
|------|--------|---------|
| Slither | installed/not available | Static analysis |
| Aderyn | installed/not available | Static analysis |
| Foundry | installed/not available | PoC generation |
| Echidna | installed/not available | Invariant fuzzing |
| Medusa | installed/not available | Fuzz testing |
| Halmos | installed/not available | Symbolic execution |

## Solodit API
- **Available:** yes/no
- **Purpose:** Cross-reference findings against real-world confirmed exploits

## Expected Output
- Report directory: ./claude-reviews/<N>/sc-audit/
- Checkpoint directory: .sc-auditor-work/checkpoints/
- PoC files: .sc-auditor-work/pocs/ (if applicable)

## User Interaction Note
sc-auditor has its own user gates after the MAP phase (scope confirmation) and
HUNT phase (hotspot selection). You will be prompted during the run-sc-audit stage.

## Config File
Written to: ./.sc-auditor.config.json
```

### Step 7: Commit, Push, and Comment

```bash
git add ./claude-reviews/$0/ScAuditPlan.md ./.sc-auditor.config.json
git commit -m "claude-review(plan-sc-audit): configure sc-auditor [session #$0]"
git push
```

Post summary to PR:
```bash
gh pr comment "claude/review/$0" --body "**SC-Audit Plan:** Configured sc-auditor in <mode> mode. Target: <dir> (<N> contracts). Tools: <enabled tools list>. See ScAuditPlan.md for details."
```

## Stage Transition Signal

**Rules:**
- Write exactly one stage name, nothing else
- Only write this file if you want a NON-DEFAULT transition
- If you do not write this file, the orchestrator advances to `run-sc-audit` (default)

**When to signal:**
- Default (advance to run-sc-audit) is correct in all normal cases.
- `interview` -- if the user changes their mind about sc-auditor or wants to adjust priorities:
  ```bash
  echo "interview" > ./claude-reviews/$0/.next-stage
  ```
- `plan` -- if the user decides to skip sc-auditor and proceed directly to the main review plan:
  ```bash
  echo "plan" > ./claude-reviews/$0/.next-stage
  ```

## Re-trigger Behavior

If re-triggered and `ScAuditPlan.md` already exists:
1. Read existing ScAuditPlan.md and .sc-auditor.config.json
2. Check for changes in Interview.md or UpdateTooling.md
3. Update .sc-auditor.config.json if tools changed
4. Append to ScAuditPlan.md:

```
---

## Configuration Update (triggered during <stage> phase)

### Reason
<what changed>

### Updated Parameters
<list changes>
```
