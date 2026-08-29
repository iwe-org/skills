#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

SESSION=c0ffee11-0000-4000-8000-00000000dd01

eval_brief

# The one thing the user confirmed: the two deploy gates. The retry budget was
# a recommendation the user answered with "leave deploy.sh alone", so it is not
# a decision and no document says it was.
eval_seed_captured_doc deploy-gates-in-ci "$(date '+%Y-%m-%d %H:%M')" "$SESSION" \
  "make deploy has two undocumented gates" \
  "bin/deploy.sh exits 3 with 'DEPLOY_ENV is unset (RB-417)' until DEPLOY_ENV names a target listed in ops/runbook-417.txt, and exits 2 until make build has written dist/releasekit.tar.gz. Nothing in the repository records either exit code, which is why CI kept failing where a local run succeeded."

eval_distill_session "$SESSION" 2 "Raise RETRY_BUDGET to 10" deploy-gates-in-ci
