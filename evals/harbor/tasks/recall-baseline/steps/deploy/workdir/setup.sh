#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

eval_workspace_remove
eval_clean_run_state
rm -f "$EVAL_APP/answer.txt"
eval_finish

rm -- "$0"
