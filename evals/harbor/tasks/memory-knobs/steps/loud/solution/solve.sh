#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

head -1 README.md

eval_sweep 7b3d9e40-0000-4000-8000-0000000000k1
eval_stream_note 'Agent tool: {"subagent_type":"distill"} run_in_background true'
