# fork-sync settings for angelo-hub/openpilot (device-side changes; opendbc comes from angelo-hub/opendbc).
# Sourced by lib.sh.

UPSTREAM_URL=https://github.com/commaai/openpilot.git
UPSTREAM_BRANCHES="master"
PORT_BRANCH=port
INTEGRATION_BRANCH=integration
FAILED_BRANCH=sync/failed

# .gitmodules and the opendbc_repo pointer are handled by repo_fixups below before triage; a conflict left
# in them, or in the openpilot side of lateral control, stops the run.
STOP_PATHS='^(\.gitmodules|opendbc_repo|panda|selfdrive/controls/|selfdrive/selfdrived/)'

PROMPT_NOTES="This fork carries device-side changes only (systemd units, offroad power management, networking
persistence). The opendbc_repo submodule and .gitmodules are managed by the workflow; never touch them."

# The opendbc submodule tracks the opendbc fork's device branch: only opendbc code already promoted to
# the car is ever pinned here. Merging upstream openpilot would otherwise silently flip the pointer back
# to comma's opendbc.
OPENDBC_FORK=https://github.com/angelo-hub/opendbc.git
OPENDBC_UPSTREAM=https://github.com/commaai/opendbc.git
OPENDBC_URL_IN_GITMODULES=../../angelo-hub/opendbc.git

opendbc_device() { git ls-remote "$OPENDBC_FORK" refs/heads/device | cut -f1; }

extra_fingerprint() { echo "opendbc-device@$(opendbc_device | cut -c1-12)"; }

# Work to do even without upstream changes: the opendbc device branch moved since port was pinned.
extra_needed() {
  local d
  d=$(opendbc_device)
  [ -n "$d" ] && [ "$(git rev-parse "origin/$PORT_BRANCH:opendbc_repo")" != "$d" ]
}

# Run after every merge (clean or conflicted) and on pin-only runs. Returns 1 to refuse the merge,
# writing the reason to $WORK/repo-block.md.
repo_fixups() {
  local d up
  d=$(opendbc_device)
  if [ -z "$d" ]; then
    echo "angelo-hub/opendbc has no \`device\` branch yet; create it before openpilot can be synced." > "$WORK/repo-block.md"
    return 1
  fi

  if git rev-parse -q --verify MERGE_HEAD >/dev/null && [ -n "$(git ls-files -u -- .gitmodules)" ]; then
    git show MERGE_HEAD:.gitmodules > .gitmodules  # upstream's submodule list, with our URL re-applied below
  fi
  git config -f .gitmodules submodule.opendbc.url "$OPENDBC_URL_IN_GITMODULES"
  git add .gitmodules

  # Upstream openpilot may need a newer opendbc than the car runs. Only proceed once the fork's device
  # branch already contains the opendbc commit upstream pins.
  up=$(git rev-parse -q --verify "upstream/master:opendbc_repo" || true)
  if [ -n "$up" ]; then
    local odb="$WORK/opendbc.git"
    [ -d "$odb" ] || git init -q --bare "$odb"
    git -C "$odb" fetch -q --filter=blob:none "$OPENDBC_FORK" "+refs/heads/device:refs/heads/device"
    git -C "$odb" fetch -q --filter=blob:none "$OPENDBC_UPSTREAM" "$up" 2>/dev/null || true
    if ! git -C "$odb" merge-base --is-ancestor "$up" "$d" 2>/dev/null; then
      printf 'upstream openpilot pins opendbc `%s`, which angelo-hub/opendbc `device` (`%s`) does not contain yet. Merge and promote the opendbc sync first; openpilot will follow on its next run.\n' \
        "${up:0:12}" "${d:0:12}" > "$WORK/repo-block.md"
      return 1
    fi
  fi
  git update-index --cacheinfo "160000,$d,opendbc_repo"
}
