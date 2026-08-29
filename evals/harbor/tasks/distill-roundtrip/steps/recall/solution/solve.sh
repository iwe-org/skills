#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

FIXTURE=${IWE_EVAL_FIXTURE:-tail-dense}

eval_oracle_search_terms "$FIXTURE" gold | while IFS= read -r terms; do
  [ -n "$terms" ] || continue
  eval_iwe find --lexical "$terms" --limit 3 >/dev/null
  eval_stream_note "{\"type\":\"tool_use\",\"name\":\"Bash\",\"input\":{\"command\":\"iwe find --lexical \\\"$terms\\\" --limit 3\"}}"
done

eval_oracle_answers "$FIXTURE" gold >answers.txt
