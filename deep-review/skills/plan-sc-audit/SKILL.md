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
- **Subagent write boundary:** Subagents in this stage must NOT create, edit, or write any files under `./claude-reviews/`. Only this parent session writes the output document.
- **No self-loop:** Do not use `/loop`, `ScheduleWakeup`, or recursive `claude` invocations to re-run this skill. For short waits, run the command synchronously with `Bash` (it blocks until completion); for long waits, use `Bash` with `run_in_background` and `Monitor`. If you cannot finish in one pass, commit your partial progress and write your own stage name to `.next-stage` -- the orchestrator re-enters the stage within its loop-safety limits. Never re-invoke yourself.
- **Deferral hierarchy (never silently drop, never over-file):** Pre-existing bugs are not grounds for dismissal -- leave the codebase in the best working order regardless of origin. When work surfaces that you will not finish in this PR, walk this hierarchy and stop at the first tier that fits: **(1) Fix it in this PR** -- the default, and hard; "complex", "tedious", "touches many files", or "would take a while" are NOT reasons to defer, only a genuine Create-Issue criterion is (a tradeoff the user must decide / architectural refactor / high blast radius / team discussion / breaking upgrade / benchmark-needed). **(2) Append to a follow-up already filed in this run** -- if a follow-up you filed (or will file) this run naturally covers it, add it there rather than opening a second issue. **(3) Append to an existing open backlog issue** -- before filing anything new, search the backlog (`gh issue list --state open --limit 200 --json number,title,labels,body`); if an open issue already covers the area, comment the new context onto it instead of creating a duplicate. **(4) File one new, bundled issue** -- only if no tier above fits; bundle every co-deferred finding from this run that shares a subsystem or design decision into the SAME issue (one well-scoped issue, never one-per-finding). Filing a follow-up is a commitment that the proper fix exceeds this PR's scope -- not a way to avoid work; never leave a deferred finding as a document-only note, and record which tier each deferral took and why.
- **Read issues in full:** When you read a GitHub issue, read the *entire* thread -- the body **and every comment/reply** -- plus any linked issues, PRs, commits, or docs that look relevant. Critical scope and context often live in replies, not the original body; missing them causes under-scoped work. Treat the whole thread as the source of truth for what the issue actually asks.

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

Only run additional Glob/Grep queries if Context.md is missing specific data needed for configuration thresholds (e.g., exact contract count for max_functions_per_category).

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

**Proof tools** (`proof_tools`, flat booleans): Enable each tool that UpdateTooling.md confirms is installed:
- `foundry_enabled`: true if `forge` is available
- `echidna_enabled`: true if `echidna` is available
- `medusa_enabled`: true if `medusa` is available
- `halmos_enabled`: true if `halmos` is available
- `ityfuzz_enabled`: true if `ityfuzz` is available

**Static analysis** (`static_analysis`, flat booleans):
- `slither_enabled`: true if `slither` is available
- `aderyn_enabled`: true if `aderyn` is available

**llm_reasoning.max_functions_per_category:** Scale based on project size:
- Small (<20 contracts): 25
- Medium (20-100 contracts): 50
- Large (>100 contracts): 100

**llm_reasoning.context_window_budget:** 0.7 default. Increase to 0.85 for smaller focused audits (<20 contracts).

**max_findings_per_category** (top-level): 10 for default, 20 for deep mode.

**max_deep_dives** (top-level): 5 for default, 10 for deep mode.

**report_output_dir:** `claude-reviews/$0/sc-audit`

**workflow.require_witness_for_high / verify.demote_unproven_medium_high:** In benchmark mode the loader already defaults demotion to true. Otherwise, if unclear whether the user wants strict proof requirements, ask:
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

Write the sc-auditor configuration to `./.sc-auditor.config.json` in the repo root.

The key names below are sc-auditor 2.0.0's canonical schema (mirroring its `config.example.json`). The loader silently ignores unrecognized keys -- a misspelled or misplaced key does not error, it silently falls back to a lower default -- so copy these names exactly and run the validation in Step 6 afterward.

```bash
cat > .sc-auditor.config.json << 'CONFIG_EOF'
{
  "default_severity": ["CRITICAL", "HIGH", "MEDIUM"],
  "default_quality_score": 2,
  "report_output_dir": "claude-reviews/<session>/sc-audit",
  "max_findings_per_category": <N>,
  "max_deep_dives": <N>,

  "static_analysis": {
    "slither_enabled": <true/false>,
    "aderyn_enabled": <true/false>
  },

  "llm_reasoning": {
    "max_functions_per_category": <N>,
    "context_window_budget": <0.7 or 0.85>
  },

  "workflow": {
    "mode": "<default|deep|benchmark>",
    "parallel_hunters": true,
    "autonomous": false,
    "require_witness_for_high": <true/false>
  },

  "proof_tools": {
    "foundry_enabled": <true/false>,
    "echidna_enabled": <true/false>,
    "medusa_enabled": <true/false>,
    "halmos_enabled": <true/false>,
    "ityfuzz_enabled": <true/false>
  },

  "verify": {
    "demote_unproven_medium_high": <true/false>
  }
}
CONFIG_EOF
```

Replace all placeholders with actual values determined in Step 3. Note `report_output_dir` must be a relative path without leading `/` or `..` segments -- the loader rejects absolute paths.

### Step 6: Validate the Config with sc-auditor's Own Loader

Run sc-auditor's compiled config loader against the file you just wrote and confirm the resolved values match what you intended. This catches wrong key names outright: the loader silently ignores unrecognized keys, so a typo shows up only as a resolved value falling back to its default.

```bash
SC_AUDITOR_DIR="$(npm root -g)/sc-auditor"
SC_AUDITOR_CONFIG="$(git rev-parse --show-toplevel)/.sc-auditor.config.json" \
  node -e "import('${SC_AUDITOR_DIR}/dist/config/loader.js').then(m => console.log(JSON.stringify(m.loadConfig(), null, 2)))"
```

If sc-auditor is not in the global npm root (e.g. it was installed some other way), find its install path in UpdateTooling.md or via `command -v sc-auditor` and point at that package's `dist/config/loader.js` instead. If you cannot locate a compiled loader at all, fall back to diffing your file key-by-key against the schema in Step 5 and note in ScAuditPlan.md that loader validation was skipped.

Then compare the loader's resolved output against the values you chose in Step 3:

- If the loader **throws** (`ERROR: CONFIG_VALIDATION - ...`), a value is out of range or mistyped -- fix the config and re-run.
- If any resolved value **differs from what you wrote** (e.g. you wrote 100 for `max_functions_per_category` but the output shows 50), the key name or nesting is wrong -- fix it to match the Step 5 schema exactly and re-run.
- Only proceed once every intended value appears verbatim in the resolved output.

### Step 7: Write ScAuditPlan.md

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
Loader validation: <passed | skipped (reason)>
```

### Step 8: Commit, Push, and Comment

```bash
git add ./claude-reviews/$0/ScAuditPlan.md ./.sc-auditor.config.json
git commit -m "claude-review(plan-sc-audit): configure sc-auditor [session #$0]"
git push
```

Post summary to PR:
```bash
gh pr comment --body "**SC-Audit Plan:** Configured sc-auditor in <mode> mode. Target: <dir> (<N> contracts). Tools: <enabled tools list>. See ScAuditPlan.md for details."
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
