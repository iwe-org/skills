#!/bin/sh
set -u

. "${IWE_EVAL_LIB:-/opt/iwe-evals/assert.sh}"

reward_init
SESSION=7b3d9e40-0000-4000-8000-0000000000k1

no_chunk_directory() {
  [ ! -d "$EVAL_APP/sessions/$SESSION" ]
}

note '# a threshold no transcript reaches means no capture at all'
check no_chunks test "$(pending_chunks)" -eq 0
check nothing_imported no_chunk_directory
check no_watermark test "$(mem_watermark "$SESSION")" -eq 0
check_not blocked_the_session stream_has '"decision": "block"'
check memory_is_still_on memory_enabled
check nothing_committed git_head_untouched

metric threshold "$(memory_knob sweep_threshold_lines)"
metric transcript_lines "$(eval_longest_tail)"

reward_write
exit 0
