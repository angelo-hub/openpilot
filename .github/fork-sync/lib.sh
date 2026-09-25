# Shared helpers for the fork-sync scripts. Sourced, never executed.
# Identical in the opendbc and openpilot forks; per-repo settings live in config.sh.
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
SYNC_DIR="$ROOT/.github/fork-sync"
# shellcheck source=/dev/null
source "$SYNC_DIR/config.sh"

WORK=${FORK_SYNC_WORK:-${RUNNER_TEMP:-/tmp}/fork-sync}
mkdir -p "$WORK"
touch "$WORK/vars"
# shellcheck source=/dev/null
source "$WORK/vars"

STATE_LABEL=fork-sync

# In a fork, gh defaults to the *parent* repo (commaai/...). Every gh call here must target the fork.
if [ -z "${GH_REPO:-}" ]; then
  GH_REPO=$(git remote get-url origin | sed -E 's#^(git@github.com:|https://github.com/)##; s#\.git$##')
fi
export GH_REPO
case "$GH_REPO" in commaai/*) echo "refusing to run against $GH_REPO" >&2; exit 1 ;; esac

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

# --- state: a single status issue whose body carries the last run's JSON ---

state_issue() {
  local n
  n=$(gh issue list --label "$STATE_LABEL" --state all --limit 1 --json number --jq '.[0].number // empty' 2>/dev/null || true)
  if [ -z "$n" ]; then
    gh label create "$STATE_LABEL" --color 5319e7 --description "Weekly upstream sync status" >/dev/null || true
    n=$(gh issue create --title "Upstream sync status" --label "$STATE_LABEL" \
          --body "$(state_body '{}' 'No runs yet.')" | grep -oE '[0-9]+$')
  fi
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
