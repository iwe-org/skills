#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

ls ops/

eval_stream_note 'Agent tool: {"subagent_type":"distill"} run_in_background true'
SESSION=5b8e2d40-0000-4000-8000-00000000cd01
eval_seed_transcript tail-deploy.jsonl "$SESSION"
eval_settle_watermarks
eval_release_dead_claims
