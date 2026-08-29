#!/bin/sh
set -u

. "${IWE_EVAL_LIB:-/opt/iwe-evals/assert.sh}"

reward_init
ANSWERS=$EVAL_APP/answers.txt

note '# eight facts among seventy documents'
check answers_written test -s "$ANSWERS"
score recall_hit_rate "$(gold_fraction "$(bank_hits "$ANSWERS" 8)" 8)"
check consulted_memory memory_query_seen
check nothing_committed git_head_untouched

note '# and the one the repository contradicts'
check stale_not_trusted bank_answer_ok "$ANSWERS" 9

metric bank_hits "$(bank_hits "$ANSWERS" 8)"
answer stale_repeated bank_stale_repeated "$ANSWERS"
metric knowledge_documents "$(knowledge_count)"
metric find_calls "$(tool_calls_matching 'iwe find')"
metric retrieve_calls "$(tool_calls_matching 'iwe retrieve')"
metric tool_calls "$(tool_calls)"

cp "$ANSWERS" "$EVAL_VERIFIER/answers.txt" 2>/dev/null
reward_write
exit 0
