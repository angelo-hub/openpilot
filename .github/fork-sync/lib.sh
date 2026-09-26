# Shared helpers for the fork-sync scripts. Sourced, never executed.
# Identical in every fork; per-repo (and per-line) settings live in config.sh next to this file.
# Scripts operate on the repository in the current directory, which need not contain them: the opendbc
# workflow runs the tools from the default branch against each line's checkout.
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
SYNC_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
source "$SYNC_DIR/config.sh"

WORK=${FORK_SYNC_WORK:-${RUNNER_TEMP:-/tmp}/fork-sync}
mkdir -p "$WORK"
touch "$WORK/vars"
# shellcheck source=/dev/null
source "$WORK/vars"

STATE_LABEL=${STATE_LABEL:-fork-sync}
STATE_TITLE=${STATE_TITLE:-Upstream sync status}
DELTA_TRAILER=${DELTA_TRAILER:-Delta-From}

# In a fork, gh defaults to the *parent* repo (commaai/...). Every gh call here must target the fork.
if [ -z "${GH_REPO:-}" ]; then
  GH_REPO=$(git remote get-url origin | sed -E 's#^(git@github.com:|https://github.com/)##; s#\.git$##')
fi
export GH_REPO
case "$GH_REPO" in commaai/*|sunnypilot/*) echo "refusing to run against $GH_REPO" >&2; exit 1 ;; esac

log() { echo "[fork-sync] $*" >&2; }

# Persist a variable for later steps (and expose it as a step output).
setvar() {
  local k=$1 v=$2
  printf '%s=%q\n' "$k" "$v" >> "$WORK/vars"
  printf -v "$k" '%s' "$v"
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    { echo "$k<<__EOF__"; echo "$v"; echo "__EOF__"; } >> "$GITHUB_OUTPUT"
  fi
}

repo_slug() { echo "$GH_REPO"; }

# --- upstream specs ---
#
#   remote/branch                    merge it (the normal case)
#   delta:remote/branch@remote/base  apply only branch's own changes relative to merge-base(branch, base),
#                                    as a single-parent commit. Used when branch sits on upstream commits
#                                    this line must not take yet (the angle port on top of sunnypilot).
#                                    The applied tip is recorded in a "$DELTA_TRAILER: <sha>" trailer.

spec_ref() { local s=${1#delta:}; echo "${s%@*}"; }
spec_base() { case $1 in delta:*@*) echo "${1#*@}" ;; esac; }
is_delta() { case $1 in delta:*) return 0 ;; *) return 1 ;; esac; }

# Tip most recently delta-applied onto <rev>, from the trailer.
last_delta() {
  git log -1 --format="%(trailers:key=$DELTA_TRAILER,valueonly)" --grep="^$DELTA_TRAILER: " "$1" | head -1 | tr -d '[:space:]'
}

# Start one step: merge or delta-apply <spec> into the index and working tree without committing.
# Returns 0 whether or not it conflicted (check `git diff --diff-filter=U`), 1 if git refused to start.
start_step() {
  local spec=$1 ref tip base
  ref=$(spec_ref "$spec")
  tip=$(git rev-parse "$ref")
  if is_delta "$spec"; then
    base=$(git merge-base "$tip" "$(spec_base "$spec")")
    printf 'Apply %s (%s) onto %s\n\nOnly its own changes relative to %s (%s); the upstream commits it sits on\nare not taken here.\n\n%s: %s\n%s-Base: %s\n' \
      "$ref" "${tip:0:12}" "$INTEGRATION_BRANCH" "$(spec_base "$spec")" "${base:0:12}" \
      "$DELTA_TRAILER" "$tip" "$DELTA_TRAILER" "$base" > "$WORK/commit-msg"
    echo delta > "$WORK/in-progress"
    git read-tree -m -u "$base" HEAD "$tip" > "$WORK/step.log" 2>&1 || return 1
    git merge-index -o -q git-merge-one-file -a >> "$WORK/step.log" 2>&1 || true
  else
    base=$(git merge-base HEAD "$tip")
    printf 'Merge %s (%s) into %s\n' "$ref" "${tip:0:12}" "$INTEGRATION_BRANCH" > "$WORK/commit-msg"
    echo merge > "$WORK/in-progress"
    git merge --no-ff --no-commit "$tip" > "$WORK/step.log" 2>&1 || git rev-parse -q --verify MERGE_HEAD >/dev/null || return 1
  fi
  printf '%s\n%s\n' "$tip" "$base" > "$WORK/step-sides"
}

abort_step() {
  if git rev-parse -q --verify MERGE_HEAD >/dev/null; then git merge --abort; else git reset -q --hard HEAD; fi
  rm -f "$WORK/in-progress"
}

commit_step() {
  local extra=()
  [ "$(cat "$WORK/in-progress")" = delta ] && extra=(--allow-empty)  # record the trailer even if nothing changed
  git commit -q -F "$WORK/commit-msg" ${extra[@]+"${extra[@]}"}
  rm -f "$WORK/in-progress"
}

# --- state: a status issue per line whose body carries the last run's JSON ---

state_issue() {
  # Cached for the run: issue search lags creation, so a second lookup could create a duplicate.
  if [ -n "${STATE_ISSUE:-}" ]; then echo "$STATE_ISSUE"; return; fi
  local n
  n=$(gh issue list --label "$STATE_LABEL" --state all --limit 1 --json number --jq '.[0].number // empty' 2>/dev/null || true)
  if [ -z "$n" ]; then
    gh label create "$STATE_LABEL" --color 5319e7 --description "Weekly upstream sync status" >/dev/null || true
    n=$(gh issue create --title "$STATE_TITLE" --label "$STATE_LABEL" \
          --body "$(state_body '{}' 'No runs yet.')" | grep -oE '[0-9]+$')
  fi
  printf 'STATE_ISSUE=%q\n' "$n" >> "$WORK/vars"
  STATE_ISSUE=$n
  echo "$n"
}

state_body() {
  printf '%s\n\n<!-- fork-sync-state\n%s\n-->\n' "$2" "$1"
}

state_get() {
  local body
  body=$(gh issue view "$(state_issue)" --json body --jq .body)
  echo "$body" | sed -n '/<!-- fork-sync-state/,/-->/p' | sed '1d;$d' | jq -c . 2>/dev/null || echo '{}'
}

# state_set <json> <markdown status>
state_set() {
  gh issue edit "$(state_issue)" --body "$(state_body "$1" "$2")" >/dev/null
}

notify() {
  gh issue comment "$(state_issue)" --body "$1" >/dev/null
}
