#!/usr/bin/env bash
# Step 1: fetch upstream and decide whether this run has anything to do.
# Sets DECISION=run|noop. Most runs end here with noop and no notification.
source "$(dirname "$0")/lib.sh"

for r in $UPSTREAM_REMOTES; do
  git remote get-url "${r%%=*}" >/dev/null 2>&1 || git remote add "${r%%=*}" "${r#*=}"
done

fetch_ref() {  # remote/branch
  git fetch --quiet --no-tags "${1%%/*}" "+refs/heads/${1#*/}:refs/remotes/$1" 2>/dev/null
}

heads=()
pending=()
for spec in $UPSTREAM_SPECS; do
  ref=$(spec_ref "$spec")
  base=$(spec_base "$spec")
  if ! fetch_ref "$ref" || { [ -n "$base" ] && ! fetch_ref "$base"; }; then
    # e.g. crosstrek disappears once #3795 merges; the other specs carry on
    log "upstream '$ref' not found, skipping"
    continue
  fi
  tip=$(git rev-parse "$ref")
  heads+=("$spec@${tip:0:12}")
  if is_delta "$spec"; then
    [ "$(last_delta "origin/$PORT_BRANCH")" = "$tip" ] || pending+=("$spec")
  else
    git merge-base --is-ancestor "$tip" "origin/$PORT_BRANCH" || pending+=("$spec")
  fi
done

fingerprint="${heads[*]:-} $(extra_fingerprint)"
fingerprint=${fingerprint% }
last=$(state_get | jq -r '.fingerprint // ""')

setvar FINGERPRINT "$fingerprint"
setvar PENDING "${pending[*]:-}"

if [ ${#pending[@]} -eq 0 ] && ! extra_needed; then
  log "$PORT_BRANCH already contains upstream ($fingerprint)"
  setvar DECISION noop
elif [ "$fingerprint" = "$last" ] && [ "${FORCE:-false}" != "true" ]; then
  log "nothing new since last run ($fingerprint)"
  setvar DECISION noop
else
  log "new upstream work: pending=[${pending[*]:-}] fingerprint=$fingerprint"
  setvar DECISION run
fi
