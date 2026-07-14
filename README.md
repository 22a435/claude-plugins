# 22a435-workflows

Claude Code plugins for autonomous development workflows.

## Plugins

### [issue-workflow](./issue-workflow/)

Autonomous issue-to-PR workflow with 8 stages. Given a GitHub issue number, produces a reviewed, tested, integration-ready pull request.

```bash
work-issue 42
```

Stages: setup → research ↔ interview ↔ plan → execute ↔ debug ↔ verify ↔ review ↔ integrate → done

### [deep-review](./deep-review/)

Comprehensive codebase review with up to 10 parallel sub-reviewers and automated remediation. Reviews the entire codebase, not just recent changes.

```bash
deep-review
```

Stages: setup → context-building → interview ↔ update-tooling → [plan-sc-audit → run-sc-audit] → plan → review → remediation-plan → remediation → verify → integrate → done

## Branching

By default every plugin cuts a branch from `origin/main` and opens its PR against `main`. Repos that use a different convention -- a `develop`/staging merge target, or semver **update branches** (`major`/`minor`/`patch` staging branches promoted to `main` on release) -- drop a `.claude-workflows.json` at their repo root to set the target branch, an update-branch map, the feature-branch prefix, and the protected-branch list. issue-workflow additionally supports `--bump major|minor|patch` (route by change size, or via a `semver:*` issue label) and `--onto <branch|PR#>` (stack sequential PRs on an open feature branch). With no config and no flags, behavior is unchanged. See each plugin's README and the [CLAUDE.md](./CLAUDE.md) for the schema.

## Installation

```bash
# Add the marketplace
claude plugin marketplace add 22a435/claude-plugins

# Install one or both plugins
claude plugin install 22a435-workflows@issue-workflow --scope user
claude plugin install 22a435-workflows@deep-review --scope user
```

See each plugin's README for CLI setup and usage details.

## Prerequisites

- **GitHub CLI** (`gh`) -- authenticated
- **Claude Code CLI** (`claude`) -- authenticated
- **git** and **jq** in PATH

## License

MIT
