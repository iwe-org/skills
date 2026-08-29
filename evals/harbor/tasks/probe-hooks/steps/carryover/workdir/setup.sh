#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

eval_finish

rm -- "$0"
