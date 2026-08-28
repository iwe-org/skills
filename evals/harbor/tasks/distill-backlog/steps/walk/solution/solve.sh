#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

DEPLOY=aa000001-0000-4000-8000-00000000ba01

eval_session list >"$EVAL_APP/.eval/session-list.out" 2>&1 || :
eval_brief

eval_seed_captured_doc deploy-env-and-bundle "$(date '+%Y-%m-%d %H:%M')" "$DEPLOY" \
  "make deploy needs DEPLOY_ENV and a built bundle" \
  "bin/deploy.sh exits 3 with 'DEPLOY_ENV is unset (RB-417)' until DEPLOY_ENV names a target from ops/runbook-417.txt, and exits 2 until make build has written dist/releasekit.tar.gz."

eval_distill_session "$DEPLOY" 3 "The greet.sh rename" deploy-env-and-bundle

# The rest is stale and low-signal: marked seen rather than read. The live
# conversation is refused by the command itself.
eval_adopt
