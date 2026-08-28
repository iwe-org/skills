#!/bin/sh
set -u

. "${IWE_EVAL_LIB:-/opt/iwe-evals/assert.sh}"

reward_init

note '# the count is information, and it is there'
check memory_is_on memory_enabled
check index_injected stream_has '<iwe-memory>'
check backlog_counted stream_has 'are not distilled'
check backlog_names_the_skill stream_has '/iwe:distill'

note '# and the reminder fired once, on a cold window'
check reminder_shown stream_has 'first natural pause'
check reminder_stamped test -f "$EVAL_STATE/.reminded"
check reminder_stamp_ignored reminder_stamp_ignored

note '# nothing was captured for showing a count'
check nothing_captured test "$(captured_count)" -eq 0
check no_session_records test "$(session_records)" -eq 0
check nothing_committed git_head_untouched

metric pending_tails "$(pending_tails)"
answer sessionstart_fired marker_fired SessionStart

reward_write
exit 0
