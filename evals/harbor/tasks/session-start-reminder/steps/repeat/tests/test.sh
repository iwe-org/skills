#!/bin/sh
set -u

. "${IWE_EVAL_LIB:-/opt/iwe-evals/assert.sh}"

reward_init

note '# the count still shows'
check index_injected stream_has '<iwe-memory>'
check backlog_counted stream_has 'are not distilled'

# The stamp is the half that survives a model run: the hook writes it whenever
# it reminds, so an unmoved stamp is the reminder not repeating.
note '# and the reminder does not repeat inside its window'
check reminder_stamp_unchanged reminder_stamp_unchanged
check_not reminder_repeated stream_has 'first natural pause'
check nothing_captured test "$(captured_count)" -eq 0
check nothing_committed git_head_untouched

metric pending_tails "$(pending_tails)"

reward_write
exit 0
