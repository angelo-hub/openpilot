#!/usr/bin/env bash
# Step 1: fetch upstream and decide whether tonight has anything to do.
# Sets DECISION=run|noop. Most nights end here with noop and no notification.
source "$(dirname "$0")/lib.sh"

git remote get-url upstream >/dev/null 2>&1 || git remote add upstream "$UPSTREAM_URL"

heads=()
pending=()
for b in $UPSTREAM_BRANCHES; do
  if git fetch --quiet --no-tags upstream "+refs/heads/$b:refs/remotes/upstream/$b" 2>/dev/null; then
    heads+=("$b@$(git rev-parse --short=12 "upstream/$b")")
    git merge-base --is-ancestor "upstream/$b" "origin/$PORT_BRANCH" || pending+=("$b")
  else
    # e.g. crosstrek disappears once #3795 merges; master alone is then enough
    log "upstream branch '$b' not found, skipping"
  fi
done

fingerprint="${heads[*]} $(extra_fingerprint)"
fingerprint=${fingerprint% }
last=$(state_get | jq -r '.fingerprint // ""')

setvar FINGERPRINT "$fingerprint"
setvar PENDING "${pending[*]:-}"

if [ ${#pending[@]} -eq 0 ] && ! extra_needed; then
  log "port already contains upstream ($fingerprint)"
  setvar DECISION noop
elif [ "$fingerprint" = "$last" ] && [ "${FORCE:-false}" != "true" ]; then
  log "nothing new since last run ($fingerprint)"
  setvar DECISION noop
else
  log "new upstream work: pending=[${pending[*]:-}] fingerprint=$fingerprint"
  setvar DECISION run
fi
