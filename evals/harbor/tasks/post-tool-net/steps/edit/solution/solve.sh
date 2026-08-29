#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

# The oracle writes the document the way an agent using its editing tools
# would — sloppy form and all — and then fires the net exactly as
# settings.json declares it. What lands is what the net leaves behind.
cat >"$EVAL_APP/notes/handoff.md" <<'DOC'
---
created: "2026-08-20 09:00"
---

#  Handover   note

Deploying releasekit, as of the last release:

*  the deploy target is read from `ops/runbook-417.txt`
*  `make build` has to have written `dist/releasekit.tar.gz`
*  `make deploy` exits 3 when `DEPLOY_ENV` is unset

Runbook steps:

1) check the target is listed
3) run `make deploy`
DOC

eval_post_tool_write notes/handoff.md

printf '# fixed: targets.txt -> runbook-417.txt\n' >>"$EVAL_APP/bin/handoff-check.sh"
eval_post_tool_write bin/handoff-check.sh

eval_note 'edited the note and the script, then fired the net over each'
eval_finish
