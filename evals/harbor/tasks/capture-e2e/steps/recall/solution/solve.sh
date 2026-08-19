#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

eval_iwe find --lexical "deploy DEPLOY_ENV" --limit 5 >/dev/null
eval_stream_note '{"type":"tool_use","name":"Bash","input":{"command":"iwe find --lexical deploy --limit 5"}}'

make build
DEPLOY_ENV=staging-blue make deploy
