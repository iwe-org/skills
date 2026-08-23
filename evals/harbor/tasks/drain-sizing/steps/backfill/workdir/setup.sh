#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

SESSION=7c1af940-0000-4000-8000-00000000ab01

eval_memory_init
eval_seed_transcript tail-backfill.jsonl "$SESSION"
# What this span costs at the live-capture budget. A backfill has to beat it.
eval_record_chunk_baseline "$SESSION" 10000
eval_finish

rm -- "$0"
