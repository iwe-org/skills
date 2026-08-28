#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

head -1 README.md

eval_hook session-start
eval_stream_note "$(cat "$EVAL_NOTES/hook-session-start.out" 2>/dev/null)"
