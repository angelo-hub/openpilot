#!/usr/bin/env bash
# The gate for openpilot: what runs on a stock GitHub runner. Same build and unit tests as upstream's
# tests.yaml. Process replay is left out on purpose: it diffs against comma's refs and the fork's opendbc
# is meant to differ; the car behavior gate lives in the opendbc fork.
# Writes $WORK/gate.md and sets GATE=green|red.
source "$(dirname "$0")/lib.sh"

report="$WORK/gate.md"
: > "$report"
status=green

step() {
  local name=$1; shift
  local logf="$WORK/gate-$(echo "$name" | tr ' /' '__').log"
  log "gate: $name"
  if "$@" > "$logf" 2>&1; then
    echo "- ✅ $name" >> "$report"
  else
    status=red
    { echo "- ❌ **$name**"; echo; echo '  <details><summary>last 80 lines</summary>'; echo
      echo '  ```'; tail -n 80 "$logf" | sed 's/^/  /'; echo '  ```'; echo '  </details>'; } >> "$report"
  fi
  echo "::group::$name"; cat "$logf"; echo "::endgroup::"
}

build_and_test() {
  git submodule sync --recursive
  git submodule update --init --recursive
  ./tools/op.sh setup
  # shellcheck source=/dev/null
  source .venv/bin/activate
  scons -j"$(nproc)"
  RAYLIB_BACKEND=headless tools/op.sh test
}

step "opendbc pinned to angelo-hub/opendbc device" test "$(git rev-parse HEAD:opendbc_repo)" = "$(opendbc_device)"
step "build + unit tests (scons, tools/op.sh test)" build_and_test

setvar GATE "$status"
