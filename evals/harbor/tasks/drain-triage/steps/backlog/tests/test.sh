#!/bin/sh
set -u

. "${IWE_EVAL_LIB:-/opt/iwe-evals/assert.sh}"

reward_init
wait_for 30 no_stale_claims
BUSY_ONE=3a71c0d0-0000-4000-8000-00000000ba01
BUSY_TWO=4b82d1e0-0000-4000-8000-00000000ba02
KEEPER=5c93e2f0-0000-4000-8000-00000000ba03

note '# the whole backlog was worked'
check memory_is_on memory_enabled
check busywork_session_completed capture_noted "$BUSY_ONE"
check second_busywork_session_completed capture_noted "$BUSY_TWO"
check keeper_session_completed capture_noted "$KEEPER"
check backlog_drained backlog_drained
check queue_drained no_stale_claims

note '# the rigor went where the signal was'
check the_drain_read_the_frontier_as_a_batch frontier_used
check two_sessions_kept_nothing test "$(empty_captures)" -eq 2
check fact_captured mem_has_text 'DEPLOY_ENV'
check runbook_named mem_has_text 'RB-417'
check provenance_resolves provenance_linked "$KEEPER"
check no_noise test "$(knowledge_count)" -le 3
check nothing_committed git_head_untouched

metric memory_documents "$(knowledge_count)"
metric empty_completions "$(empty_captures)"
metric frontier_reads "$(stream_count 'job frontier')"
metric single_chunk_reads "$(stream_count 'job next')"
metric dedup_searches "$(stream_count 'find --lexical')"
answer distill_agent_launched agent_launched distill

reward_write
exit 0
