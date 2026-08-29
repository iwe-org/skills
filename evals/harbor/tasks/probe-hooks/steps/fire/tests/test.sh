#!/bin/sh
set -u

. "${IWE_EVAL_LIB:-/opt/iwe-evals/assert.sh}"

reward_init
SEEDED=7a1c9f20-0000-4000-8000-00000000ab01

session_id_exported() {
  eval_all_text | grep -qE 'CLAUDE_CODE_SESSION_ID=[0-9a-f-]{8}'
}

listing_marks_a_current_session() {
  grep -q 'current session: [0-9a-f-]' "$EVAL_NOTES/session-list.out" 2>/dev/null
}

note '# question 1: does SessionStart fire headless, and is its output injected?'
answer sessionstart_fired marker_fired SessionStart
answer injection_visible stream_has '<iwe-memory>'
answer injection_names_cookbook stream_has 'query cookbook'
answer injection_counts_the_backlog stream_has 'are not distilled'
answer injection_carries_the_offer stream_has 'Worth remembering'

note '# question 2: is CLAUDE_CODE_SESSION_ID in the tool environment?'
answer session_id_exported session_id_exported
answer listing_knows_the_current_session listing_marks_a_current_session

note '# question 3: nothing ran that nobody asked for'
answer no_stop_hook_exists test ! -f "$EVAL_NOTES/hook-stop.out"
answer nothing_captured test "$(captured_count)" -eq 0
answer no_watermark_moved test "$(mem_watermark "$SEEDED")" -eq 0
answer no_subagent_spawned no_subagent_spawned

metric pending_tails "$(pending_tails)"
metric transcript_lines "$(eval_longest_tail)"
metric memory_documents "$(knowledge_count)"

score probe_recorded 1
reward_write
exit 0
