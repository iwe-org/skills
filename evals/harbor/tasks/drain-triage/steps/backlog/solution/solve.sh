#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

KEEPER=5c93e2f0-0000-4000-8000-00000000ba03

eval_sweep "$KEEPER"
eval_stream_note 'Agent tool: {"subagent_type":"distill"} run_in_background true'
eval_stream_note 'Bash: {"command":"iwe internal claude job frontier"}'

eval_seed_captured_doc deploy-env-rb-417 '2026-08-13 09:12' "$KEEPER" claude \
  'Deploy fails two ways, exit 2 and exit 3' \
  'make deploy exits 2 while dist/releasekit.tar.gz is missing and exits 3 with "DEPLOY_ENV is unset (RB-417)" once the bundle is there. The valid DEPLOY_ENV values live only in ops/runbook-417.txt.'

# One batch read over the whole frontier, then a completion per session: the
# two busywork spans finish with nothing, the one that hit the gotcha carries
# the document it produced.
eval_triage_capture "$KEEPER" deploy-env-rb-417
