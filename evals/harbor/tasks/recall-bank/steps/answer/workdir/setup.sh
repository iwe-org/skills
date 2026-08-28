#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

eval_memory_init
eval_clean_run_state
rm -f "$EVAL_APP/answer.txt" "$EVAL_APP/answers.txt"

# The eight facts the bank asks about, in the starter shape.
eval_seed_doc busybox-sh-has-no-pipefail "2026-08-18 09:21" \
  "set -o pipefail breaks bin/deploy.sh on the deploy hosts" \
  "The deploy hosts run busybox sh, which rejects the option with 'bin/deploy.sh: line 3: set: Illegal option -o pipefail'. The line was added beside set -u and reverted; the build host's dash accepts it, which is why CI would not have caught it."
eval_seed_doc lb-drain-window-rb-533 "2026-08-18 09:24" \
  "The load-balancer drain takes 150 seconds (RB-533)" \
  "RB-533 records that a load-balancer drain takes 150 seconds, and nobody deploys inside a drain window, retries or no retries. Waiting the window out is what protects a deploy."
eval_seed_doc staging-green-frozen-until-rb-417 "2026-08-18 09:12" \
  "staging-green is frozen until RB-417 closes; release trains go to staging-blue" \
  "The parser team keeps its rewrite baseline on staging-green and a deploy resets it, so staging-green is frozen until RB-417 closes and every release train goes to staging-blue, even though ops/runbook-417.txt lists both targets."
eval_seed_doc smoke-hook-needs-smoke-token "2026-08-18 09:31" \
  "The nightly smoke hook needs SMOKE_TOKEN from ops/vault/releasekit-smoke" \
  "The smoke hook aborts with 'smoke: SMOKE_TOKEN missing (RB-590)' when the variable is empty. Its value is not in the repository: CI reads it from the vault path ops/vault/releasekit-smoke, and a rotation can leave a job with an empty value."
eval_seed_doc deploy-hosts-git-2-30-no-initial-branch "2026-08-18 09:40" \
  "Deploy hosts run git 2.30, which has no --initial-branch (RB-611)" \
  "git init --initial-branch=main on a deploy host fails with 'unknown option' because the hosts run git 2.30.2. The RB-611 workaround is a plain git init followed by git symbolic-ref HEAD refs/heads/main."
eval_seed_doc release-train-schedule "2026-08-18 09:52" \
  "Release trains cut Tuesdays 10:00 UTC; code freeze starts Friday 16:00 UTC" \
  "Release trains cut on Tuesdays at 10:00 UTC and code freeze starts on Friday at 16:00 UTC. Nothing in the repository says this."
eval_seed_doc runbook-417-edits-need-ops-ticket "2026-08-18 09:36" \
  "ops/runbook-417.txt is edited only with an OPS- ticket and ops sign-off" \
  "bin/deploy.sh parses ops/runbook-417.txt, so the file is never edited directly, not even for a comment: every change goes through an OPS- ticket with ops sign-off."
eval_seed_doc make-test-runs-on-build-host-only "2026-08-18 09:46" \
  "make test runs on the build host only; busybox fails the parser test (RB-622)" \
  "Under the deploy hosts' busybox sh, bin/test.sh fails 'parser strips comments' with 'expected [key=value] got []'. RB-622 records that the suite runs on the build host only and has never passed under busybox."

# One document the repository contradicts: bin/deploy.sh exits 3, not 7. An
# answer that repeats 7 trusted memory over the code in front of it.
eval_seed_doc deploy-env-unset-exit-code "2026-05-04 15:10" \
  "make deploy exits 7 when DEPLOY_ENV is unset" \
  "bin/deploy.sh exits 7 with 'DEPLOY_ENV is unset (RB-417)' when the variable is empty, and 2 until make build has written the bundle."

eval_seed_distractors "$EVAL_FIXTURES/distractors.txt" "2026-06-10 11:00"
eval_seed_questions
eval_settle_watermarks
eval_finish

rm -- "$0"
