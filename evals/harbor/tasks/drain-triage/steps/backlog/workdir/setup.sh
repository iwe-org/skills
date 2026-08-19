#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

# Two sessions of the same kind of busywork and one that hit the planted
# gotcha: a backlog whose signal sits in one session out of three.
eval_memory_init
eval_seed_transcript tail-busywork.jsonl 3a71c0d0-0000-4000-8000-00000000ba01
eval_seed_transcript tail-busywork.jsonl 4b82d1e0-0000-4000-8000-00000000ba02
eval_seed_transcript tail-deploy.jsonl 5c93e2f0-0000-4000-8000-00000000ba03
eval_finish

rm -- "$0"
