#!/bin/sh
set -u

. "${IWE_EVAL_LIB:-/opt/iwe-evals/assert.sh}"

reward_init

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
check nothing_committed git_head_untouched

metric memory_documents "$(mem_count '{ type: { $in: [learning, decision, gotcha] } }')"

reward_write
exit 0
