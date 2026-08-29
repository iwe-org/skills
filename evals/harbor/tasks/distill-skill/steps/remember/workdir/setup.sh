#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

SESSION=dd000001-0000-4000-8000-00000000cc01

eval_memory_init --typed

# The exchange happens in this session, and nothing on disk is its transcript:
# the items come out of the live conversation. `session complete` refuses an id
# it has never heard of, so the record is what makes the ledger entry legal.
eval_seed_session_record "$SESSION"
eval_seed_typed_doc decision decisions/deploy-target-freeze "2026-07-02 11:20" \
  "Release trains deploy to staging-blue while RB-417 is open" \
  "staging-green is frozen for the vendored-parser rewrite: deploying to it resets the rewrite baseline. Every release train goes to staging-blue until RB-417 is closed, even though ops/runbook-417.txt lists both targets as valid."
eval_settle_watermarks
eval_finish

rm -- "$0"
