#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

eval_iwe find --lexical "deploy target" --limit 5 >/dev/null
eval_stream_note '{"type":"tool_use","name":"Bash","input":{"command":"iwe find --lexical \"deploy target\" --limit 5"}}'

make build
DEPLOY_ENV=staging-blue make deploy

printf 'staging-blue, because staging-green is frozen for the vendored-parser rewrite until RB-417 closes.\n' >answer.txt
