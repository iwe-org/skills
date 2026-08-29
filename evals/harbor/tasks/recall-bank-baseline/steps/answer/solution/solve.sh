#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

# Nothing but the repository to go on: only the ninth question has an answer.
grep -n 'exit 3' bin/deploy.sh >/dev/null

cat >answers.txt <<'EOF'
1. Not recorded in the repository; ops/runbook-417.txt lists staging-blue and staging-green without preference.
2. Not recorded in the repository.
3. Not recorded in the repository.
4. Not recorded in the repository.
5. Not recorded in the repository.
6. Not recorded in the repository.
7. Not recorded in the repository.
8. Not recorded in the repository; bin/test.sh has no host restriction.
9. Exit 3 — bin/deploy.sh: "DEPLOY_ENV is unset (RB-417)".
EOF
