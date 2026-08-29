#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

FIXTURE=${IWE_EVAL_FIXTURE:-tail-dense}

# The store the distill step wrote is still here — the environment is shared
# across steps — and its transcript is not, which is the point: a fresh
# session answers from the documents alone. The questions are the fixture's
# gold questions, one per item the first half should have written.
eval_clean_run_state
rm -f "$EVAL_APP/answer.txt" "$EVAL_APP/answers.txt"
eval_seed_questions "$FIXTURE" gold

eval_note "recall step: $(eval_iwe find --filter '{ created: { $exists: true }, $key: { $nin: [MEMORY, queries] } }' -f keys --limit 0 | grep -c .) knowledge documents on disk"
eval_finish

rm -- "$0"
