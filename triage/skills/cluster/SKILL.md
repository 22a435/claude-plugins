---
name: cluster
description: Build the dependency/duplicate/design-decision graph and consolidate still-live items into a small set of well-scoped, loosely-coupled bundles. Invoke with /triage:cluster <session-number>.
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash, Agent, Write, Edit
---

# Cluster Phase

You are performing the **cluster** stage of an issue-triage workflow. This is the core of the triage: turn the still-live items into a **small-to-medium set of well-scoped issues**, where each one is a single, comprehensive "bite" the issue workflow can take to a single PR. Bundle aggressively but correctly: **strong coupling within a bundle, weak coupling across bundles.**

## Workflow Context

This skill is one stage of a multi-stage issue-triage workflow orchestrated by the `triage` CLI.

- **Branch:** `claude/triage/<session-number>` (created by the orchestrator during setup)
- **Work directory:** `./claude-triages/<session-number>/` -- each stage produces one document here
- **Document ownership:** You may READ any prior document. Only WRITE to your own output document inside `./claude-triages/$0/` (where `$0` is the session number passed as your argument). Never create files, directories, or write anywhere else under `./claude-triages/`. When re-triggered, APPEND new sections -- never delete or overwrite existing content. Mark in-place edits with `> [IN-PLACE EDIT during <stage> phase]: <reason>`.
- **Commits:** Format: `claude-triage(<stage>): <description> [session #<N>]`. Commit and push after completing the stage.
- **PR updates:** Post a summary to the PR thread (via `gh pr comment`) after completing the stage.
- **Subagent write boundary:** Subagents in this stage must NOT create, edit, or write any files under `./claude-triages/`. Only this parent session writes the output document. Include this constraint in every subagent prompt you compose.
- **No self-loop:** Do not use `/loop`, `ScheduleWakeup`, or recursive `claude` invocations to re-run this skill. For short waits, run the command synchronously with `Bash` (it blocks until completion); for long waits, use `Bash` with `run_in_background` and `Monitor`. If you cannot finish in one pass, commit your partial progress and write your own stage name to `.next-stage` -- the orchestrator re-enters the stage within its loop-safety limits. Never re-invoke yourself.
- **Read issues in full:** When you read a GitHub issue, read the *entire* thread -- the body **and every comment/reply** -- plus any linked issues, PRs, commits, or docs that look relevant. Critical scope and context often live in replies, not the original body; missing them causes under-scoped work. Treat the whole thread as the source of truth for what the issue actually asks.

## Context
- **Session number:** $0 (the triage session number passed as your argument)
- **Work directory:** `./claude-triages/$0/`
- **Input documents:** `./claude-triages/$0/Reconcile.md`, `./claude-triages/$0/Inventory.md`
- **Output document:** `./claude-triages/$0/Cluster.md`

## Bundling Philosophy

The point of triage is to **reduce** the issue set, not preserve it. Avoiding scope now just defers it into issue-creation creep, which is worse. So bundle boldly:

- **A good bundle is one comprehensive PR's worth of work.** Aim for ambitious, complete units -- a whole feature area, a whole refactor, a whole cleanup sweep -- not the smallest safe slice. "This is a lot of work" is not a reason to split a coherent unit; coherence is the test, not size.
- **Anchor each bundle on its design decision.** If several items depend on the same undecided question (which library, which schema, which architecture), they belong in the **same** bundle, with that decision at its head -- so the issue workflow resolves it **once** (during its research/interview) and all dependent work flows from it. A decision and its dependents must never be split across bundles.
- **Dependencies travel together.** If item B can't be built until item A's work exists (blocks/depends-on), put them in the same bundle unless A is genuinely large enough to be its own PR *and* B only needs A's finished interface (in which case record the cross-bundle dependency explicitly).
- **Across bundles: minimize coupling.** The end state should let someone run the issue workflow on several bundles **in parallel** with little risk of conflict. If two bundles would constantly touch the same files or share an unresolved decision, they are really one bundle.
- **Do NOT scope down a single requested feature into multiple issues.** The opposite failure of issue-creep is the one to avoid here.

## Instructions

### Step 1: Read reconcile + inventory

Read `Reconcile.md` and `Inventory.md`. Your raw material is the **still-live** set (plus UNCLEAR items, treated as still-live but flagged). The already-fixed and duplicate items are handled as closes/merges in the plan -- carry them forward, do not re-bundle them as work.

### Step 2: Build the relationship graph

