#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

eval_memory_init
eval_seed_transcript tail-deploy.jsonl 8f1e6d20-0000-4000-8000-0000000000c1
eval_seed_transcript tail-busywork.jsonl 8f1e6d20-0000-4000-8000-0000000000c2
eval_release_dead_claims
eval_finish

rm -- "$0"
