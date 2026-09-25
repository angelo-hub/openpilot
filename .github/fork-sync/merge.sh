#!/usr/bin/env bash
# Steps 2-4: reset integration to port, merge each pending upstream branch, triage conflicts.
#
#   merge.sh            start from port and merge everything in $PENDING
#   merge.sh continue   after a repaired conflict, merge whatever was left in $REMAINING
#
# Sets RESULT to one of:
#   clean               every merge applied (possibly after repair); go run the gate
#   conflict            stopped mid-merge in allowed paths only; the repair agent may run
#   blocked-safety      a conflict touches $STOP_PATHS; merge aborted, human review
#   blocked-structural  delete/rename-style conflict an agent cannot combine; merge aborted
#   blocked-repo        a repo-specific rule refused the merge (see config.sh); merge aborted
source "$(dirname "$0")/lib.sh"

mode=${1:-start}
if [ "$mode" = start ]; then
  git checkout -q -B "$INTEGRATION_BRANCH" "origin/$PORT_BRANCH"
  read -r -a todo <<< "${PENDING:-}"
  merged=()
else
  read -r -a todo <<< "${REMAINING:-}"
  read -r -a merged <<< "${MERGED:-} $CONFLICT_BRANCH"
fi
deferred=()

# If the repo needs a fixup but upstream had nothing new (e.g. openpilot re-pinning opendbc).
if [ "$mode" = start ] && [ ${#todo[@]} -eq 0 ]; then
  if ! repo_fixups; then setvar RESULT blocked-repo; exit 0; fi
  if ! git diff --cached --quiet; then
    git commit -q -m "fork-sync: repo fixups ($(extra_fingerprint))"
  fi
fi

while [ ${#todo[@]} -gt 0 ]; do
  b=${todo[0]}
  todo=("${todo[@]:1}")
  msg="Merge upstream $b ($(git rev-parse --short=12 "upstream/$b")) into $INTEGRATION_BRANCH"

  if git merge --no-ff --no-edit -m "$msg" "upstream/$b" > "$WORK/merge-$b.log" 2>&1; then
    # A clean merge can still silently flip things the fork owns (e.g. a submodule pointer).
    if ! repo_fixups; then git reset -q --hard HEAD~1; setvar RESULT blocked-repo; exit 0; fi
    git diff --cached --quiet || git commit -q --amend --no-edit
    merged+=("$b")
    continue
  fi

  if ! repo_fixups; then git merge --abort; setvar RESULT blocked-repo; exit 0; fi
  conflicts=$(git diff --name-only --diff-filter=U)
  if [ -z "$conflicts" ]; then
    git commit -q --no-edit
    merged+=("$b")
    continue
  fi

  if [ "$mode" = continue ]; then
    # One repair per night. Leave the rest for tomorrow rather than stacking agent runs.
    git merge --abort
    deferred=("$b" "${todo[@]}")
    break
  fi

  setvar CONFLICTS "$conflicts"
  setvar CONFLICT_BRANCH "$b"
  setvar MERGED "${merged[*]:-}"
  setvar REMAINING "${todo[*]:-}"

  stop=$(echo "$conflicts" | grep -E "$STOP_PATHS" || true)
  if [ -n "$stop" ]; then
    git merge --abort
    setvar STOPPED "$stop"
    setvar RESULT blocked-safety
    exit 0
  fi

  # Only both-modified (UU) and both-added (AA) conflicts have two sides to combine.
  structural=$(git status --porcelain=v1 | grep -E '^(DD|AU|UD|UA|DU) ' | cut -c4- || true)
  if [ -n "$structural" ]; then
    git merge --abort
    setvar STOPPED "$structural"
    setvar RESULT blocked-structural
    exit 0
  fi

  # Snapshot for verify.sh: HEAD, both sides of each conflict, and every non-conflicted index entry.
  git rev-parse HEAD > "$WORK/pre-head"
  : > "$WORK/sides"
  while IFS= read -r f; do
    printf '%s\t%s\t%s\n' "$f" "$(git rev-parse -q --verify ":2:$f" || true)" "$(git rev-parse -q --verify ":3:$f" || true)" >> "$WORK/sides"
  done <<< "$conflicts"
  git ls-files -s | awk '$3 == 0' | awk -F'\t' 'NR==FNR{c[$1]=1; next} !($2 in c)' <(echo "$conflicts") - | sort > "$WORK/stage0.before"

  setvar RESULT conflict
  exit 0
done

setvar MERGED "${merged[*]:-}"
setvar DEFERRED "${deferred[*]:-}"
setvar RESULT clean
