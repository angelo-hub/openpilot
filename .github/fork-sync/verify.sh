#!/usr/bin/env bash
# Mechanical checks on the repair agent's work, run by the workflow (not the agent).
# The prompt states the rules; this script is what actually enforces them.
# On success, commits the merge. Sets VERIFY=ok|failed and writes $WORK/verify.md.
source "$(dirname "$0")/lib.sh"

report="$WORK/verify.md"
: > "$report"
fail() { echo "- $*" >> "$report"; }

if [ -f RESOLUTION.md ]; then
  mv RESOLUTION.md "$WORK/resolution.md"
else
  fail "agent did not write RESOLUTION.md explaining the resolution"
fi

# The agent must not commit, reset, or abort: HEAD and the in-progress merge must be untouched.
[ "$(git rev-parse HEAD)" = "$(cat "$WORK/pre-head")" ] || fail "HEAD moved during repair (agent committed or reset)"
git rev-parse -q --verify MERGE_HEAD >/dev/null || fail "merge is no longer in progress (agent aborted or committed it)"

cut -f1 "$WORK/sides" > "$WORK/conflicted"
while IFS= read -r f; do git add -A -- "$f"; done < "$WORK/conflicted"

# Edits to any other tracked file would not be committed but would be tested by the gate: refuse them.
stray=$(git diff --name-only)
[ -z "$stray" ] || fail "edited files outside the conflict set: $(echo "$stray" | sed 's/.*/`&`/' | paste -sd, -)"

left=$(git diff --name-only --diff-filter=U)
[ -z "$left" ] || fail "still unmerged: $(echo $left)"

while IFS=$'\t' read -r f ours theirs; do
  if [ -e "$f" ] && grep -nE '^(<<<<<<<|>>>>>>>)( |$)' "$f" >/dev/null; then
    fail "conflict markers left in \`$f\`"
  fi
  now=$(git rev-parse -q --verify ":0:$f" || true)
  # No -X ours / -X theirs, no reverting the port: a resolution identical to one side is refused.
  if [ -n "$now" ] && [ "$now" = "$ours" ]; then fail "\`$f\` resolved by taking the port side wholesale"; fi
  if [ -n "$now" ] && [ "$now" = "$theirs" ]; then fail "\`$f\` resolved by taking the upstream side wholesale"; fi
done < "$WORK/sides"

# Nothing outside the conflicted files may change: no test edits, no safety/ edits, no drive-by fixes.
git ls-files -s | awk -F'\t' 'NR==FNR{c[$1]=1; next} !($2 in c)' "$WORK/conflicted" - | sort > "$WORK/stage0.after"
touched=$(diff <(cut -f2 "$WORK/stage0.before") <(cut -f2 "$WORK/stage0.after") | grep -E '^[<>]' | cut -c3- | sort -u || true)
changed=$(join -t$'\t' -1 2 -2 2 \
            <(awk -F'\t' '{print $1"\t"$2}' "$WORK/stage0.before" | sort -t$'\t' -k2) \
            <(awk -F'\t' '{print $1"\t"$2}' "$WORK/stage0.after" | sort -t$'\t' -k2) \
          | awk -F'\t' '$2 != $3 {print $1}' || true)
outside=$(printf '%s\n%s\n' "$touched" "$changed" | sed '/^$/d' | sort -u)
if [ -n "$outside" ]; then
  fail "files outside the conflict set were changed: $(echo "$outside" | sed 's/.*/`&`/' | paste -sd, -)"
fi

if [ -s "$report" ]; then
  setvar VERIFY failed
  exit 0
fi

git commit -q --no-edit
setvar VERIFY ok
