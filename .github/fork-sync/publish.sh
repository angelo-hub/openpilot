#!/usr/bin/env bash
# Final step: push what is reviewable, open or refresh the PR into port, record state, and notify
# only when the outcome changed. Never writes port or device.
source "$(dirname "$0")/lib.sh"

slug=$(repo_slug)
run_url="${GITHUB_SERVER_URL:-https://github.com}/$slug/actions/runs/${GITHUB_RUN_ID:-local}"
agent_ran=false
[ -n "${VERIFY:-}" ] && agent_ran=true

section() { [ -s "$2" ] && printf '\n### %s\n\n%s\n' "$1" "$(cat "$2")"; true; }
details=$(
  echo "Upstream: \`$FINGERPRINT\`"
  [ -n "${MERGED:-}" ] && echo "Merged: \`$MERGED\`"
  [ -n "${DEFERRED:-}" ] && echo "Deferred to next run (second conflict): \`$DEFERRED\`"
  [ -n "${CONFLICTS:-}" ] && printf '\nConflicted while merging `%s`:\n%s\n' "${CONFLICT_BRANCH:-}" "$(echo "$CONFLICTS" | sed 's/.*/- `&`/')"
  section "Repair agent's explanation" "$WORK/resolution.md"
  section "Resolution check (verify.sh)" "$WORK/verify.md"
  section "Gate" "$WORK/gate.md"
  printf '\n[Workflow run](%s)\n' "$run_url"
)

case "${RESULT:-}" in
  clean)
    if [ "${GATE:-}" = green ]; then outcome=green; else outcome=red; fi ;;
  conflict)
    if [ "${AGENT_OUTCOME:-}" != success ]; then outcome=agent-failed
    elif [ "${VERIFY:-}" != ok ]; then outcome=verify-failed
    elif [ "${GATE:-}" = green ]; then outcome=green
    else outcome=red; fi ;;
  *) outcome=${RESULT:-error} ;;
esac

title="Upstream sync $(date -u +%F): $outcome"
headline=""
case "$outcome" in
  green)
    git push -q --force origin "HEAD:refs/heads/$INTEGRATION_BRANCH"
    body=$(printf 'Automated upstream merge into `%s`. Gate is green%s.\n\nReview before merging: merging this PR does **not** touch the car; promotion to `%s` stays manual.\n\n%s\n' \
      "$PORT_BRANCH" "$($agent_ran && echo ', after a repair-agent conflict resolution' || true)" "${DEVICE_BRANCH:-device}" "$details")
    pr=$(gh pr list --head "$INTEGRATION_BRANCH" --base "$PORT_BRANCH" --state open --json number --jq '.[0].number // empty')
    if [ -n "$pr" ]; then
      gh pr edit "$pr" --title "$title" --body "$body" >/dev/null
    else
      pr=$(gh pr create --head "$INTEGRATION_BRANCH" --base "$PORT_BRANCH" --title "$title" --body "$body" | grep -oE '[0-9]+$')
    fi
    headline="✅ upstream merged and gate green → PR #$pr" ;;
  red)
    # Keep integration (and any open green PR) as it was; park tonight's merge for inspection.
    git push -q --force origin "HEAD:refs/heads/$FAILED_BRANCH"
    headline="❌ merge applied but the gate is red. Nothing looked wrong textually; this is the case that matters. Inspect: [\`$FAILED_BRANCH\`](${GITHUB_SERVER_URL:-https://github.com}/$slug/compare/$PORT_BRANCH...$FAILED_BRANCH)" ;;
  blocked-safety)
    headline="🛑 conflict under \`$STOP_PATHS\`: upstream changed code that bounds steering. Stopped without touching it; resolve by hand:
$(echo "$STOPPED" | sed 's/.*/- `&`/')" ;;
  blocked-structural)
    headline="🛑 delete/rename conflict an agent cannot combine; resolve by hand:
$(echo "$STOPPED" | sed 's/.*/- `&`/')" ;;
  blocked-repo)
    headline="⏸️ $(cat "$WORK/repo-block.md" 2>/dev/null || echo 'repo-specific rule refused the merge')" ;;
  verify-failed)
    headline="🛑 repair agent's resolution broke the rules below; nothing was pushed. Resolve by hand." ;;
  agent-failed)
    headline="🛑 conflict in allowed paths, but the repair agent did not finish (missing ANTHROPIC_API_KEY, error, or turn limit). Resolve by hand." ;;
  *)
    headline="⚠️ sync run errored before finishing; see the workflow run." ;;
esac

# Signature: what a human would consider "the same news" as last time.
signature=$(printf '%s\n%s\n%s\n' "$outcome" "${CONFLICTS:-}" "$(grep -E '^- ❌' "$WORK/gate.md" 2>/dev/null || true)" | shasum | cut -c1-16)
prev=$(state_get)
prev_sig=$(echo "$prev" | jq -r '.signature // ""')

state=$(jq -nc --arg f "$FINGERPRINT" --arg o "$outcome" --arg s "$signature" --arg r "$run_url" --arg t "$(date -u +%FT%TZ)" \
  '{fingerprint:$f, outcome:$o, signature:$s, run:$r, at:$t}')
state_set "$state" "$(printf '**Last run** %s: %s\n\n%s\n' "$(date -u +%F)" "$headline" "$details")"

if [ "$signature" != "$prev_sig" ]; then
  notify "$(printf '%s\n\n%s\n' "$headline" "$details")"
  log "notified: $outcome"
else
  log "same outcome as last run ($outcome); not notifying"
fi

# Always exit 0: a failed scheduled run makes GitHub email every time, which is the noise the
# signature check above exists to avoid. The status issue is the notification channel.
exit 0
