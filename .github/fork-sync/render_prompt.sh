#!/usr/bin/env bash
# Fill agent_prompt.md for this run's conflict and expose it as the PROMPT step output.
source "$(dirname "$0")/lib.sh"

if is_delta "$CONFLICT_BRANCH"; then
  op="applying only the own changes of \`$(spec_ref "$CONFLICT_BRANCH")\` (relative to its base on \`$(spec_base "$CONFLICT_BRANCH")\`) as a 3-way merge; there is no MERGE_HEAD, use the commits below"
else
  op="\`git merge $(spec_ref "$CONFLICT_BRANCH")\`"
fi
agent_test="$SYNC_DIR/agent_test.sh"
case "$agent_test" in "$ROOT"/*) agent_test=${agent_test#"$ROOT"/} ;; esac

export P_REPO P_OP=$op P_BASE=${CONFLICT_BASE:0:12} P_THEIRS=${CONFLICT_THEIRS:0:12} P_TEST=$agent_test \
  P_INTEG=$INTEGRATION_BRANCH P_PORT=$PORT_BRANCH P_NOTES=$PROMPT_NOTES P_CONFLICTS
P_REPO=$(repo_slug)
P_CONFLICTS=$(echo "$CONFLICTS" | sed 's/.*/- `&`/')
prompt=$(awk '
  { gsub(/\{\{REPO\}\}/, ENVIRON["P_REPO"]); gsub(/\{\{OPERATION\}\}/, ENVIRON["P_OP"])
    gsub(/\{\{BASE\}\}/, ENVIRON["P_BASE"]); gsub(/\{\{THEIRS\}\}/, ENVIRON["P_THEIRS"])
    gsub(/\{\{AGENT_TEST\}\}/, ENVIRON["P_TEST"])
    gsub(/\{\{INTEGRATION\}\}/, ENVIRON["P_INTEG"]); gsub(/\{\{PORT\}\}/, ENVIRON["P_PORT"])
    if ($0 == "{{CONFLICTS}}") { print ENVIRON["P_CONFLICTS"]; next }
    if ($0 == "{{REPO_NOTES}}") { print ENVIRON["P_NOTES"]; next }
    print }' "$SYNC_DIR/agent_prompt.md")
setvar PROMPT "$prompt"
