#!/bin/sh
set -u

. "${IWE_EVAL_LIB:-/opt/iwe-evals/assert.sh}"

reward_init
ANSWERS=$EVAL_APP/answers.txt

note '# what is achievable here with no memory at all'
check answers_written test -s "$ANSWERS"
check repo_fact_answered bank_answer_ok "$ANSWERS" 9
check nothing_committed git_head_untouched
check_not memory_was_enabled memory_enabled

note '# the baseline half of the memory-lift pair'
metric bank_hits "$(bank_hits "$ANSWERS" 8)"
answer recall_hit_rate_nonzero test "$(bank_hits "$ANSWERS" 8)" -gt 0
metric find_calls "$(tool_calls_matching 'iwe find')"
metric retrieve_calls "$(tool_calls_matching 'iwe retrieve')"
metric tool_calls "$(tool_calls)"

cp "$ANSWERS" "$EVAL_VERIFIER/answers.txt" 2>/dev/null
reward_write
exit 0
