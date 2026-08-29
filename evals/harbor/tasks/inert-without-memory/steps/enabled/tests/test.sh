#!/bin/sh
set -u

. "${IWE_EVAL_LIB:-/opt/iwe-evals/assert.sh}"

reward_init
SESSION=9d2f4c60-0000-4000-8000-0000000000f1

# The record remembers the transcript's length when it is completed; the
# distilled line reaching it is the whole tail read, from line zero.
read_from_line_zero() {
  _total=$(session_field "$SESSION" transcript_lines)
  [ -n "$_total" ] || return 1
  [ "$(mem_watermark "$SESSION")" -eq "$_total" ]
}

note '# one document turned memory on'
check memory_is_on memory_enabled
check nothing_committed git_head_untouched

note '# and the history nobody had read was still there to read'
check tail_read test "$(mem_watermark "$SESSION")" -gt 0
check whole_tail_covered read_from_line_zero
check fact_captured mem_has_text 'DEPLOY_ENV'
check provenance_linked provenance_linked "$SESSION"
answer backlog_drained backlog_drained

metric watermark "$(mem_watermark "$SESSION")"
metric memory_documents "$(knowledge_count)"

reward_write
exit 0
