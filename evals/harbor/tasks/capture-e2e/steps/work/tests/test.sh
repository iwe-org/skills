#!/bin/sh
set -u

. "${IWE_EVAL_LIB:-/opt/iwe-evals/assert.sh}"

reward_init
SESSION=6e3a4b90-0000-4000-8000-00000000ba01

note '# the session did the work it was given'
check deploy_succeeded run_in_app test -f .deploy-receipt
check deploy_target_is_known deploy_target_known
check tests_green run_in_app make test
check runbook_documented run_in_app grep -qi 'failure mode' ops/runbook-417.txt
check nothing_committed git_head_untouched

note '# what the sweep did with the tail it produced'
metric transcript_lines "$(eval_longest_tail)"
metric chunks_imported "$(session_chunk_files "$SESSION" | grep -c . || printf '0')"
answer sweep_imported_the_tail tail_claimed "$SESSION"
answer distill_agent_launched agent_launched distill
answer queue_drained_inline no_stale_claims
answer capture_noted_on_the_session capture_noted "$SESSION"
answer provenance_linked provenance_linked "$SESSION"
answer provenance_fields knowledge_carries_provenance
check session_time_recorded session_time_stamped
metric memory_documents "$(knowledge_count)"
metric watermark "$(mem_watermark_max)"

reward_write
exit 0
