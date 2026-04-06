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

Stages: setup → context-building → interview ↔ update-tooling → plan → review → remediation-plan → remediation → done

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
