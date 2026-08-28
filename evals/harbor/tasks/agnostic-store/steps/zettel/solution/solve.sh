#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

make build
DEPLOY_ENV=staging-blue make deploy
cat .deploy-receipt

SESSION=1a7f5b30-0000-4000-8000-0000000000b1

# The distill run reads the policy and the store before it proposes anything,
# then writes this store's shape — not one of its own.
eval_brief
eval_iwe retrieve -k MEMORY >/dev/null
eval_iwe schema >/dev/null
eval_iwe create --template zettel --strict \
  --var title="make deploy refuses to run without DEPLOY_ENV" \
  --var body="bin/deploy.sh exits 3 with 'DEPLOY_ENV is unset (RB-417)' and exits 4 on a target ops/runbook-417.txt does not list. It also exits 2 until make build has written dist/releasekit.tar.gz." >/dev/null
eval_distill_session "$SESSION" 2 "A refactor nobody asked for" \
  notes/make-deploy-refuses-to-run-without-deploy-env
