#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

eval_memory_init

# This store wants a far longer tail than any transcript here before it spends
# a model pass, and keeps captures small when it does.
eval_memory_set sweep_threshold_lines 400
eval_memory_set max_items_per_chunk 2

eval_seed_transcript tail-deploy.jsonl 7b3d9e40-0000-4000-8000-0000000000k1
eval_finish

rm -- "$0"
