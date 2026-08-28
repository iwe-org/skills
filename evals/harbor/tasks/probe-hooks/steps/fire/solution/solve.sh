#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

SEEDED=7a1c9f20-0000-4000-8000-00000000ab01

head -1 README.md
printf 'CLAUDE_CODE_SESSION_ID=%s\n' "${CLAUDE_CODE_SESSION_ID:-unset}"

eval_hook session-start
eval_stream_note "$(cat "$EVAL_NOTES/hook-session-start.out" 2>/dev/null)"
eval_stream_note "CLAUDE_CODE_SESSION_ID=${CLAUDE_CODE_SESSION_ID:-unset}"
eval_session list >"$EVAL_NOTES/session-list.out" 2>&1 || :
eval_note "the listing saw $SEEDED"
