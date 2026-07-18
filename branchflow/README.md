# branchflow

Release-train orchestrator for the 22a435 workflows. It manages the branches the
feature plugins (`issue-workflow`, `deep-review`, `triage`) target, and turns a stack
of merged work into a tagged release — **merge-only and PR-driven**, so it never
force-pushes and coexists with strict branch protection.

It handles two shapes, chosen entirely by your `.claude-workflows.json`:

- **Single line** — one `develop`/staging branch; the version bump is decided at
  release time. No cascade. The simplest thing that keeps `main` releasable.
- **Semver trains** — separate `major` / `minor` / `patch` accumulator branches, so
  you can ship the smallest coherent release on demand without dragging in half-done
  larger work. This is the powerful (and more involved) mode; the rest of this README
  focuses on it, and calls out where single-line differs.

## The model

```
        feature branches (claude/*)          cut from an accumulator, PR back into it
             │  │  │
             ▼  ▼  ▼
   patch ───────────────┐
             │ cascade ↑ │  up-flow:  a change in a lower line is forward-merged
   minor ───────────────┤             up into every higher line
             │ cascade ↑ │
   major ───────────────┘
             │ promote (bump + tag)
             ▼
   main  ◀───────────────    down-flow (reconcile): when main moves, every
         ─────────────────▶  accumulator merges it back in
```

Everything rests on one **invariant**:

> **`major ⊇ minor ⊇ patch`** (in content) at all times.

Two flows maintain it, and both are just merges via PRs:

- **cascade (up):** a lower line's change is forward-merged up the chain. Keeps higher
  lines ⊇ lower lines.
- **reconcile (down):** when `main` moves (a release, or a hotfix), every accumulator
  merges `main` back in — lower lines end up with an empty diff-vs-main ("cleared"),
  higher lines get the new baseline while keeping their unshipped work.

The invariant is the safety condition: promoting a line puts its content (which, by
the invariant, already contains every lower line's) into `main`, so resetting the
lower lines afterward loses nothing. `branchflow promote` **refuses** if the invariant
is violated.

### Two rules that keep it conflict-free

1. **Merge with merge-commits, never squash.** Squash rewrites SHAs and makes every
   later cascade/reconcile hit phantom conflicts. (Squash is fine for a standalone
   feature PR, or the final PR of a stack.)
2. **Bump the version only at promote, never in accumulators or feature branches.**
   Then no merge ever touches the version field. `branchflow` follows this itself.

## Install

```bash
claude plugin marketplace add 22a435/claude-plugins
claude plugin install 22a435-workflows@branchflow --scope user
```

Set up the CLI command (symlink or alias to `branchflow/bin/branchflow`), e.g.:

```bash
ln -s ~/.claude/plugins/22a435-workflows/branchflow/bin/branchflow ~/.local/bin/branchflow
```

Needs `git`, `gh` (authenticated), and `jq`. `claude` is **optional** — only conflict
resolution and changelog drafting use it, so `branchflow` also runs in CI (see the
eager Action) with just `git`/`gh`/`jq`.

## Configuration

`branchflow` reads the same `.claude-workflows.json` as the feature plugins, plus an
optional `release` block. All keys optional.

| Key | Meaning | Default |
|-----|---------|---------|
| `releaseBranch` | Released / tagged line | `main` |
| `targetBranch` | Single develop/staging line (single-line mode) | — |
| `updateBranches` | `{major,minor,patch}` accumulator branch names (trains mode) | — |
| `protectedBranches` | Branches the push-guard hook blocks | `main master production` |
| `release.versionFrom` | `tag` or a version file | `tag` |
| `release.versionFile` | File `promote` bumps (`package.json`, …); `none` = tag-only | `none` |
| `release.tagPrefix` | Release tag prefix | `v` |
| `release.changelogFile` | Changelog `promote` maintains | — |

> The file must be **strict JSON** (no `//` comments — those below are illustrative).

### Example A — single `develop` line, versioned from tags

The whole team merges into `develop`; you release when it's ready and pick the bump
then. No cascade, minimal machinery.

```json
{
  "targetBranch": "develop",
  "protectedBranches": ["main", "develop"],
  "release": { "versionFrom": "tag", "tagPrefix": "v" }
}
```

```bash
branchflow init                 # ensure develop exists
branchflow promote minor        # cut a minor-bump release PR: develop -> main
branchflow reconcile            # after it merges: tag + merge main back into develop
```

### Example B — three semver trains, canonical package.json version

Ship a patch without pulling in in-flight minor/major work.

```json
{
  "releaseBranch": "main",
  "branchPrefix": "claude",
  "defaultBump": "patch",
  "updateBranches": { "major": "major", "minor": "minor", "patch": "patch" },
  "protectedBranches": ["main", "major", "minor", "patch"],
  "release": {
    "versionFrom": "tag",
    "versionFile": "package.json",
    "tagPrefix": "v",
    "changelogFile": "CHANGELOG.md"
  }
}
```

### Example C — namespaced release lines + tag-only (no version file)

For repos that don't keep a canonical version file (versioned purely by git tags).

```json
{
  "releaseBranch": "release",
  "updateBranches": {
    "major": "trains/major",
    "minor": "trains/minor",
    "patch": "trains/patch"
  },
  "defaultBump": "patch",
  "protectedBranches": ["release", "trains/major", "trains/minor", "trains/patch"],
  "release": { "versionFrom": "tag", "versionFile": "none", "tagPrefix": "v" }
}
```

## Commands

| Command | What it does |
|---------|--------------|
| `branchflow init` | Interactive turnkey setup (smart, repo-detected defaults; `--yes` accepts all). Scaffolds `.claude-workflows.json` if missing, commits it to the release branch, creates the accumulator branches, offers a baseline tag, and — with repo admin — sets merge-commit-only + branch protection via the GitHub API. Idempotent. |
| `branchflow status [--check]` | Per line: pending↑ vs main, behind↓, next version; the invariant matrix. `--check` exits non-zero on violation (CI gate). |
| `branchflow cascade [<level>]` | Forward-merge lower lines UP via PRs. `--auto-merge` lands clean ones; conflicts get a Claude-resolved PR. No `<level>` cascades all. |
| `branchflow promote <level\|bump>` | Open a version-bump PR from a line into `main`. Refuses on a violated invariant unless `--force`. `--auto-merge` lands it (when the env allows), else waits for manual merge. |
| `branchflow reconcile [--version <v>]` | Tag a just-merged release, then merge `main` DOWN into every accumulator via PRs. |

Global flags: `--yes` (skip confirmations), `--auto-merge`, `--force`, `--repo-dir <path>`.

## End-to-end walkthroughs (trains mode)

### One-time setup

```bash
branchflow init      # interactive; press enter to accept each detected default
```

`init` walks you through it: it detects your default branch and version file,
proposes a `.claude-workflows.json`, commits it to the release branch, creates
the `major`/`minor`/`patch` branches, offers a baseline tag, and (if you have
repo admin) sets the merge method to **merge-commit only** and requires PRs on
all the managed branches via the GitHub API. Run `branchflow init --yes` to
accept every default non-interactively. It's idempotent — safe to re-run.

If you'd rather configure by hand, write `.claude-workflows.json` yourself (see
Configuration above) and `init` will skip the scaffold and just create branches
+ apply settings. The one setting that matters most: **disable squash-merge** on
these branches — squash rewrites commit SHAs and breaks the cascade.

