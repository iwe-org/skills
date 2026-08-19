#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

eval_memory_init
eval_seed_transcript tail-deploy.jsonl 2c5a7e80-0000-4000-8000-0000000000d1

# A capture that started long ago and never came back: its chunk is here with a
# long-expired claim on it, the watermark never moved, and it covers a fraction
# of what the transcript now holds.
eval_watermark 2c5a7e80-0000-4000-8000-0000000000d1 0
eval_seed_capture_chunk 2c5a7e80-0000-4000-8000-0000000000d1 "2020-01-01 09:00" 0 12 \
  "[user]
a digest from a capture that died before it wrote anything"
eval_finish

rm -- "$0"
