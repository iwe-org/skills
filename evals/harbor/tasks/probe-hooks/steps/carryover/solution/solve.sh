#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

ls ops/

eval_seed_transcript tail-busywork.jsonl 7a1c9f20-0000-4000-8000-00000000ab02
eval_stream_note 'Agent tool: {"subagent_type":"distill"} run_in_background true'
eval_watermark 7a1c9f20-0000-4000-8000-00000000ab01 85
eval_release_dead_claims
