#!/bin/sh
set -u

. "${IWE_EVAL_LIB:-/opt/iwe-evals/assert.sh}"

reward_init
SESSION=de000003-0000-4000-8000-00000000de03
FIXTURE=${IWE_EVAL_FIXTURE:-tail-dense}
UNITS=$EVAL_VERIFIER/document-units

gold_dump_documents "$UNITS"
gold_eval "$FIXTURE" "$UNITS"

note '# what the first half wrote'
score document_recall "$(gold_fraction "$(gold_stat "$UNITS" gold_hits)" "$(gold_stat "$UNITS" gold_total)")"
score document_precision "$(gold_fraction "$(gold_stat "$UNITS" units_on_gold)" "$(gold_stat "$UNITS" units)")"
check no_decoy_written test "$(gold_stat "$UNITS" decoy_units)" -eq 0
check no_secret_written test "$(gold_stat "$UNITS" secret_units)" -eq 0
check no_folding test "$(gold_stat "$UNITS" folded_units)" -eq 0
check key_convention knowledge_keys_are_flat_slugs
check provenance_linked provenance_linked "$SESSION"
check store_validates mem_valid
check session_distilled session_distilled "$SESSION"
check no_subagent_spawned no_subagent_spawned
check nothing_committed git_head_untouched

metric documents_written "$(captured_count)"
metric gold_hits "$(gold_stat "$UNITS" gold_hits)"
metric gold_total "$(gold_stat "$UNITS" gold_total)"
metric decoy_documents "$(gold_stat "$UNITS" decoy_units)"
metric windows_read "$(tool_calls_matching 'session read')"
metric tool_calls "$(tool_calls)"

reward_write
exit 0
