#!/bin/sh
set -u

. "${IWE_EVAL_LIB:-/opt/iwe-evals/assert.sh}"

reward_init

SCRIPT_SEEDED='#!/bin/sh
#  checks    the handover note is current
set -eu
grep -q '"'"'runbook-417'"'"' notes/handoff.md
# fixed: targets.txt -> runbook-417.txt'

note '# the edit the user asked for landed'
check memory_is_on memory_enabled
check runbook_named mem_iwe retrieve -k notes/handoff
check targets_file_gone run_in_app sh -c '! grep -q "ops/targets.txt" notes/handoff.md'
check runbook_file_named run_in_app sh -c 'grep -q "runbook-417.txt" notes/handoff.md'
check exit_code_noted run_in_app sh -c 'grep -q "DEPLOY_ENV" notes/handoff.md'

note '# and the net put the document back into canonical form'
check document_is_canonical is_canonical notes/handoff
check bullets_normalized run_in_app sh -c '! grep -qE "^\*  " notes/handoff.md'
check heading_normalized run_in_app sh -c '! grep -qE "^#  " notes/handoff.md'
check frontmatter_kept run_in_app sh -c 'grep -q '"'"'created: "2026-08-20 09:00"'"'"' notes/handoff.md'
check store_validates mem_valid

note '# while the file the net does not own is untouched'
check script_is_verbatim file_is_verbatim bin/handoff-check.sh "$SCRIPT_SEEDED"

note '# and nothing was captured along the way'
check nothing_captured test "$(captured_count)" -eq 0
check no_session_records test "$(session_records)" -eq 0
check no_subagent_spawned no_subagent_spawned
check no_state_files store_has_no_state_files
check nothing_committed git_head_untouched

metric memory_documents "$(knowledge_count)"

reward_write
exit 0
