#!/bin/sh
set -u

. "${IWE_EVAL_LIB:-/opt/iwe-evals/assert.sh}"

reward_init
SESSION=9d2f4c60-0000-4000-8000-0000000000f1

hooks_printed_nothing() {
  [ ! -s "$EVAL_NOTES/hook-settings.out" ]
}

hook_error_free() {
  ! eval_all_text | grep -qE 'command not found|hook error|hook failed|Permission denied'
}

no_mechanical_documents() {
  [ ! -d "$EVAL_APP/sessions" ]
}

check task_completed test "$(cat "$EVAL_APP/count.txt" 2>/dev/null)" = "4"
check_not memory_was_enabled memory_enabled
check nothing_was_written no_mechanical_documents
check no_watermark_exists test "$(mem_watermark "$SESSION")" -eq 0
check_not blocked_the_session stream_has '"decision": "block"'
check_not launched_a_memory_agent agent_launched distill
check hooks_stayed_quiet hooks_printed_nothing
check no_hook_output_in_the_session hook_error_free
check nothing_committed git_head_untouched

reward_write
exit 0
