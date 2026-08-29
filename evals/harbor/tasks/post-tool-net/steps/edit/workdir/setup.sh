#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

eval_memory_init

# A store document in deliberately non-canonical form: doubled spaces after the
# heading marker, `*` bullets where this store writes `-`, and ordered items
# numbered 1) 3). Whatever the agent edits, the net has to leave it canonical.
mkdir -p "$EVAL_APP/notes"
cat >"$EVAL_APP/notes/handoff.md" <<'DOC'
---
created: "2026-08-20 09:00"
---

#  Handover   note

Deploying releasekit, as of the last release:

*  the deploy target is read from `ops/targets.txt`
*  `make build` has to have written `dist/releasekit.tar.gz`

Runbook steps:

1) check the target is listed
3) run `make deploy`
DOC

# A file the net does not own, in equally sloppy shape. It must come out
# byte-for-byte as seeded plus the one appended line.
cat >"$EVAL_APP/bin/handoff-check.sh" <<'DOC'
#!/bin/sh
#  checks    the handover note is current
set -eu
grep -q 'runbook-417' notes/handoff.md
DOC
chmod +x "$EVAL_APP/bin/handoff-check.sh"

eval_note 'seeded a non-canonical store document and a shell script beside it'
eval_finish

rm -- "$0"
