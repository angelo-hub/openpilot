#!/usr/bin/env bash
# Manual promotion: port -> device. The only thing that ever writes device, and it is run by a human.
#
#   .github/fork-sync/promote.sh            show what would be promoted
#   .github/fork-sync/promote.sh --yes      merge (never rebase), tag, push
#
# Each promotion gets an annotated tag deployed/<date>-<n> recording the previous device commit, so a
# bad drive has an obvious rollback target. Roll back by reverting, never by force-pushing (the car
# updates over git):  git revert -m 1 <promotion merge>  on device, then push.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
source .github/fork-sync/config.sh
DEVICE_BRANCH=device

git fetch -q origin "$PORT_BRANCH" "$DEVICE_BRANCH" --tags
prev=$(git rev-parse "origin/$DEVICE_BRANCH")

echo "Commits on $PORT_BRANCH not yet on $DEVICE_BRANCH:"
git log --oneline --first-parent "origin/$DEVICE_BRANCH..origin/$PORT_BRANCH"
if git merge-base --is-ancestor "origin/$PORT_BRANCH" "origin/$DEVICE_BRANCH"; then
  echo "(nothing to promote)"; exit 0
fi
[ "${1:-}" = "--yes" ] || { echo; echo "Re-run with --yes to promote. Not right before a drive that matters."; exit 0; }

wt=$(mktemp -d)
git worktree add -q --detach "$wt" "origin/$DEVICE_BRANCH"
(
  cd "$wt"
  git merge -q --no-ff --no-edit -m "Promote $PORT_BRANCH ($(git rev-parse --short=12 "origin/$PORT_BRANCH")) to $DEVICE_BRANCH" "origin/$PORT_BRANCH"
  n=1; while git rev-parse -q --verify "refs/tags/deployed/$(date +%F)-$n" >/dev/null; do n=$((n+1)); done
  tag="deployed/$(date +%F)-$n"
  git tag -a "$tag" -m "Promoted to $DEVICE_BRANCH. Previous device commit (rollback target): $prev"
  git push origin "HEAD:refs/heads/$DEVICE_BRANCH" "refs/tags/$tag"
  echo "Promoted: $(git rev-parse --short=12 HEAD)  tag $tag  rollback target $prev"
)
git worktree remove --force "$wt"
