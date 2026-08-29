#!/bin/sh
set -u

. "${IWE_EVAL_LIB:-/opt/iwe-evals/assert.sh}"

reward_init
SESSION=c0ffee11-0000-4000-8000-00000000dd01

no_phantom_decision() {
  ! mem_has_text 'RETRY_BUDGET' && ! mem_has_text 'retry budget'
}

note '# what the user confirmed was written'
check memory_is_on memory_enabled
check gate_captured mem_has_text 'DEPLOY_ENV'
check runbook_named mem_has_text 'RB-417'
check something_was_kept test "$(captured_count)" -gt 0
check provenance_linked provenance_linked "$SESSION"
check store_validates mem_valid

note '# what the user never confirmed was not'
check no_phantom_decision no_phantom_decision
check no_deploy_script_edit run_in_app sh -c '! grep -q "RETRY_BUDGET=.*10" bin/deploy.sh'

note '# and the run recorded itself'
check watermark_advanced test "$(mem_watermark "$SESSION")" -gt 0
check capture_noted_on_the_session capture_noted "$SESSION"
check session_was_distilled session_distilled "$SESSION"
check no_subagent_spawned no_subagent_spawned
check no_state_files store_has_no_state_files
check nothing_committed git_head_untouched

metric memory_documents "$(knowledge_count)"
metric offered "$(session_offered "$SESSION")"
metric kept "$(session_kept "$SESSION")"
metric rejected "$(session_rejected_count "$SESSION")"
answer ledger_recorded_a_rejection test "$(session_rejected_count "$SESSION")" -gt 0
answer read_the_span stream_has 'session read'

reward_write
exit 0
