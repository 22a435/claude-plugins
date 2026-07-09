---
name: verify
description: Verify remediations were applied correctly. Cross-references Remediation-Plan.md, Remediation.md, and actual code. Runs the repo's local CI script and records its state for the orchestrator's pre-ready gate. Invoke with /deep-review:verify <session-number>.
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash, Agent, Write, Edit
---

# Verification Phase

You are performing the **verify** stage of a deep codebase review. Your job is to confirm that all remediations documented in Remediation.md were actually applied correctly in the code, and that nothing from the Remediation-Plan.md was missed.

## Workflow Context

This skill is one stage of a multi-stage deep review workflow orchestrated by the `deep-review` CLI.

- **Branch:** `claude/review/<session-number>` (created by the orchestrator during setup)
- **Work directory:** `./claude-reviews/<session-number>/` -- each stage produces one document here
- **Document ownership:** You may READ any prior document. Only WRITE to `./claude-reviews/$0/Verify.md` for your output document. When re-triggered, APPEND new sections -- never delete or overwrite existing content. Mark in-place edits with `> [IN-PLACE EDIT during <stage> phase]: <reason>`.
- **Commits:** Format: `claude-review(<stage>): <description> [session #<N>]`. Commit and push after completing the stage.
- **PR updates:** Post a summary to the PR thread (via `gh pr comment`) after each stage.
- **No code edits:** This stage does NOT edit any source code. It only reads code to verify remediations and produces Verify.md.
- **No self-loop:** Do not use `/loop`, `ScheduleWakeup`, or recursive `claude` invocations to re-run this skill. For short waits, run the command synchronously with `Bash` (it blocks until completion); for long waits, use `Bash` with `run_in_background` and `Monitor`. If you cannot finish in one pass, commit your partial progress and write your own stage name to `.next-stage` -- the orchestrator re-enters the stage within its loop-safety limits. Never re-invoke yourself.
- **Deferral hierarchy (never silently drop, never over-file):** Pre-existing bugs are not grounds for dismissal -- leave the codebase in the best working order regardless of origin. When work surfaces that you will not finish in this PR, walk this hierarchy and stop at the first tier that fits: **(1) Fix it in this PR** -- the default, and hard; "complex", "tedious", "touches many files", or "would take a while" are NOT reasons to defer, only a genuine Create-Issue criterion is (a tradeoff the user must decide / architectural refactor / high blast radius / team discussion / breaking upgrade / benchmark-needed). **(2) Append to a follow-up already filed in this run** -- if a follow-up you filed (or will file) this run naturally covers it, add it there rather than opening a second issue. **(3) Append to an existing open backlog issue** -- before filing anything new, search the backlog (`gh issue list --state open --limit 200 --json number,title,labels,body`); if an open issue already covers the area, comment the new context onto it instead of creating a duplicate. **(4) File one new, bundled issue** -- only if no tier above fits; bundle every co-deferred finding from this run that shares a subsystem or design decision into the SAME issue (one well-scoped issue, never one-per-finding). Filing a follow-up is a commitment that the proper fix exceeds this PR's scope -- not a way to avoid work; never leave a deferred finding as a document-only note, and record which tier each deferral took and why.
- **Read issues in full:** When you read a GitHub issue, read the *entire* thread -- the body **and every comment/reply** -- plus any linked issues, PRs, commits, or docs that look relevant. Critical scope and context often live in replies, not the original body; missing them causes under-scoped work. Treat the whole thread as the source of truth for what the issue actually asks.

## Context
- **Session number:** $0 (the review session number passed as your argument)
- **Work directory:** `./claude-reviews/$0/`
- **Input documents:** `./claude-reviews/$0/Remediation-Plan.md`, `./claude-reviews/$0/Remediation.md` (primary), plus Review.md and sub-reviews for context
- **Output document:** `./claude-reviews/$0/Verify.md`
- **Control file (also owned by this stage):** `./claude-reviews/$0/.local-ci-state` -- local CI command + code-state hash, read by the orchestrator before marking the PR ready. Like `.next-stage`, this is a sanctioned exception to the one-document rule. Running the local CI script does not conflict with the "No code edits" rule -- it only executes checks.

## Instructions

### Step 1: Determine Verification Mode

Check whether `./claude-reviews/$0/Integration.md` exists:

- **If Integration.md does NOT exist** (or this is the first verify run): this is a **standard verification** -- check all remediations against the plan.
- **If Integration.md exists** (and Verify.md already exists from a prior run): this is a **post-integration verification** -- focus on whether the rebase undid any remediations.

### Step 2: Read Input Documents

