#!/usr/bin/env bash
# Manual promotion: port -> device. The only thing that ever writes device, and it is run by a human.
#
#   .github/fork-sync/promote.sh [--line sp]          show what would be promoted
#   .github/fork-sync/promote.sh [--line sp] --yes    merge (never rebase), tag, push
#
# Each promotion gets an annotated tag <prefix>/<date>-<n> recording the previous device commit, so a
# bad drive has an obvious rollback target. Roll back by reverting, never by force-pushing (the car
# updates over git):  git revert -m 1 <promotion merge>  on device, then push.
set -euo pipefail
yes=false
while [ $# -gt 0 ]; do
  case $1 in
    --line) export FORK_SYNC_LINE=$2; shift 2 ;;
    --yes) yes=true; shift ;;
    *) echo "usage: $0 [--line <line>] [--yes]" >&2; exit 1 ;;
  esac
done
cd "$(git rev-parse --show-toplevel)"
# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.sh"
DEVICE_BRANCH=${DEVICE_BRANCH:-device}
DEPLOY_TAG_PREFIX=${DEPLOY_TAG_PREFIX:-deployed}

git fetch -q origin "$PORT_BRANCH" "$DEVICE_BRANCH" --tags
prev=$(git rev-parse "origin/$DEVICE_BRANCH")

echo "Commits on $PORT_BRANCH not yet on $DEVICE_BRANCH:"
git log --oneline --first-parent "origin/$DEVICE_BRANCH..origin/$PORT_BRANCH"
if git merge-base --is-ancestor "origin/$PORT_BRANCH" "origin/$DEVICE_BRANCH"; then
  echo "(nothing to promote)"; exit 0
fi
$yes || { echo; echo "Re-run with --yes to promote. Not right before a drive that matters."; exit 0; }

wt=$(mktemp -d)
git worktree add -q --detach "$wt" "origin/$DEVICE_BRANCH"
(
  cd "$wt"
  git merge -q --no-ff --no-edit -m "Promote $PORT_BRANCH ($(git rev-parse --short=12 "origin/$PORT_BRANCH")) to $DEVICE_BRANCH" "origin/$PORT_BRANCH"
  n=1; while git rev-parse -q --verify "refs/tags/$DEPLOY_TAG_PREFIX/$(date +%F)-$n" >/dev/null; do n=$((n+1)); done
  tag="$DEPLOY_TAG_PREFIX/$(date +%F)-$n"
  git tag -a "$tag" -m "Promoted to $DEVICE_BRANCH. Previous device commit (rollback target): $prev"
  git push origin "HEAD:refs/heads/$DEVICE_BRANCH" "refs/tags/$tag"
  echo "Promoted: $(git rev-parse --short=12 HEAD)  tag $tag  rollback target $prev"
)
git worktree remove --force "$wt"
