---
name: context-building
description: Build comprehensive project context -- structure, tech stack, documentation, tool discovery, recommendations. Invoke with /context-building <session-number>.
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash, Agent, Write, Edit, WebSearch, WebFetch
---

# Context Building Phase

You are performing the **context-building** stage of a deep codebase review. Your job is to comprehensively understand the project being reviewed and recommend appropriate review tools.

## Workflow Context

This skill is one stage of a 7-stage deep review workflow orchestrated by the `deep-review` CLI.

- **Branch:** `claude/review/<session-number>` (created by the orchestrator during setup)
- **Work directory:** `./claude-reviews/<session-number>/` -- each stage produces one document here
- **Document ownership:** You may READ any prior document. Only WRITE to your own output document inside `./claude-reviews/$0/` (where `$0` is the session number passed as your argument). Never create files, directories, or write anywhere else under `./claude-reviews/` except your output document. When re-triggered, APPEND new sections -- never delete or overwrite existing content. Mark in-place edits with `> [IN-PLACE EDIT during <stage> phase]: <reason>`.
- **Commits:** Format: `claude-review(<stage>): <description> [session #<N>]`. Commit and push after completing the stage.
- **PR updates:** This stage creates the draft PR and posts a summary to the PR thread (via `gh pr comment`).
- **Subagent cost optimization:** Downgrade information-gathering agents (Explore, web research, context7) to `model: "sonnet"`. Keep the parent session's model for synthesis and judgment.
- **Subagent write boundary:** Subagents in this stage must NOT create, edit, or write any files under `./claude-reviews/`. Only this parent session writes the output document. Include this constraint in every subagent prompt you compose.

## Context
- **Session number:** $0 (the review session number passed as your argument)
- **Work directory:** `./claude-reviews/$0/`
- **Input document:** `./claude-reviews/$0/Session.md`
- **Output document:** `./claude-reviews/$0/Context.md`

## Instructions

### Step 1: Read Session Metadata

Read `./claude-reviews/$0/Session.md` to get the repository and branch information.

### Step 2: Conduct Parallel Discovery

Launch multiple discovery agents simultaneously. All agents use `model: "sonnet"` -- they are gathering information, not making judgments.

**Architecture Mapper** -- launch an Explore agent to:
- Glob for all source files and map the directory structure
- Read key config files (package.json, pyproject.toml, Cargo.toml, go.mod, Gemfile, pom.xml, build.gradle, CMakeLists.txt, etc.)
- Identify all languages, frameworks, and runtime versions
- Map module organization, entry points, and key abstractions
- Identify build tools, bundlers, and compilation steps
- Look at the top-level directory layout and how code is organized

**Documentation Reader** -- launch an Explore agent to:
- Read CLAUDE.md (all of them -- root and subdirectory), README.md, CONTRIBUTING.md
- Read the `docs/` directory if it exists
- Check for API documentation (OpenAPI specs, GraphQL schemas, etc.)
- Assess documentation quality and completeness (preliminary)
- Identify any CLAUDE.md sections that contain large blocks of content that could be extracted to dedicated docs files

**CI/CD Analyzer** -- launch an Explore agent to:
- Read `.github/workflows/`, `.gitlab-ci.yml`, `Jenkinsfile`, `Makefile`, etc.
- Identify CI checks, test commands, lint commands, build commands
- Find deployment configuration
- Identify which checks can be run locally

**Dependency Analyzer** -- launch an agent to:
- Read lock files (package-lock.json, yarn.lock, Pipfile.lock, Cargo.lock, go.sum, etc.)
- Identify dependency management tools and strategies
- Note version pinning approach
- Count direct vs transitive dependencies
- Check for monorepo tooling (workspaces, lerna, nx, turborepo)

**Test Framework Detector** -- launch an agent to:
- Find test directories, test files, test config files
- Identify test frameworks and runners
- Check for coverage configuration and reports
- Identify test patterns (unit, integration, e2e)
- Run test suite to verify it passes (if quick)

### Step 3: Discover Existing Review Tooling

Search the repository for custom review skills, subagents, or tooling already available:

1. **Custom Claude skills/commands:** Look in `.claude/skills/`, `.claude/commands/`, and `CLAUDE.md` files for review-related skills or slash commands.
2. **Agent definitions:** Look for agent configuration files (`.claude/agents/`, agent YAML/JSON/MD files).
3. **Review scripts:** Look for scripts named `*review*`, `*lint*`, `*audit*`, `*check*`, `*analyze*`.
4. **Makefile targets:** `grep -iE '^\S*(?:review|lint|check|audit|analyze)\S*:' Makefile makefile GNUmakefile 2>/dev/null`
5. **Linter configs:** `.eslintrc*`, `pyproject.toml` (ruff/mypy/pylint sections), `.golangci.yml`, `clippy.toml`, `biome.json`, `.rubocop.yml`, `.prettierrc*`, `.stylelintrc*`, etc.

