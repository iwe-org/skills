#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

eval_memory_init --queries

# Small chunks on purpose: the seeded tail imports as several, so this task
# exercises the queue loop — next, curate, complete, next — rather than a
# single pass.
eval_memory_set chunk_chars 3000

eval_clean_run_state
eval_finish

rm -- "$0"
