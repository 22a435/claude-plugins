---
name: resolve-merge
description: Resolve conflicts from a branchflow cascade or reconcile merge, preserving BOTH release lines' intent. Invoke with /branchflow:resolve-merge <head> <base> <kind>.
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash, Edit, Write
---

# Resolve Merge (branchflow)

You are resolving a merge conflict for the **branchflow** release-train tool. The
orchestrator has already started a merge and left conflicts in the working tree;
your only job is to resolve them correctly and stage the result. **Do not commit,
push, or open a PR** — the orchestrator does that after you return.

## Arguments
- `$1` = **head**: the branch being merged IN (its changes must be preserved).
- `$2` = **base**: the branch being merged INTO (its changes must be preserved).
- `$3` = **kind**: `cascade` (a lower line flowing up into a higher one) or
  `reconcile` (the release branch flowing down into an accumulator).

You are currently checked out on a throwaway branch (`branchflow/<kind>/...`) that
was created from `base`, with `head` merged into it (`--no-commit`), conflicts and all.

## The rule that governs every resolution

These two branches are **parallel release lines that both legitimately changed the
code.** This is NOT a "pick one side" situation. Integrate **both** intents:

- For **cascade** (`head` is a lower line, e.g. patch → minor): the lower line's
  change is usually a fix that must land on top of whatever the higher line already
  did. Keep the higher line's work AND apply the lower line's fix to it.
- For **reconcile** (`head` is the release branch flowing down): the release branch
  carries the just-shipped baseline; the accumulator carries unshipped work. Keep the
  accumulator's unshipped work AND take the released baseline.
- If a genuine semantic conflict makes "both" impossible, choose the resolution that
  preserves correctness and leaves the codebase building, and add a brief
  `> RESOLUTION NOTE:` comment near the change explaining what you did and why.

## Steps

### 1. Survey the conflicts
```bash
git status --short          # 'UU' / 'AA' etc. mark conflicted paths
git ls-files -u | awk '{print $4}' | sort -u    # the conflicted files
```
For each, read the full file and the surrounding code to understand both sides
(`git log --oneline -3 "$1"` and `"$2"` help you see what each line was doing).

### 2. Resolve each file
Edit out every conflict marker (`<<<<<<<`, `=======`, `>>>>>>>`), integrating both
sides per the rule above. Then stage it:
```bash
git add <resolved-file>
```

### 3. Sanity-check
- No markers remain: `! grep -rnE '^(<<<<<<<|=======|>>>>>>>)' $(git ls-files)`
- Nothing left unmerged: `git ls-files -u` prints nothing.
- If the repo has a fast local check (lint/typecheck/build), run it to confirm the
  merged tree is coherent; fix anything the merge broke.

### 4. Stop
Leave the merge staged but **uncommitted** (the orchestrator commits it, pushes the
resolution branch, and opens the review PR). Do not run `git commit`, `git merge
--continue`, `git push`, or `gh pr ...`.

If a conflict is beyond safe automatic resolution, leave that file conflicted and
clearly say so in your final message — the orchestrator will detect the remaining
conflict and route it to a human instead of opening a PR.
