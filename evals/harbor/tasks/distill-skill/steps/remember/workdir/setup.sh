#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

eval_memory_init --typed
eval_seed_typed_doc decision decisions/deploy-target-freeze "2026-07-02 11:20" \
  "Release trains deploy to staging-blue while RB-417 is open" \
  "staging-green is frozen for the vendored-parser rewrite: deploying to it resets the rewrite baseline. Every release train goes to staging-blue until RB-417 is closed, even though ops/runbook-417.txt lists both targets as valid."
eval_settle_watermarks
eval_finish

rm -- "$0"
