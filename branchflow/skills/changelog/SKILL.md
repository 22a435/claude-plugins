---
name: changelog
description: Prepare a branchflow release commit -- apply the version bump to the configured version file (if any) and draft the changelog from the commit range. Invoke with /branchflow:changelog <new-version> <level> <line>.
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash, Edit, Write
---

# Prepare Release Commit (branchflow)

You are preparing the release commit for the **branchflow** promote step. You are
checked out on the release branch (`branchflow/release/<new-version>`), which was cut
from the line being promoted. Apply the version bump and draft the changelog, then
**stage** your edits and stop — the orchestrator commits, pushes, and opens the
release PR into the release branch.

## Arguments
- `$1` = **new version** (e.g. `1.5.0`, no tag prefix).
- `$2` = **level**: `major` | `minor` | `patch`.
- `$3` = **line**: the accumulator branch being promoted (e.g. `minor`).

## Step 1: Read the release config

Read `.claude-workflows.json` at the repo root:
```bash
jq '{releaseBranch, release}' .claude-workflows.json
```
You need `release.versionFile` (default `"none"`), `release.changelogFile` (optional),
`release.tagPrefix` (default `"v"`), and `releaseBranch` (default `"main"`).

## Step 2: Apply the version bump (only if a version file is configured)

If `release.versionFile` is `"none"`, absent, or the file does not exist, **skip this
step** — this repo versions from git tags only, and the orchestrator will tag on
reconcile.

Otherwise set the version in that file to `$1`, using the right method for its format:
- `package.json`: `jq '.version = $v' --arg v "$1"` (preserve formatting where practical) or a targeted edit of the `"version"` field.
- `Cargo.toml` / `pyproject.toml`: edit the `version = "..."` line under the package/project table.
- `*.gemspec`, `setup.py`, `version.go`, `VERSION`, etc.: edit the single version literal.
- Anything else: locate the current version string (it will match the previous release) and replace it with `$1`.

Never touch a version string that is a dependency's version — only the project's own.

## Step 3: Draft the changelog

Gather the commits being released (everything on this branch not yet on the release
branch):
```bash
git log --no-merges --pretty='- %s (%h)' "origin/<releaseBranch>..HEAD"
```
Group them sensibly — by Conventional-Commit type (feat / fix / perf / refactor / docs
/ chore) if the messages use it, otherwise by area. Write a concise, human-facing
section; drop pure-noise commits (formatting-only, merge bookkeeping).

If `release.changelogFile` is set, **prepend** a new section to it (create the file
with a standard header if it does not exist):
```
## <tagPrefix><new-version> (<UTC date>)  —  <level> release

### Added / Changed / Fixed
...
```
Keep existing entries below, untouched. If no changelog file is configured, skip the
file write — but still include the drafted notes in your final message so the
orchestrator can put them in the PR body.

Use a UTC date via `date -u +%Y-%m-%d`.

## Step 4: Stage and stop

```bash
git add -A
```
Do **not** commit, push, tag, or open a PR. Report what you changed (version file +
changelog path, or "tag-only, no version file") and paste the drafted changelog notes
so they can flow into the release PR.
