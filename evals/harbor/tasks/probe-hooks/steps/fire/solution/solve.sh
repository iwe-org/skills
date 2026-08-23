#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

SEEDED=7a1c9f20-0000-4000-8000-00000000ab01

head -1 README.md

eval_stream_note '<iwe-memory> index injected at session start. The `queries` document is this store'"'"'s query cookbook.'
eval_stream_note 'Agent tool: {"subagent_type":"distill"} run_in_background true'
eval_sweep "$SEEDED"
eval_seed_doc probe-deploy-gate "$(date '+%Y-%m-%d %H:%M')" \
  "make deploy needs DEPLOY_ENV and a built bundle" \
  "bin/deploy.sh exits 3 with 'DEPLOY_ENV is unset (RB-417)' until DEPLOY_ENV names a target from ops/runbook-417.txt, and exits 2 until make build has written dist/releasekit.tar.gz."
eval_complete_capture "$SEEDED" probe-deploy-gate
