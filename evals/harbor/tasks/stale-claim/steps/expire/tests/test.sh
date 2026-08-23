#!/bin/sh
set -u

. "${IWE_EVAL_LIB:-/opt/iwe-evals/assert.sh}"

reward_init
wait_for 60 no_stale_claims
SESSION=2c5a7e80-0000-4000-8000-0000000000d1

dead_digest_gone() {
  ! grep -rq 'a capture that died' "$EVAL_APP/sessions" 2>/dev/null
}

# The chunk key is the line it starts at, so the re-import lands on the same
# file rather than leaving the dead half-span beside a fresh one.
span_not_duplicated() {
  [ ! -f "$EVAL_APP/sessions/$SESSION/000012.md" ]
}

note '# the stale claim did not survive, and did not advance anything'
check stale_digest_replaced dead_digest_gone
check span_imported_once span_not_duplicated
check queue_drained no_stale_claims
check nothing_committed git_head_untouched

note '# the span it was holding was swept again'
check span_reswept test "$(mem_watermark "$SESSION")" -ge 80
check capture_noted_on_the_session capture_noted "$SESSION"
answer backlog_drained backlog_drained

metric watermark "$(mem_watermark "$SESSION")"
metric memory_documents "$(knowledge_count)"

reward_write
exit 0
