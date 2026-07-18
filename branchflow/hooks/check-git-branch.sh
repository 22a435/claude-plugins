#!/bin/bash
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only check git push commands
if ! echo "$COMMAND" | grep -q "git push"; then
  exit 0
fi

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

# Protected branches default to main/master/production. A repo can override
# the list via "protectedBranches" in .claude-workflows.json at its root --
# recommended for repos with develop/staging or major/minor/patch update
# branches, so feature sessions can never push directly to a merge target.
PROTECTED_BRANCHES=("main" "master" "production")
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
CFG="${REPO_ROOT}/.claude-workflows.json"
if [[ -n "$REPO_ROOT" && -f "$CFG" ]] && jq -e '.protectedBranches | arrays' "$CFG" >/dev/null 2>&1; then
  mapfile -t PROTECTED_BRANCHES < <(jq -r '.protectedBranches[]' "$CFG")
fi

for protected in "${PROTECTED_BRANCHES[@]}"; do
  if [[ "$BRANCH" == "$protected" ]]; then
    echo "{
      \"hookSpecificOutput\": {
        \"hookEventName\": \"PreToolUse\",
        \"permissionDecision\": \"deny\",
        \"permissionDecisionReason\": \"Cannot push to protected branch: $BRANCH. Use a feature branch and open a PR instead.\"
      }
    }"
    exit 0
  fi
done

exit 0
