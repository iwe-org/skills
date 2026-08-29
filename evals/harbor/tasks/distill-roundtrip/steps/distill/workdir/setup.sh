#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

SESSION=de000003-0000-4000-8000-00000000de03
FIXTURE=${IWE_EVAL_FIXTURE:-tail-dense}

eval_memory_init
# The whole digest fits one default window, where max_proposals_per_read
# would cap a compliant run below the gold count; smaller windows make the
# read span several and exercise the multi-window flow the plan calls for.
eval_memory_set chunk_chars 3500
eval_seed_transcript "$FIXTURE.jsonl" "$SESSION"

eval_note "seeded the labelled $FIXTURE transcript; the recall step answers from what this step writes"
eval_finish

rm -- "$0"
