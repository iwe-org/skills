#!/bin/sh
set -u

. "${IWE_EVAL_LIB:-/opt/iwe-evals/assert.sh}"

reward_init
has_pending_chunk() {
  [ "$(pending_chunks)" -ge 1 ]
}
wait_for 30 has_pending_chunk
SESSION=7b3d9e40-0000-4000-8000-0000000000k1

chunks_under_the_session_prefix() {
  [ -f "$EVAL_CHUNKS/$SESSION/000000.md" ] && [ ! -d "$EVAL_APP/sessions/$SESSION" ]
}

session_under_the_sessions_prefix() {
  [ -f "$EVAL_APP/sessions/$SESSION.md" ]
}

item_cap_travelled_with_the_chunk() {
  _cap=$(sed -n 's/^max_items: //p' "$EVAL_CHUNKS/$SESSION/000000.md" 2>/dev/null | head -1)
  [ "${_cap:-0}" = "2" ]
}

chunk_names_its_span() {
  grep -q '^covers_from: 0$' "$EVAL_CHUNKS/$SESSION/000000.md" 2>/dev/null
}

note '# the machinery writes records under sessions/ and chunks under .iwe/claude-sessions/'
check chunks_written_under_the_session chunks_under_the_session_prefix
check session_written_under_sessions session_under_the_sessions_prefix
check chunk_carries_its_start_line chunk_names_its_span

note '# and the numbers the policy sets are the ones it applies'
check item_cap_honored item_cap_travelled_with_the_chunk
check queue_is_visible test "$(chunk_files | wc -l | tr -d ' ')" -ge 1
check nothing_committed git_head_untouched

metric threshold_now "$(memory_knob sweep_threshold_lines)"
metric pending_chunks "$(pending_chunks)"

reward_write
exit 0
