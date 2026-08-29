#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

eval_memory_init
eval_seed_doc release-bundle-format "$(date '+%Y-%m-%d %H:%M')" \
  "Release bundles are tarballs" \
  "make build writes dist/releasekit.tar.gz and bin/deploy.sh refuses to run without it."

# Three sessions nobody has read, all of them settled rather than live.
for _s in cc000001-0000-4000-8000-00000000ff01 \
          cc000002-0000-4000-8000-00000000ff02 \
          cc000003-0000-4000-8000-00000000ff03; do
  eval_seed_transcript tail-deploy.jsonl "$_s"
done
eval_session_dirs | sort -u | while read -r _dir; do
  for _s in cc000001-0000-4000-8000-00000000ff01 \
            cc000002-0000-4000-8000-00000000ff02 \
            cc000003-0000-4000-8000-00000000ff03; do
    [ ! -f "$_dir/$_s.jsonl" ] || touch -t 202608190800 "$_dir/$_s.jsonl"
  done
done
rm -f "$EVAL_STATE/.reminded"
eval_marker_hooks
eval_finish

rm -- "$0"
