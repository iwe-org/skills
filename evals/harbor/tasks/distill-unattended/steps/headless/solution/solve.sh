#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

SESSION=bb000001-0000-4000-8000-00000000ee01

# Reading is the whole of what an unattended run may do. It writes nothing and
# records nothing, so the span comes back next time a human is in front of it.
eval_brief
eval_read_session "$SESSION" >/dev/null
eval_session list >>"$EVAL_NOTES/session-list.out" 2>&1 || :
eval_note 'unattended: read and listed, wrote nothing'
