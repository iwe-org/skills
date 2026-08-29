#!/bin/sh
set -u

. "${IWE_EVAL_LIB:-/opt/iwe-evals/assert.sh}"

reward_init
SESSION=1a7f5b30-0000-4000-8000-0000000000b1

wrote_a_zettel() {
  [ "$(mem_count '{ type: zettel }')" -gt 0 ]
}

zettels_only() {
  [ "$(captured_count)" -gt 0 ] || return 1
  [ "$(captured_count)" = "$(mem_count '{ type: zettel }')" ]
}

keys_under_notes() {
  _stray=$(captured_keys | grep -cv '^notes/' || :)
  [ "${_stray:-0}" = "0" ]
}

note '# the session did the work'
check deploy_succeeded deploy_target_known
check nothing_committed git_head_untouched

note "# capture wrote this store's shape, not one of its own"
check wrote_a_zettel wrote_a_zettel
check only_zettels zettels_only
check keys_follow_the_store_convention keys_under_notes
check store_validates mem_valid
check no_default_ontology no_default_ontology
check fact_captured mem_has_text 'DEPLOY_ENV'

note '# and the flow still closed the loop'
check watermark_advanced test "$(mem_watermark "$SESSION")" -gt 0
check capture_noted_on_the_session capture_noted "$SESSION"
check provenance_linked provenance_linked "$SESSION"
check backlog_drained backlog_drained
check ledger_recorded test "$(session_kept "$SESSION")" -gt 0
check no_subagent_spawned no_subagent_spawned

metric zettels "$(mem_count '{ type: zettel }')"
metric knowledge_documents "$(knowledge_count)"

reward_write
exit 0