Read in full:
1. `Remediation-Plan.md` -- the approved plan listing all remediations to apply
2. `Remediation.md` -- the remediation report documenting what was actually done

If post-integration mode, also read:
3. `Integration.md` -- details of the rebase, conflicts resolved, files affected

### Step 3: Standard Verification (no Integration.md)

For each remediation marked as "Complete" in Remediation.md:

1. **Read the affected files** listed in the remediation entry
2. **Verify the fix is present** -- confirm the described change actually exists in the code
3. **Cross-reference against the plan** -- confirm the fix matches what the plan specified
4. **Record the result:** PASS (fix verified in code) or FAIL (fix missing, incomplete, or different from plan)

Then check for **missed items**:

1. Compare the full list of "fix now" items in Remediation-Plan.md against what Remediation.md reports
2. Any item in the plan not accounted for in Remediation.md (neither completed nor documented as failed) is a **missed** item

Use parallel subagents to verify multiple remediations concurrently. Each agent:
- Reads the specific files for one remediation
- Checks the fix is present and correct
- Reports PASS/FAIL with evidence

### Step 4: Post-Integration Verification (Integration.md exists)

This mode runs after a rebase. Focus specifically on remediations that may have been affected:

1. **Identify affected files** -- from Integration.md's conflict list and `git diff` output
2. **Filter remediations** -- only check remediations that touched files affected by the rebase
3. **For each affected remediation:**
   - Read the current state of the file
   - Compare against what Remediation.md says was changed
   - Record: INTACT (fix survived rebase), UNDONE (fix was lost/corrupted), or PARTIAL (fix partially present)
4. **Remediations in unaffected files** can be marked SKIPPED (assumed intact)

### Step 5: Run Local CI

Target repos run GitHub Actions only after the PR is marked ready for review, so the repo's local CI script is the authoritative pre-merge check -- it must be green before this workflow completes.

**Discover the local CI script.** Look in this order:

1. Documentation: the repo's CLAUDE.md or README (look for a documented local CI / check / verify command)
2. `scripts/ci*` (e.g., `scripts/ci.sh`, `scripts/ci-local.sh`)
3. A `ci` target in the Makefile (`make ci`)
4. A `"ci"` script in package.json (`npm run ci`)
5. If none exist, read `.github/workflows/*.yml` to see what CI runs and run those steps manually -- but record `command=none` in the marker; never record a command that is not a real, repeatable single entry point in the repo.

Record exactly one single-line shell command (e.g., `./scripts/ci.sh`), or `none`.

**Skip rule (re-verification passes only):** before running the local CI script, compute the code-state hash (command in the marker block below) and compare it to the existing `./claude-reviews/$0/.local-ci-state`. If the file exists, `tree_hash` matches, and `status=green`, you may skip re-running the local CI script and record it as SKIPPED (code unchanged since last green run) in Verify.md. Never skip when the hash differs, the marker is missing, or the last status was not `green`.

**Run the local CI script in full** (unless validly skipped) and capture its output.

**On failure:** document the failure as a gap in Verify.md's "Local CI Failures" section (exact command, output tail, affected checks) and signal `remediation` -- fixing local CI failures is remediation work, including the case where the local CI script *itself* is broken (leave the codebase in the best working order regardless of origin). Deferring a local-CI failure follows the Deferral hierarchy like any other finding; if ALL local CI failures are deferred, write the marker with `status=deferred` so the orchestrator can warn the user that GitHub Actions may show red once the PR is ready.

**Write the local CI state marker.** Only this parent session writes it. Write it whenever the local CI outcome for the current tree is green, validly skipped, deferred, or "no script exists". Do NOT write or update it when you are routing a local CI failure to `remediation` -- leave the previous marker (or its absence) in place so the state stays stale until a genuinely green run.

```bash
# If `git status --porcelain` shows uncommitted changes outside ./claude-reviews/,
# a prior stage failed to commit its work -- commit those first, or the hash
# will not describe the code you actually verified.
TREE_HASH=$(git ls-tree -r HEAD | awk -F'\t' '$2 !~ /^claude-reviews\//' | sha256sum | awk '{print $1}')
cat > ./claude-reviews/$0/.local-ci-state << EOF
command=<single-line local CI command, or none>
tree_hash=${TREE_HASH}
status=<green | deferred | none>
timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
```

- `status=green` -- the local CI script ran against this tree and passed (or was validly skipped against an unchanged green tree)
- `status=deferred` -- the local CI script failed, but every failure was deferred to follow-up issues (rare; requires the same explicit rationale as any deferral)
- `status=none` -- the repo has no local CI script (`command=none`)

