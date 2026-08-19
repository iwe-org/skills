#!/bin/sh
set -u

. "${IWE_EVAL_LIB:-/opt/iwe-evals/assert.sh}"

reward_init
wait_for 60 no_stale_claims
FIRST=8f1e6d20-0000-4000-8000-0000000000c1
SECOND=8f1e6d20-0000-4000-8000-0000000000c2

session_records_are_unique() {
  _dupes=$(grep -h '^session:' "$EVAL_APP/sessions"/*.md 2>/dev/null |
    sort | uniq -c | awk '$1 > 1' | grep -c .)
  [ "$_dupes" = "0" ]
}

capture_notes_are_single() {
  _multi=$(grep -c -- '— captured' "$EVAL_APP/sessions/$FIRST.md" 2>/dev/null)
  [ "$_multi" = "1" ] || return 1
  _multi=$(grep -c -- '— captured' "$EVAL_APP/sessions/$SECOND.md" 2>/dev/null)
  [ "$_multi" = "1" ]
}

knowledge_titles_are_unique() {
  _dupes=$(mem_iwe find --filter "$(knowledge_filter)" --limit 0 --project 'title=$title' |
    sort | uniq -d | grep -c .)
  [ "$_dupes" = "0" ]
}

note '# both spans were imported, once each'
check both_sessions_recorded test "$(session_records)" -eq 2
check one_record_per_session session_records_are_unique
check first_tail_imported tail_claimed "$FIRST"
check second_tail_imported tail_claimed "$SECOND"
check one_capture_per_session capture_notes_are_single

note '# and the race left nothing behind'
check no_chunk_outlived_the_race no_stale_claims
check no_duplicate_items knowledge_titles_are_unique
answer backlog_drained backlog_drained
check no_state_files store_has_no_state_files
check nothing_committed git_head_untouched

metric memory_documents "$(knowledge_count)"
metric pending_tails "$(pending_tails)"

reward_write
exit 0
