#!/bin/sh
set -u

. "${IWE_EVAL_LIB:-/opt/iwe-evals/assert.sh}"

reward_init
SESSION=dd000001-0000-4000-8000-00000000cc01

# A model run completes against its own session id, which this verifier cannot
# know, so the scored checks ask whether *some* session record kept the two
# documents; the ledger on the oracle's fixed id is reported, not scored.
a_capture_was_noted() {
  for _id in $(session_record_ids); do
    capture_noted "$_id" && return 0
  done
  return 1
}

note '# the novel fact becomes its own document, in this store shape'
check novel_document_created mem_type_has_text 'gotcha, learning, decision' 'receipt'
check novel_document_is_findable test -n "$(mem_iwe find --lexical 'smoke deploy receipt' -f keys --limit 3)"
check typed_key_convention_followed run_in_app sh -c 'ls gotchas/*.md >/dev/null 2>&1'

note '# the known fact updates the document that already covered it'
check no_duplicate_decision test "$(mem_count '{ type: decision }')" -eq 1
check existing_document_updated run_in_app grep -q '2026-09-01' decisions/deploy-target-freeze.md
check created_stamp_preserved run_in_app grep -q '2026-07-02' decisions/deploy-target-freeze.md

note '# written through the CLI gate, not by hand'
check store_validates mem_valid
check attached_to_the_daily_hub daily_links_a_memory
check no_state_files store_has_no_state_files
check no_subagent_spawned no_subagent_spawned
check nothing_committed git_head_untouched

note '# and the run recorded what it kept, with no transcript to read'
check both_documents_linked_from_a_session test "$(captured_count)" -ge 2
check capture_noted a_capture_was_noted
check no_line_moved test "$(mem_watermark_max)" -eq 0

metric memory_documents "$(mem_count '{ type: { $in: [learning, decision, gotcha] } }')"
metric offered "$(session_offered "$SESSION")"
metric kept "$(session_kept "$SESSION")"
answer ledger_kept_both test "$(session_kept "$SESSION")" -eq 2
answer nothing_rejected test "$(session_rejected_count "$SESSION")" -eq 0

reward_write
exit 0