The orchestrator reads this marker just before marking the PR ready: if the code hash no longer matches (something changed the code after your last green run), it re-runs the recorded command itself and, if red, re-enters the workflow at `verify`. Getting this marker right is what keeps red runs off GitHub Actions.

### Step 6: Write Verify.md

Write `./claude-reviews/$0/Verify.md`:

```
# Verification Report: Session #<N>

## Summary
- **Mode:** Standard / Post-Integration
- **Remediations verified:** <N>/<M>
- **Passed:** <N>
- **Failed:** <N>
- **Missed (not attempted):** <N>
- **Undone by integration:** <N> (post-integration mode only)
- **Local CI:** <command> -- GREEN / FAIL / SKIPPED (code unchanged since last green run) / NONE (no script found)
- **Verdict:** ALL PASS / GAPS FOUND (ALL PASS requires local CI green, validly skipped, none, or deferred-with-rationale)

## Verification Results

### Remediation: <title>
- **Status:** PASS / FAIL / UNDONE / SKIPPED
- **Files checked:**
  - `path/to/file.ts` -- <what was verified, or what's missing>
- **Evidence:** <brief description of what was found in the code>
- **Plan reference:** <which item in Remediation-Plan.md this corresponds to>

### Remediation: <title>
...

## Missed Items
Items in Remediation-Plan.md not accounted for in Remediation.md:
- <plan item title> -- <files that should have been changed>
- ...
(Or: "None -- all plan items were addressed")

## Items Undone by Integration
(Post-integration mode only)
- <remediation title> -- <what was lost and in which file>
- ...

## Local CI Failures
For each failure, provide enough context for the remediation stage to investigate without re-running the checks:
- **Command:** <exact local CI command>
- **Error output:** <output tail>
- **Affected checks:** <which parts of CI failed>
- **Status:** TO-REMEDIATE | DEFERRED-ISSUE #<n> (with rationale for deferral)
(Or: "None -- local CI green / skipped / no script found")

## Recommendation
<"All remediations verified. Proceed to integration." or "Gaps found. Remediation should address the items listed above.">
```

### Step 7: Commit and Push

```bash
git add ./claude-reviews/$0/Verify.md ./claude-reviews/$0/.local-ci-state
git commit -m "claude-review(verify): verification complete [session #$0]"
git push
```

### Step 8: Comment on PR

```bash
gh pr comment "claude/review/$0" --body "**Verification Complete**

- Remediations verified: <N>/<M>
- Passed: <N>, Failed: <N>, Missed: <N>
- Verdict: <ALL PASS / GAPS FOUND>

<brief summary of any issues found>

See \`claude-reviews/$0/Verify.md\` for full details."
```

### Step 9: Signal Transition

- **If all remediations pass and local CI is green/skipped/none (or deferred with rationale):** do not write a signal file (default transition to `integrate`)
- **If gaps found** (failures, missed items, remediations undone by integration, or local CI failures): signal `remediation`
  ```bash
  echo "remediation" > ./claude-reviews/$0/.next-stage
  ```

## Stage Transition Signal

When running under the `deep-review` orchestrator, you can request a transition to a different stage by writing the target stage name to `./claude-reviews/$0/.next-stage`.

**Rules:**
- Write exactly one stage name, nothing else
- Only write this file if you want a NON-DEFAULT transition
- If you do not write this file, the orchestrator advances to `integrate` (default)

**When to signal:**
- `remediation` -- gaps were found (failed, missed, or undone remediations, or local CI failures). Remediation will read Verify.md to see what needs addressing:
  ```bash
  echo "remediation" > ./claude-reviews/$0/.next-stage
  ```
- Default (integrate) -- all remediations verified, proceed to integration.

## Re-trigger Behavior

If re-triggered and `Verify.md` already exists:

1. Read existing Verify.md to understand prior verification results
2. Determine the trigger context (post-remediation re-run or post-integration)
3. Re-verify items that previously failed, were missed, or were newly applied
4. Recompute the tree hash and apply the Step 5 skip rule against `.local-ci-state`: re-run the local CI script whenever the hash differs or the last status was not `green`, and update the marker after adjudicating the result
5. Append a new section:

```
---

## Re-verification (<date>)

### Trigger
<post-remediation fix / post-integration rebase>

### Results
- Previously failed, now: <PASS/FAIL>
- Previously missed, now: <PASS/FAIL>
- Undone by integration, now: <INTACT/STILL UNDONE>

### Updated Verdict
<ALL PASS / GAPS REMAIN>
```
