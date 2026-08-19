#!/bin/sh
set -u

. "${IWE_EVAL_LIB:-/opt/iwe-evals/assert.sh}"

reward_init
wait_for 60 no_stale_claims
SESSION=9d2f4c60-0000-4000-8000-0000000000f1

captured_from_line_zero() {
  grep -q -- 'through line 8' "$EVAL_APP/sessions/$SESSION.md" 2>/dev/null
}

note '# one document turned memory on'
check memory_is_on memory_enabled
check nothing_committed git_head_untouched

note '# and the history nobody had read was still there to read'
check tail_imported tail_claimed "$SESSION"
check whole_tail_covered captured_from_line_zero
check fact_captured mem_has_text 'DEPLOY_ENV'
check queue_drained no_stale_claims
answer backlog_drained backlog_drained

metric watermark "$(mem_watermark "$SESSION")"
metric memory_documents "$(knowledge_count)"

reward_write
exit 0
