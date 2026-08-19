#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

# The policy arrives now. The transcript from the previous step was never
# read, and no watermark was ever written, so it is still capturable whole.
# It is seeded again because step log directories are not shared (the probe's
# step_log_dir_shared = 0); on a real machine it never left the disk.
eval_memory_init
eval_seed_transcript tail-deploy.jsonl 9d2f4c60-0000-4000-8000-0000000000f1
eval_finish

rm -- "$0"
