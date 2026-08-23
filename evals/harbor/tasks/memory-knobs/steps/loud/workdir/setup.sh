#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

# Same store, one knob lowered: now the seeded tail is worth a pass. The tail
# is seeded again because step log directories are not shared (the probe's
# step_log_dir_shared = 0); in a live session it never left the disk.
eval_memory_set sweep_threshold_lines 40
eval_seed_transcript tail-deploy.jsonl 7b3d9e40-0000-4000-8000-0000000000k1
eval_finish

rm -- "$0"
