#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

SESSION=de000002-0000-4000-8000-00000000de02
FIXTURE=${IWE_EVAL_FIXTURE:-tail-dense}

eval_memory_init
# The whole digest fits one default window, where max_proposals_per_read
# would cap a compliant run below the gold count; smaller windows make the
# read span several and exercise the multi-window flow the plan calls for.
eval_memory_set chunk_chars 3500
eval_seed_transcript "$FIXTURE.jsonl" "$SESSION"

# One fact the session re-establishes is already here, from an earlier
# session: the run has to sharpen this document, not write a second one.
eval_seed_doc deploy-target-freeze "2026-07-02 11:20" \
  "Release trains deploy to staging-blue while RB-417 is open" \
  "staging-green is frozen for the vendored-parser rewrite: deploying to it resets the rewrite baseline. Every release train goes to staging-blue until RB-417 is closed, even though ops/runbook-417.txt lists both targets as valid."

eval_note "seeded the labelled $FIXTURE transcript and one document it overlaps"
eval_finish

rm -- "$0"
