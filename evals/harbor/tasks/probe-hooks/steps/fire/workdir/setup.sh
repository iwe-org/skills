#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

eval_memory_init --queries
eval_marker_hooks
eval_seed_doc release-bundle-format "$(date '+%Y-%m-%d %H:%M')" \
  "Release bundles are tarballs" \
  "make build writes dist/releasekit.tar.gz and bin/deploy.sh refuses to run without it. Seeded by the probe so the SessionStart injector has something to index."
eval_seed_transcript tail-deploy.jsonl 7a1c9f20-0000-4000-8000-00000000ab01
eval_finish

rm -- "$0"
