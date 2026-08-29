#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

SESSION=de000001-0000-4000-8000-00000000de01
FIXTURE=${IWE_EVAL_FIXTURE:-tail-dense}

eval_brief
eval_read_session "$SESSION" >/dev/null

# Every gold item, nothing else, and no write: the oracle is what a perfect
# proposal pass looks like, so the verifier's ceiling is 1.0 by construction.
# The proposals themselves are the fixture's oracle file.
eval_oracle_proposals "$FIXTURE" "$SESSION"
