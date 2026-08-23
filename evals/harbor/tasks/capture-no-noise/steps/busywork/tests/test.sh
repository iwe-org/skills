#!/bin/sh
set -u

. "${IWE_EVAL_LIB:-/opt/iwe-evals/assert.sh}"

reward_init
wait_for 30 no_stale_claims
SESSION=5b2d8e10-0000-4000-8000-00000000cd01

note '# the busywork itself'
check rename_applied run_in_app grep -q 'greeting=' bin/greet.sh
check rename_complete run_in_app sh -c '! grep -q "msg=" bin/greet.sh'
check tests_green run_in_app make test

note '# the sweep ran, and it wrote nothing'
check sweep_imported_the_tail tail_claimed "$SESSION"
check no_noise test "$(knowledge_count)" -eq 0
check nothing_captured test "$(captured_count)" -eq 0
check tail_closed no_stale_claims
check watermark_advanced test "$(mem_watermark "$SESSION")" -gt 0
check capture_noted_on_the_session capture_noted "$SESSION"
check nothing_committed git_head_untouched

metric noise_documents "$(knowledge_count)"
metric pending_tails "$(pending_tails)"
answer distill_agent_launched agent_launched distill

reward_write
exit 0
