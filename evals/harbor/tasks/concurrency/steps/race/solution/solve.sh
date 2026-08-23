#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

sed -n 's/^  target: //p' ops/runbook-417.txt

# Two turn boundaries landing at once: the job document's key is the only thing
# keeping them off each other's tails.
eval_sweep 8f1e6d20-0000-4000-8000-0000000000c1 &
eval_sweep 8f1e6d20-0000-4000-8000-0000000000c2 &
wait

eval_stream_note 'Agent tool: {"subagent_type":"distill"} run_in_background true'
eval_seed_doc deploy-env-gate "$(date '+%Y-%m-%d %H:%M')" \
  "make deploy refuses to run without DEPLOY_ENV" \
  "bin/deploy.sh exits 3 with 'DEPLOY_ENV is unset (RB-417)' until DEPLOY_ENV names a target ops/runbook-417.txt lists."
eval_complete_capture 8f1e6d20-0000-4000-8000-0000000000c1 deploy-env-gate
eval_complete_capture 8f1e6d20-0000-4000-8000-0000000000c2
