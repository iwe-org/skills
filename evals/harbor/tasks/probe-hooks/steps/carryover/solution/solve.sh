#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

ls ops/

eval_seed_transcript tail-busywork.jsonl 7a1c9f20-0000-4000-8000-00000000ab02
eval_session list --all >"$EVAL_NOTES/session-list.out" 2>&1 || :
