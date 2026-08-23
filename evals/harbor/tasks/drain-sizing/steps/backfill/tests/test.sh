#!/bin/sh
set -u

. "${IWE_EVAL_LIB:-/opt/iwe-evals/assert.sh}"

reward_init
wait_for 30 no_stale_claims
SESSION=7c1af940-0000-4000-8000-00000000ab01

note '# the drain sized its chunks for a backfill'
check memory_is_on memory_enabled
check chunks_carry_the_backfill_item_budget chunk_budget_at_least "$SESSION" 7
check fewer_chunks_than_the_default_budget chunks_below_baseline "$SESSION"
check live_capture_defaults_restored capture_defaults_restored

note '# and kept what the default budget keeps, plus what it truncates away'
check fact_captured mem_has_text 'DEPLOY_ENV'
check runbook_named mem_has_text 'RB-417'
check decision_captured mem_has_text 'parser'
check fact_past_the_default_cut mem_has_text 'RB-508'
check no_truncation_marker_copied no_truncation_marker_in_memory

note '# the ordinary drain invariants still hold'
check watermark_advanced test "$(mem_watermark "$SESSION")" -gt 0
check backlog_drained backlog_drained
check queue_drained no_stale_claims
check capture_noted_on_the_session capture_noted "$SESSION"
check provenance_resolves provenance_linked "$SESSION"
check no_state_files store_has_no_state_files
check nothing_committed git_head_untouched

metric imported_chunks "$(session_chunk_count "$SESSION")"
metric baseline_chunks_at_10000 "$(baseline_chunks)"
metric memory_documents "$(knowledge_count)"
metric captured_documents "$(captured_count)"
answer distill_agent_launched agent_launched distill

reward_write
exit 0
