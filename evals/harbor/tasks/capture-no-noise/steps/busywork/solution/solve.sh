#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

sed -e 's/^msg=/greeting=/' -e 's/"\$msg"/"$greeting"/' bin/greet.sh >bin/greet.sh.next
mv bin/greet.sh.next bin/greet.sh
chmod +x bin/greet.sh
make test

SESSION=5b2d8e10-0000-4000-8000-00000000cd01
eval_sweep "$SESSION"
eval_stream_note 'Agent tool: {"subagent_type":"distill"} run_in_background true'
eval_complete_capture "$SESSION"