### A single patch fix

```bash
work-issue 101 --bump patch     # feature plugin: claude/101 cut from patch, PR into patch
# review + merge that PR (merge commit) into patch
branchflow cascade patch        # forward-merge the fix up into minor + major (PRs)
# merge those PRs
branchflow status               # invariant ✓
```

### A multi-PR feature (stacking) landing as a minor

Keep the accumulator clean while the feature is incomplete — stack the PRs, land the
whole stack into `minor` only when it's done:

```bash
work-issue 110 --bump minor                     # PR A: cut from minor,  base = minor
work-issue 111 --onto claude/110 --bump minor   # PR B: cut from A,       base = A
work-issue 112 --onto claude/111 --bump minor   # PR C: cut from B,       base = B
# review the stack; merge bottom-up (A, then B, then C -- merge commits, not squash).
branchflow cascade minor        # push the completed feature up into major
```

### Cutting the release

```bash
branchflow status               # confirm the invariant holds first
branchflow promote minor        # opens "Release v1.5.0" PR: minor -> main (+ bump/changelog)
# review + merge the release PR into main (merge commit)
branchflow reconcile            # tags v1.5.0, merges main back down into all lines
```

At this point `main` is `v1.5.0`, `patch`/`minor` are clean (empty diff vs main), and
`major` keeps its unshipped work on the new baseline.

## Manual vs eager (both supported)

- **Manual (default, always safe):** you run `status → cascade → promote → reconcile`.
  Nothing auto-merges unless you pass `--auto-merge`; `promote` hard-gates on the
  invariant so a release can't silently drop work.
- **Eager (opt-in):** copy `templates/branchflow.yml` into `.github/workflows/`. On a
  push to an accumulator it cascades up; on a push to `main` it tags + reconciles —
  all with auto-merge, so the invariant stays true continuously. Clean merges land on
  their own; conflicting ones open a PR for a human (no Claude in CI).

## Safety properties

- **Never force-pushes** an accumulator or the release branch — every update is a PR.
  Works with strict branch protection; the shared push-guard hook blocks direct pushes
  to protected branches as a backstop.
- **Invariant-gated promotion** — `promote` refuses (exit 3) if a lower line isn't
  fully cascaded up, unless you `--force` (with confirmation).
- **Version only at promote** — accumulators/feature branches never touch the version,
  so reconciles don't conflict on it.
- **Out of scope:** it does not decide *what* a change's magnitude is (that's the
  feature plugin's `--bump`/label), and it does not manage long-term maintenance
  branches for already-released majors.

## How it fits the other plugins

`branchflow` and the feature plugins share one `.claude-workflows.json`: the feature
plugins *route* PRs into the right line (`work-issue 42 --bump minor`, `--onto`), and
`branchflow` *cascades and releases* those lines. See the repo root `README.md` and
`CLAUDE.md` for the shared branching model.
