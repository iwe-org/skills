#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

ls bin/ | grep -c '\.sh$' >count.txt

SESSION=9d2f4c60-0000-4000-8000-0000000000f1

# Not a workspace: every hook is a no-op.
eval_hook_from_settings Stop "$SESSION"

# A workspace, but still no MEMORY.md: same silence.
( cd "$EVAL_APP" && iwe init --defaults >/dev/null 2>&1 ) || true
eval_hook_from_settings Stop "$SESSION"
eval_hook_from_settings SessionStart "$SESSION"
