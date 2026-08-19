#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

SESSION=7c1af940-0000-4000-8000-00000000ab01

# Size the chunks for a backfill before the first import: per-chunk overhead is
# fixed, so fewer and larger is cheaper over the same span, and the item budget
# scales with it so a bigger chunk is still allowed to yield what it holds.
eval_memory_set chunk_chars 25000
eval_memory_set max_items_per_chunk 7

eval_sweep "$SESSION"
eval_stream_note 'Agent tool: {"subagent_type":"distill"} run_in_background true'

eval_seed_captured_doc deploy-env-rb-417 '2026-08-12 08:03' "$SESSION" claude \
  'Deploy fails two ways, exit 2 and exit 3' \
  'make deploy exits 2 while dist/releasekit.tar.gz is missing and exits 3 with "DEPLOY_ENV is unset (RB-417)" once the bundle is there. The valid DEPLOY_ENV values are written down only in ops/runbook-417.txt: staging-blue and staging-green.'
eval_seed_captured_doc vendored-parser-stays-vendored '2026-08-12 08:40' "$SESSION" user \
  'The vendored parser never becomes a dependency' \
  'src/parser/ is a patched copy of parsekit 0.4.1 and must never be replaced by the registry package: the patch is what makes it POSIX sh, and the dependency would pull a node toolchain into a shell tool. Nothing in the repository records this.'
eval_seed_captured_doc standby-rotation-rb-508 '2026-08-12 09:05' "$SESSION" user \
  'RB-508 governs the standby rotation' \
  'RB-417 names the valid DEPLOY_ENV values; RB-508 says which of them is live while staging-blue is being rebuilt. The two runbooks answer different questions and only RB-508 answers "which target this week".'
eval_seed_captured_doc deploy-attempts-audit-trail '2026-08-12 09:20' "$SESSION" claude \
  'The attempt log is written before validation' \
  'bin/deploy.sh appends the timestamp and ${DEPLOY_ENV:-<unset>} to .deploy-attempts before it validates anything, so the file records failed runs too. That is what tells a blind retry from a re-diagnosed failure afterwards.'

eval_complete_capture "$SESSION" deploy-env-rb-417 vendored-parser-stays-vendored \
  standby-rotation-rb-508 deploy-attempts-audit-trail

# Live capture wants the small budget back, and the restore is import-side: the
# chunks this drain imported keep the stamps they were cut with.
eval_memory_set chunk_chars 10000
eval_memory_set max_items_per_chunk 3
