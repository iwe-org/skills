#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

eval_memory_init
eval_clean_run_state
rm -f "$EVAL_APP/answer.txt"

eval_seed_doc deploy-target-freeze "2026-07-02 11:20" \
  "Release trains deploy to staging-blue while RB-417 is open" \
  "staging-green is frozen for the vendored-parser rewrite: deploying to it resets the rewrite baseline and costs the parser team a day of re-capture. Every release train goes to staging-blue until RB-417 is closed, even though ops/runbook-417.txt still lists both targets as valid."
eval_seed_doc deploy-env-gate "2026-07-02 11:24" \
  "make deploy refuses to run without DEPLOY_ENV" \
  "bin/deploy.sh exits 3 with 'DEPLOY_ENV is unset (RB-417)' and exits 2 until make build has written dist/releasekit.tar.gz."
eval_settle_watermarks
eval_finish

rm -- "$0"
