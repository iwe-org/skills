#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

make build
DEPLOY_ENV=staging-blue make deploy
make test

cat >>ops/runbook-417.txt <<'RUNBOOK'

Failure modes

  exit 2  dist/releasekit.tar.gz is missing — run make build first.
  exit 3  DEPLOY_ENV is unset — export one of the targets above.
  exit 4  DEPLOY_ENV names a target this file does not list.
RUNBOOK

SESSION=6e3a4b90-0000-4000-8000-00000000ba01
eval_seed_transcript tail-deploy.jsonl "$SESSION"
eval_sweep "$SESSION"
eval_stream_note 'Agent tool: {"subagent_type":"distill"} run_in_background true'

# What the capture agent writes, in the shape the starter policy describes:
# one date — the chunk's occurred stamp, stamped as created — plus session from
# the chunk header, origin judged: the gate was uncovered by the work, the
# parser rule was stated by a person.
NOW=$(date '+%Y-%m-%d %H:%M')
eval_seed_captured_doc deploy-env-gate "$NOW" "$SESSION" claude \
  "make deploy refuses to run without DEPLOY_ENV" \
  "bin/deploy.sh exits 3 with 'DEPLOY_ENV is unset (RB-417)' and exits 4 on a target ops/runbook-417.txt does not list. It also exits 2 until make build has written dist/releasekit.tar.gz, so a clean checkout needs make build and DEPLOY_ENV=staging-blue together."
eval_seed_captured_doc vendored-parser "$NOW" "$SESSION" user \
  "The parser under src/parser stays vendored" \
  "Replacing src/parser with a package-registry dependency has been proposed and reverted twice: the registry copy drops the comment handling that bin/test.sh asserts on line 25. Do not add it to a dependency manifest."
eval_complete_capture "$SESSION" deploy-env-gate vendored-parser
