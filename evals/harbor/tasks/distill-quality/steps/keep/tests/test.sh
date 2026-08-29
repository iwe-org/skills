#!/bin/sh
set -u

. "${IWE_EVAL_LIB:-/opt/iwe-evals/assert.sh}"

reward_init
SESSION=de000002-0000-4000-8000-00000000de02
FIXTURE=${IWE_EVAL_FIXTURE:-tail-dense}
UNITS=$EVAL_VERIFIER/document-units

gold_dump_documents "$UNITS"
gold_eval "$FIXTURE" "$UNITS"

note '# what was written, against the gold set'
score document_recall "$(gold_fraction "$(gold_stat "$UNITS" gold_hits)" "$(gold_stat "$UNITS" gold_total)")"
score document_precision "$(gold_fraction "$(gold_stat "$UNITS" units_on_gold)" "$(gold_stat "$UNITS" units)")"
check no_decoy_written test "$(gold_stat "$UNITS" decoy_units)" -eq 0
check no_secret_written test "$(gold_stat "$UNITS" secret_units)" -eq 0
check no_folding test "$(gold_stat "$UNITS" folded_units)" -eq 0

note '# the shape of it'
check no_duplicate_of_seeded test "$(knowledge_titles_matching 'staging-(green|blue)')" -eq 1
check seeded_document_covers_it test "$(gold_pattern_units "$UNITS" "$FIXTURE" G3)" -ge 1
check seeded_created_preserved run_in_app grep -q '2026-07-02' deploy-target-freeze.md
check key_convention knowledge_keys_are_flat_slugs
check provenance_linked provenance_linked "$SESSION"
check store_validates mem_valid
check no_truncation_marker no_truncation_marker_in_memory

note '# and the run recorded itself'
check session_distilled session_distilled "$SESSION"
check watermark_advanced test "$(mem_watermark "$SESSION")" -gt 0
check no_subagent_spawned no_subagent_spawned
check no_state_files store_has_no_state_files
check nothing_committed git_head_untouched

metric documents_written "$(captured_count)"
metric knowledge_documents "$(knowledge_count)"
metric gold_hits "$(gold_stat "$UNITS" gold_hits)"
metric gold_total "$(gold_stat "$UNITS" gold_total)"
metric freeze_titled_documents "$(knowledge_titles_matching 'staging-(green|blue)')"
metric decoy_documents "$(gold_stat "$UNITS" decoy_units)"
metric folded_documents "$(gold_stat "$UNITS" folded_units)"
metric windows_read "$(tool_calls_matching 'session read')"
metric tool_calls "$(tool_calls)"
metric offered "$(session_offered "$SESSION")"
metric kept "$(session_kept "$SESSION")"
answer read_the_span stream_has 'session read'

reward_write
exit 0
