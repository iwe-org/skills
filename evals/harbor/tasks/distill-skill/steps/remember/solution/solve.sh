#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

eval_iwe retrieve -k MEMORY >/dev/null

eval_iwe create --template gotcha --strict \
  --var title="A failed deploy leaves a stale .deploy-receipt" \
  --var body="The nightly smoke job reads .deploy-receipt to decide what it is smoking, and a failed make deploy leaves the previous target's receipt in place, so the smoke job reports green against a deploy that never happened. Delete .deploy-receipt before every retry." \
  --var session="oracle" >/dev/null

eval_iwe update -k decisions/deploy-target-freeze --content '# Release trains deploy to staging-blue while RB-417 is open

staging-green is frozen for the vendored-parser rewrite: deploying to it resets the rewrite baseline. Every release train goes to staging-blue until RB-417 is closed, even though ops/runbook-417.txt lists both targets as valid. The freeze ends on 2026-09-01, when RB-417 closes and staging-green goes back into rotation.' >/dev/null

for key in $(eval_iwe find --filter '{ type: { $in: [gotcha, decision] } }' -f keys --limit 0); do
  eval_iwe attach -k "$key" --to daily --quiet >/dev/null 2>&1 || true
done
