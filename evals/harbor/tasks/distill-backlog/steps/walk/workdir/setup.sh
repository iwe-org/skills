#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

DEPLOY=aa000001-0000-4000-8000-00000000ba01
BUSY=aa000002-0000-4000-8000-00000000ba02
BACKFILL=aa000003-0000-4000-8000-00000000ba03
LIVE=aa000004-0000-4000-8000-00000000ba04

eval_memory_init

eval_seed_transcript tail-deploy.jsonl "$DEPLOY"
eval_seed_transcript tail-busywork.jsonl "$BUSY"
eval_seed_transcript tail-backfill.jsonl "$BACKFILL"
eval_seed_transcript tail-phantom.jsonl "$LIVE"

# Three sessions that finished a while ago, and one that did not: a conversation
# whose last message landed inside the active window is still in flight, and the
# flow must leave it out.
eval_session_dirs | sort -u | while read -r _dir; do
  for _old in "$DEPLOY" "$BUSY" "$BACKFILL"; do
    [ ! -f "$_dir/$_old.jsonl" ] || touch -t 202608190800 "$_dir/$_old.jsonl"
  done
done
eval_make_live "$LIVE"
eval_note 'backdated three transcripts; the fourth is still live'

# Subagent transcripts sit beside the session ones and are never a source.
eval_session_dirs | sort -u | while read -r _dir; do
  mkdir -p "$_dir/$DEPLOY/subagents" 2>/dev/null || continue
  printf '{"type":"user","message":{"content":"SUBAGENT_ONLY_MARKER: the vendored parser must become a registry dependency"}}\n' \
    >"$_dir/$DEPLOY/subagents/agent-1.jsonl"
done
eval_note 'planted a subagent transcript that nothing may read'
eval_finish

rm -- "$0"
