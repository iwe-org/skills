#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

SESSION=de000003-0000-4000-8000-00000000de03
FIXTURE=${IWE_EVAL_FIXTURE:-tail-dense}

eval_brief
eval_iwe retrieve -k MEMORY >/dev/null

# The run reads the span, then writes one document per gold fact through the
# CLI, in the starter policy's shape: a flat slug of the title, `created` from
# the read header's occurred stamp, `session` naming the record. The documents
# are the fixture's oracle file, so the recall step answers from exactly what a
# perfect first half would have written.
keys=$(eval_seed_oracle_docs "$FIXTURE" "$SESSION" "$(eval_occurred "$SESSION")")
offered=$(printf '%s\n' "$keys" | grep -c .)

# shellcheck disable=SC2086
eval_distill_session "$SESSION" "$offered" "" $keys
