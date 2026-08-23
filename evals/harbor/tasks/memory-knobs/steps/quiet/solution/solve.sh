#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

sed -n 's/^  target: //p' ops/runbook-417.txt

# 85 lines is well under this store's 400-line threshold: the sweep imports
# nothing, here or anywhere.
eval_sweep 7b3d9e40-0000-4000-8000-0000000000k1
