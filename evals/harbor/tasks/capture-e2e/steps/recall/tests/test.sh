#!/bin/sh
set -u

. "${IWE_EVAL_LIB:-/opt/iwe-evals/assert.sh}"

reward_init

note '# what memory had to offer this session'
answer recall_precondition mem_has_text 'DEPLOY_ENV'

note '# whether the session used it'
check deploy_succeeded deploy_target_known
check no_blind_attempt test "$(deploy_blind_attempts)" -eq 0
check consulted_memory memory_query_seen

metric deploy_attempts "$(deploy_attempts)"
metric blind_attempts "$(deploy_blind_attempts)"

reward_write
exit 0
