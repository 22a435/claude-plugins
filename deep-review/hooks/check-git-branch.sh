#!/bin/bash
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only check git push commands
if ! echo "$COMMAND" | grep -q "git push"; then
  exit 0
fi

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
PROTECTED_BRANCHES=("main" "master" "production")

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
