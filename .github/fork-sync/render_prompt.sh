#!/usr/bin/env bash
# Fill agent_prompt.md for tonight's conflict and expose it as the PROMPT step output.
source "$(dirname "$0")/lib.sh"

export P_REPO P_BRANCH=$CONFLICT_BRANCH P_INTEG=$INTEGRATION_BRANCH P_PORT=$PORT_BRANCH P_NOTES=$PROMPT_NOTES P_CONFLICTS
P_REPO=$(repo_slug)
P_CONFLICTS=$(echo "$CONFLICTS" | sed 's/.*/- `&`/')
prompt=$(awk '
  { gsub(/\{\{REPO\}\}/, ENVIRON["P_REPO"]); gsub(/\{\{BRANCH\}\}/, ENVIRON["P_BRANCH"])
    gsub(/\{\{INTEGRATION\}\}/, ENVIRON["P_INTEG"]); gsub(/\{\{PORT\}\}/, ENVIRON["P_PORT"])
    if ($0 == "{{CONFLICTS}}") { print ENVIRON["P_CONFLICTS"]; next }
    if ($0 == "{{REPO_NOTES}}") { print ENVIRON["P_NOTES"]; next }
    print }' "$SYNC_DIR/agent_prompt.md")
setvar PROMPT "$prompt"
