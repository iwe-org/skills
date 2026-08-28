#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

# The window is already open from the previous step's reminder. Step log
# directories are not shared, so the backlog is seeded again; the stamp under
# .iwe/claude/ is what carries over, and it is the thing under test.
for _s in cc000001-0000-4000-8000-00000000ff01 \
          cc000002-0000-4000-8000-00000000ff02 \
          cc000003-0000-4000-8000-00000000ff03; do
  eval_seed_transcript tail-deploy.jsonl "$_s"
done
eval_session_dirs | sort -u | while read -r _dir; do
  for _s in cc000001-0000-4000-8000-00000000ff01 \
            cc000002-0000-4000-8000-00000000ff02 \
            cc000003-0000-4000-8000-00000000ff03; do
    [ ! -f "$_dir/$_s.jsonl" ] || touch -t 202608190800 "$_dir/$_s.jsonl"
  done
done
mkdir -p "$EVAL_STATE"
[ -f "$EVAL_STATE/.reminded" ] ||
  printf '%s\n' "$(date '+%Y-%m-%d %H:%M')" >"$EVAL_STATE/.reminded"

# What the verifier compares against: a stamp written now cannot be a literal in
# a test, and the point of the check is that this step did not move it.
mkdir -p "$EVAL_NOTES"
cp "$EVAL_STATE/.reminded" "$EVAL_NOTES/reminded.before"

# The container gives each step its own agent log; the offline simulation shares
# one directory across a task's steps, so the previous step's injection would
# still be in the stream this step asserts on.
: >"$EVAL_LOGS/agent/claude-code.txt" 2>/dev/null || :
eval_note 'the reminder window is already open'
eval_finish

rm -- "$0"
