#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

eval_clean_run_state
eval_release_dead_claims
eval_finish

rm -- "$0"
