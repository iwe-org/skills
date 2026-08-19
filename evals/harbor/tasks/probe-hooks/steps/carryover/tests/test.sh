#!/bin/sh
set -u

. "${IWE_EVAL_LIB:-/opt/iwe-evals/assert.sh}"

reward_init
SEEDED=7a1c9f20-0000-4000-8000-00000000ab01

shared_log_dir() {
  eval_session_dirs | while read -r dir; do
    [ -f "$dir/$SEEDED.jsonl" ] || continue
    n=$(find "$dir" -maxdepth 1 -name '*.jsonl' 2>/dev/null | grep -c .)
    [ "$n" -lt 2 ] || printf 'shared\n'
  done | grep -q shared
}

note '# question 4: does a later step see the previous step transcripts?'
answer step_log_dir_shared shared_log_dir
answer earlier_tail_reswept tail_claimed "$SEEDED"
answer distill_agent_launched agent_launched distill

metric session_dirs "$(eval_session_dirs | grep -c .)"
metric transcripts_total "$(eval_transcripts | grep -c .)"
metric watermark_after "$(mem_watermark "$SEEDED")"

score probe_recorded 1
reward_write
exit 0
