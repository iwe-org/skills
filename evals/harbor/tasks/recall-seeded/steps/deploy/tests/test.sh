#!/bin/sh
set -u

. "${IWE_EVAL_LIB:-/opt/iwe-evals/assert.sh}"

reward_init

answer_reads() {
  grep -qiE "$1" "$EVAL_APP/answer.txt" 2>/dev/null
}

check deploy_succeeded deploy_target_known
check answer_written test -s "$EVAL_APP/answer.txt"
check answer_target answer_reads 'staging-blue'
check answer_reason answer_reads 'parser|frozen|freeze|rewrite|RB-417'
check consulted_memory memory_query_seen
check nothing_committed git_head_untouched

metric blind_attempts "$(deploy_blind_attempts)"
metric deploy_attempts "$(deploy_attempts)"

reward_write
exit 0