Record what was found (or that nothing was found).

### Step 4: Research Additional Tools

Launch a web research agent (`model: "sonnet"`) to recommend review tools based on the detected tech stack.

**Tool recommendation matrix** (use as a starting point, supplement with web research):

- **JavaScript/TypeScript:** eslint, prettier, typescript-eslint, npm audit, depcheck, madge (circular deps)
- **Python:** ruff, mypy, bandit, safety, black, vulture (dead code), radon (complexity)
- **Go:** golangci-lint, govulncheck, staticcheck
- **Rust:** clippy, cargo-audit, cargo-deny, cargo-udeps
- **Java/Kotlin:** spotbugs, checkstyle, pmd, dependency-check
- **Ruby:** rubocop, brakeman, bundler-audit
- **General:** semgrep, trivy, gitleaks, tokei/cloc (line counts), jscpd (copy-paste detection)
- **Documentation:** markdownlint, alex (inclusive language)

For each tool, determine:
- Is it already installed?
- Is it already configured in the repo?
- What would it catch that manual review might miss?
- Install and run commands

Only recommend tools that are relevant to the detected stack. Do not recommend tools for languages not used in the project.

### Step 5: Identify Derived Interfaces

Look for derived or generated packages/interfaces:
- SDK packages (client libraries)
- API definitions (REST, GraphQL, gRPC/protobuf)
- RPC definitions
- MCP server definitions
- WebUI/frontend components that consume backend APIs
- Generated types or code (codegen configs)
- Shared types packages in monorepos

### Step 6: Write Context.md

Synthesize all findings into `./claude-reviews/$0/Context.md`:

```
# Context Report: Review Session #<N>

## Project Overview
What this project is, its purpose, primary users/consumers.

## Technology Stack
Languages, frameworks, runtime versions, build tools, package managers.

## Architecture
Directory structure, module organization, key abstractions, data flow, entry points.

## Dependencies
Key dependencies and their purpose. Dependency management strategy. Direct vs transitive count.

## Testing Infrastructure
Test frameworks, coverage tooling, test patterns, CI integration. Current test health (pass/fail).

## Documentation Assessment
What docs exist, preliminary quality/completeness rating. CLAUDE.md files found and their state.

## Derived Interfaces
SDKs, APIs, RPC definitions, MCP servers, WebUI components detected. How they relate to core code.

## Available Review Tooling
### Already in Repo
List of existing linters, review scripts, Claude skills, and agents discovered.

### Recommended Additions
For each recommended tool:
- **Tool:** name
- **Category:** static-analysis / security / dependency / quality / docs / formatting / testing / performance
- **Why:** what it would catch that manual review might miss
- **Install:** command to install
- **Run:** command to run
- **Already installed:** yes/no
- **Persistence risk:** low (CLI tool) / medium (adds config file) / high (modifies build pipeline)

## Open Questions for Interview
Ambiguities about the project that need user clarification before planning the review.
```

### Step 7: Commit and Push

```bash
git add ./claude-reviews/$0/Context.md
git commit -m "claude-review(context-building): complete context analysis [session #$0]"
git push
```

### Step 8: Create Draft PR

Create a draft Pull Request with a summary of the context:

```bash
gh pr create \
  --title "Deep Review Session #$0" \
  --body "<context summary: project type, stack, key findings, tool recommendations>" \
  --draft \
  --base main \
  --head "claude/review/$0"
```

The PR body should contain:
- Brief project description
- Technology stack summary
- Number of recommended tools
- Key areas of interest for review
- Reference to `./claude-reviews/$0/Context.md` for full details

### Step 9: Comment on PR

Post a structured summary to the PR thread:

```bash
gh pr comment "claude/review/$0" --body "<context summary>"
```

## Stage Transition Signal

When running under the `deep-review` orchestrator, you can request a transition to a different stage by writing the target stage name to `./claude-reviews/$0/.next-stage`.

**Rules:**
- Write exactly one stage name, nothing else
- Only write this file if you want a NON-DEFAULT transition
- If you do not write this file, the orchestrator advances to `interview` (default)
- The orchestrator validates your request -- invalid transitions are ignored

**When to signal:**
- In almost all cases, do NOT write a signal file. The default (advance to interview) is correct.

## Re-trigger Behavior

If re-triggered, append a new section:

```
---

## Additional Context (triggered during <stage> phase)

### Reason for Re-investigation
<why this context building was needed again>

### Findings
<new findings>
```

Do not modify the original sections unless correcting a factual error (mark in-place edits clearly).
