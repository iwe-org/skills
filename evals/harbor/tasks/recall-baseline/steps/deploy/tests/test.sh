#!/bin/sh
set -u

. "${IWE_EVAL_LIB:-/opt/iwe-evals/assert.sh}"

reward_init

answer_reads() {
  grep -qiE "$1" "$EVAL_APP/answer.txt" 2>/dev/null
}

note '# what is achievable here with no memory at all'
check deploy_succeeded deploy_target_known
check answer_written test -s "$EVAL_APP/answer.txt"
check nothing_committed git_head_untouched
check_not memory_was_enabled memory_enabled

note '# the baseline half of the memory-lift pair'
answer answer_target answer_reads 'staging-blue'
answer answer_reason answer_reads 'parser|frozen|freeze|rewrite|RB-417'
metric deploy_attempts "$(deploy_attempts)"
metric blind_attempts "$(deploy_blind_attempts)"

reward_write
exit 0
