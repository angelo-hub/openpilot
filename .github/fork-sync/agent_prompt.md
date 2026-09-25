You are resolving merge conflicts in a personal fork of {{REPO}} that runs on a real car.

The working tree is in the middle of `git merge upstream/{{BRANCH}}` into the `{{INTEGRATION}}` branch,
which was just reset to `{{PORT}}` (the fork's own changes). These files are conflicted:

{{CONFLICTS}}

{{REPO_NOTES}}

## Your job

1. For each conflicted file, understand what upstream changed (`git log -p MERGE_HEAD --not HEAD -- <file>`,
   `git diff HEAD...MERGE_HEAD -- <file>`) and what the port changed (`git diff MERGE_HEAD...HEAD -- <file>`).
2. Edit the file so it keeps **both** intents: upstream's change applied to the port's behavior.
   Remove every conflict marker.
3. Optionally run targeted tests with `.github/fork-sync/agent_test.sh <pytest args>`. A failing test is
   a result to report, not something to fix.
4. Write `RESOLUTION.md` at the repository root with, per file: what upstream changed, what the port
   changed, how you combined them, and anything you were unsure of. Include test results if you ran any.

The workflow, not you, stages, commits, runs the full test suite, and opens the PR.

## Hard rules

These are also enforced mechanically after you finish. Breaking any of them discards your work.

- Edit **only** the conflicted files listed above (plus writing RESOLUTION.md). Never touch any other
  file, in particular never edit a test to make it pass, and never touch anything under a safety/ directory.
- Never resolve by taking a side wholesale: no `git checkout --ours/--theirs`, no `-X ours/theirs`, and no
  reverting the port to make a conflict disappear. A resolution byte-identical to either side is rejected.
- Do not run `git add`, `git commit`, `git merge`, `git reset`, `git checkout`, `git restore`, or `git push`.
- One attempt. Do not iterate on the port's behavior to chase green tests.
- If you cannot combine both sides with confidence, stop: leave the markers in that file and explain why in
  RESOLUTION.md. Stopping is a correct outcome; a plausible guess in steering code is not.
