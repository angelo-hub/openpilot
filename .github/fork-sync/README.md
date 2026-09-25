# fork sync

Weekly upstream merge for this fork, gated on tests passing, not on the absence of conflicts.

| branch        | holds                                   | written by                        |
|---------------|-----------------------------------------|-----------------------------------|
| `port`        | the fork's changes (default branch)     | you, and merged sync PRs          |
| `integration` | last run's upstream merge, pre-review   | `.github/workflows/fork-sync.yml` |
| `sync/failed` | last red merge, parked for inspection   | the workflow                      |
| `device`      | exactly what the comma installs         | `promote.sh`, by hand, only       |

Rulesets enforce it: `port` and `device` cannot be force-pushed or deleted, and only an admin (you)
can update them, so the workflow and the repair agent physically cannot write either.

## What a run does

1. `detect.sh`: fetch upstream (`config.sh: UPSTREAM_BRANCHES`). If `port` already contains it, or nothing
   moved since the last run, exit silently. Most runs end here.
2. `merge.sh`: reset `integration` to `port`, merge each upstream branch.
   `repo_fixups` (config.sh) keeps `.gitmodules` pointed at angelo-hub/opendbc and pins `opendbc_repo` to the
   opendbc fork's `device` tip. If upstream openpilot pins an opendbc commit that `device` does not contain
   yet, the run stops and waits: sync and promote opendbc first. A promotion of opendbc `device` alone also
   triggers a run, to re-pin.
3. Clean merge: `gate.sh` checks the pin, then builds and runs openpilot's unit tests as upstream CI does.
   (The car behavior gate lives in the opendbc fork; process replay is skipped because it diffs against
   comma's refs, which the fork's opendbc is meant to differ from.)
   Green opens or refreshes a PR `integration -> port`. Red parks the merge on `sync/failed` and reports.
4. Conflict: anything matching `STOP_PATHS` (`.gitmodules`, submodules, `selfdrive/controls/`, `selfdrive/selfdrived/`) or a delete/rename conflict stops the run.
   Otherwise the repair agent (claude-code-action) edits the conflicted files and writes `RESOLUTION.md`.
   `verify.sh` then rejects the attempt if it left markers, took either side wholesale, or touched any other
   file. A verified resolution goes through the same gate, once.

Notifications are comments on the `fork-sync` status issue, posted only when the outcome changes.
Scheduled runs always exit 0 so GitHub does not email you about every red week.

## Promoting to the car

Promote opendbc first, then openpilot. Read the PR, merge it into `port`, then from a local clone:

    .github/fork-sync/promote.sh          # show what would go to device
    .github/fork-sync/promote.sh --yes    # merge port into device (never rebase), tag deployed/<date>-<n>

Each `deployed/*` tag records the previous device commit as the rollback target. Roll back with
`git revert -m 1 <promotion merge>` on `device`, never a force push. Don't promote right before a drive
that matters.

## Setup

- Secret `ANTHROPIC_API_KEY` (only needed when a merge conflicts).
- Actions → General: workflow permissions read/write, and "Allow GitHub Actions to create pull requests".
- Manual run: Actions → fork sync → Run workflow (tick `force` to rerun an unchanged upstream).
