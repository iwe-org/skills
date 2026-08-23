#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

head -1 README.md

SESSION=2c5a7e80-0000-4000-8000-0000000000d1
eval_sweep "$SESSION"
eval_stream_note 'Agent tool: {"subagent_type":"distill"} run_in_background true'
eval_seed_doc deploy-env-gate "$(date '+%Y-%m-%d %H:%M')" \
  "make deploy refuses to run without DEPLOY_ENV" \
  "bin/deploy.sh exits 3 with 'DEPLOY_ENV is unset (RB-417)'."
eval_complete_capture "$SESSION" deploy-env-gate
