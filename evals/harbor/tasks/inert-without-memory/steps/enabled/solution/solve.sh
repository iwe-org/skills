#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

head -1 ops/runbook-417.txt

SESSION=9d2f4c60-0000-4000-8000-0000000000f1
eval_seed_transcript tail-deploy.jsonl "$SESSION"
eval_brief
eval_seed_captured_doc deploy-env-gate "$(date '+%Y-%m-%d %H:%M')" "$SESSION" \
  "make deploy refuses to run without DEPLOY_ENV" \
  "bin/deploy.sh exits 3 with 'DEPLOY_ENV is unset (RB-417)'."
eval_distill_session "$SESSION" 1 "" deploy-env-gate
