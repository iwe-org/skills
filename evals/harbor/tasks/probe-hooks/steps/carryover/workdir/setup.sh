#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

eval_release_dead_claims
eval_watermark 7a1c9f20-0000-4000-8000-00000000ab01 0
eval_finish

rm -- "$0"
