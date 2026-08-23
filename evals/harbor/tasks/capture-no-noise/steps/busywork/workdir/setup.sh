#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

eval_memory_init
eval_seed_transcript tail-busywork.jsonl 5b2d8e10-0000-4000-8000-00000000cd01
eval_finish

rm -- "$0"
