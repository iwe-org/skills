#!/bin/sh
set -u

. "${IWE_EVAL_LIB:-/opt/iwe-evals/assert.sh}"

reward_init
SEEDED=7a1c9f20-0000-4000-8000-00000000ab01

note '# question 1: does SessionStart fire in headless mode, and is its output injected?'
answer sessionstart_fired marker_fired SessionStart
answer injection_visible stream_has '<iwe-memory>'
answer injection_names_cookbook stream_has 'query cookbook'

note '# question 2: is the Stop block honored headless?'
answer stop_fired marker_fired Stop
answer sweep_imported_the_tail tail_claimed "$SEEDED"
answer distill_agent_launched agent_launched distill

note '# question 3: does the background capture finish before the process exits?'
answer watermark_advanced test "$(mem_watermark "$SEEDED")" -gt 0
answer capture_wrote_a_document test "$(knowledge_count)" -gt 1
answer capture_found_the_planted_fact mem_has_text 'DEPLOY_ENV'
answer capture_noted_on_the_session capture_noted "$SEEDED"
answer provenance_linked provenance_linked "$SEEDED"
answer queue_drained no_stale_claims
answer backlog_drained backlog_drained
answer subagent_transcript_written test -n "$(eval_subagent_transcripts)"

metric pending_tails "$(pending_tails)"
metric transcript_lines "$(eval_longest_tail)"
metric memory_documents "$(knowledge_count)"

score probe_recorded 1
reward_write
exit 0
