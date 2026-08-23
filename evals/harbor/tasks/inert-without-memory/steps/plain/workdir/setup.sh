#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

# Two ways to be memory-less, both live in this step: no workspace marker at
# all, and — after the sweep has had its chance — a workspace with no MEMORY.md.
eval_workspace_remove
eval_seed_transcript tail-deploy.jsonl 9d2f4c60-0000-4000-8000-0000000000f1
rm -f "$EVAL_APP/count.txt"
eval_finish

rm -- "$0"
