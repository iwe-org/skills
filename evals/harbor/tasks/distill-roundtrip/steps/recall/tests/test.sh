#!/bin/sh
set -u

. "${IWE_EVAL_LIB:-/opt/iwe-evals/assert.sh}"

reward_init
FIXTURE=${IWE_EVAL_FIXTURE:-tail-dense}
ANSWERS=$EVAL_APP/answers.txt
QUESTIONS=$(bank_question_count "$FIXTURE" gold)

note "# the second half: answered from the documents alone ($FIXTURE, $QUESTIONS questions)"
check answers_written test -s "$ANSWERS"
score roundtrip_recall "$(gold_fraction "$(bank_hits "$ANSWERS" "$QUESTIONS" "$FIXTURE")" "$QUESTIONS")"
check consulted_memory memory_query_seen
check nothing_committed git_head_untouched

metric bank_hits "$(bank_hits "$ANSWERS" "$QUESTIONS" "$FIXTURE")"
metric bank_questions "$QUESTIONS"
metric knowledge_documents "$(knowledge_count)"
metric find_calls "$(tool_calls_matching 'iwe find')"
metric retrieve_calls "$(tool_calls_matching 'iwe retrieve')"
metric tool_calls "$(tool_calls)"

cp "$ANSWERS" "$EVAL_VERIFIER/answers.txt" 2>/dev/null
reward_write
exit 0