For the still-live items, establish edges (use parallel sonnet subagents to read code/issue context where the relationship is non-obvious; remind them of the write boundary):
- **shares-design-decision** -- both hinge on the same undecided question
- **depends-on / blocks** -- one needs the other's work first
- **same-subsystem** -- both modify the same area/files
- **duplicate-ish** -- partial overlap not caught in reconcile

### Step 3: Partition into bundles

Partition the graph so that within-bundle coupling (shared decision, dependency, same subsystem) is strong and cross-bundle coupling is weak. For each bundle decide a clear, comprehensive scope. Target a **small-to-medium** number of bundles overall. Record any unavoidable cross-bundle dependency explicitly (bundle X depends on the interface from bundle Y).

### Step 4: Draft the consolidated issue for each bundle

For each bundle, draft the GitHub issue that will represent it -- written so the issue workflow can take it straight to a single PR:
- **Title** -- crisp, describes the whole bundle
- **Scope / what done looks like** -- the comprehensive unit of work, with each absorbed item as a checklist line
- **Decisions to resolve first** -- the design decision(s)/open questions this bundle hinges on, stated as questions for the issue workflow's research/interview to answer. (This is what lets bundles run in parallel.)
- **Absorbs** -- the issue numbers / TODO refs folded into this bundle (these get closed-as-absorbed during consolidate, with a pointer to the new issue)
- **Cross-bundle dependencies** -- "depends on bundle <id>", or "none"
- **Suggested labels**

### Step 5: Assemble the full triage plan

Write `./claude-triages/$0/Cluster.md` -- this is the complete proposed plan the interview stage will present for approval:

```
# Triage Plan: Session #<N>

## Summary
- **Open issues at start:** <count>
- **To close (already fixed):** <count>
- **To merge (duplicates):** <count> absorbed into <count> canonicals
- **Still-live items:** <count>  →  **consolidated into <count> bundles**
- **Net issue change:** <start> open  →  <end> open (target: fewer, each a single-PR bite)

## Closes (already fixed)
| Issue | Title | Evidence | Close comment |
|---|---|---|---|
| #<n> | <title> | <file:line / PR> | <one-liner> |

## Merges (duplicates)
| Absorbed | Into canonical | Why same |
|---|---|---|
| #<a> | #<n> | <reason> |

## New / Updated Bundles
### Bundle B<k>: <title>
- **Scope (one PR):**
  - [ ] <absorbed item 1 -- what to do>
  - [ ] <absorbed item 2 -- what to do>
- **Decisions to resolve first:** <design question(s), or "none -- well-specified">
- **Absorbs:** #<x>, #<y>, TODO <path:line>
- **Cross-bundle dependencies:** <depends on B<j> | none>
- **Suggested labels:** <labels>
- **Disposition of absorbed issues:** <create new issue and close absorbed with pointer | grow existing #<n> into the bundle>

(repeat per bundle)

## Parallelism Map
<Which bundles can be worked in parallel (no shared decision, no shared files) vs. which must be sequential. This is the payoff: the issue workflow can run these bundles concurrently.>

## Open Questions for the User
<Anything the interview stage must confirm: borderline closes, UNCLEAR items, aggressive merges, or bundles whose scope you are unsure the user will accept.>
```

Note for each bundle whether it should be a **new** issue (then absorbed issues are closed with a pointer) or whether an existing issue should be **grown** into the bundle (preferred when one absorbed issue is clearly the natural home -- this avoids needless close/create churn, mirroring the "append over create" discipline).

### Step 6: Commit, push, and comment

```bash
git add ./claude-triages/$0/Cluster.md
git commit -m "claude-triage(cluster): consolidate into <K> bundles [session #$0]"
git push
gh pr comment --body "**Cluster complete (session #$0):** proposed <A> closes, <B> merges, <K> consolidated bundles. Awaiting approval in interview before any GitHub changes."
```

## Stage Transition Signal

Write the target stage name to `./claude-triages/$0/.next-stage` for a non-default transition.

**When to signal:**
- `reconcile` -- if clustering reveals classifications need rework: `echo "reconcile" > ./claude-triages/$0/.next-stage`
- Default (advance to `interview`) is correct in most cases.

## Re-trigger Behavior

If re-triggered (e.g., the user changed the plan during interview), append a `## Revised Plan (triggered during <stage> phase)` section capturing the changes, and clearly mark which bundles changed. Do not silently overwrite the original plan; mark in-place edits.
