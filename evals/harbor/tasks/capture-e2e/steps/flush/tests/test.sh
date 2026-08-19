#!/bin/sh
set -u

. "${IWE_EVAL_LIB:-/opt/iwe-evals/assert.sh}"

reward_init
wait_for 30 no_stale_claims

note '# what the capture wrote'
check memory_is_on memory_enabled
check fact_captured mem_has_text 'DEPLOY_ENV'
check runbook_named mem_has_text 'RB-417'
check decision_captured mem_has_text 'parser'
check watermark_advanced test "$(mem_watermark_max)" -gt 0
check queue_drained no_stale_claims
answer provenance_fields knowledge_carries_provenance
check no_state_files store_has_no_state_files
check nothing_committed git_head_untouched

metric pending_tails "$(pending_tails)"
metric memory_documents "$(knowledge_count)"
metric released_chunks_before_this_step "$(cat "$EVAL_NOTES/released-claims" 2>/dev/null || printf '0')"
answer distill_agent_launched agent_launched distill

reward_write
exit 0
