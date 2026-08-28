#!/bin/sh
set -u

. "${IWE_EVAL_LIB:-/opt/iwe-evals/assert.sh}"

reward_init
SESSION=bb000001-0000-4000-8000-00000000ee01

note '# it read'
check memory_is_on memory_enabled

note '# and wrote nothing at all'
check no_documents_written test "$(knowledge_count)" -eq 0
check nothing_captured test "$(captured_count)" -eq 0
check no_session_record session_untouched "$SESSION"
check no_watermark_moved test "$(mem_watermark "$SESSION")" -eq 0
check store_untouched store_is_untouched
check session_still_pending session_listed "$SESSION"
check no_subagent_spawned no_subagent_spawned
check nothing_committed git_head_untouched

metric memory_documents "$(knowledge_count)"
metric session_records "$(session_records)"
answer read_the_span stream_has 'session read'

reward_write
exit 0
