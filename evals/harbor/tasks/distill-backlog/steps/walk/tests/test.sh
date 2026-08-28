#!/bin/sh
set -u

. "${IWE_EVAL_LIB:-/opt/iwe-evals/assert.sh}"

reward_init
DEPLOY=aa000001-0000-4000-8000-00000000ba01
BUSY=aa000002-0000-4000-8000-00000000ba02
BACKFILL=aa000003-0000-4000-8000-00000000ba03
LIVE=aa000004-0000-4000-8000-00000000ba04

subagent_content_never_reached_memory() {
  ! mem_has_text 'SUBAGENT_ONLY_MARKER' && ! mem_has_text 'registry dependency'
}

note '# the backlog was listed and the signal session was read'
check memory_is_on memory_enabled
check deploy_session_read test "$(mem_watermark "$DEPLOY")" -gt 0
check fact_captured mem_has_text 'DEPLOY_ENV'
check provenance_linked provenance_linked "$DEPLOY"
check capture_noted_on_the_session capture_noted "$DEPLOY"

note '# the live conversation was left alone'
check live_session_untouched test "$(mem_watermark "$LIVE")" -eq 0
check live_session_still_pending session_is "$LIVE" active

note '# the stale rest was marked seen, not read'
check busywork_settled test "$(mem_watermark "$BUSY")" -gt 0
check backfill_settled test "$(mem_watermark "$BACKFILL")" -gt 0
check busywork_adopted session_adopted "$BUSY"
check backfill_adopted session_adopted "$BACKFILL"

note '# and nothing came from a subagent'
check no_subagent_content subagent_content_never_reached_memory
check no_subagent_spawned no_subagent_spawned
check store_validates mem_valid
check nothing_committed git_head_untouched

metric memory_documents "$(knowledge_count)"
metric sessions_recorded "$(session_records)"
metric pending_tails "$(pending_tails)"

reward_write
exit 0
