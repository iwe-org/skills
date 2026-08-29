#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

SESSION=c0ffee11-0000-4000-8000-00000000dd01

eval_memory_init
eval_seed_transcript tail-phantom.jsonl "$SESSION"

# The agent reads the span with `session read`, which is the reader the flow
# uses anyway: it renders both halves of the exchange correctly, where the sed
# that used to write .eval/prior-session.md matched nothing and left it empty.
eval_note 'seeded the phantom-decision transcript'
eval_finish

rm -- "$0"
