#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

SESSION=de000002-0000-4000-8000-00000000de02
OCCURRED="2026-08-18 09:04"

eval_brief
eval_iwe retrieve -k MEMORY >/dev/null

# The run reads the span, then writes one document per gold fact through the
# CLI, in the starter policy's shape: a flat slug, `created` from the read
# header's occurred stamp, `session` naming the record.
eval_seed_captured_doc busybox-sh-has-no-pipefail "$OCCURRED" "$SESSION" \
  "set -o pipefail breaks bin/deploy.sh on the deploy hosts" \
  "The deploy hosts run busybox sh, which rejects the option with \`bin/deploy.sh: line 3: set: Illegal option -o pipefail\`. The line was added beside \`set -u\` and reverted after \`busybox sh -n bin/deploy.sh\` failed; the build host's dash accepts it, which is why CI would not have caught it. Parse any change to bin/*.sh under busybox before keeping it."
eval_seed_captured_doc lb-drain-window-rb-533 "$OCCURRED" "$SESSION" \
  "The load-balancer drain takes 150 seconds (RB-533)" \
  "RB-533 records that a load-balancer drain takes 150 seconds, and nobody deploys inside a drain window, retries or no retries. Waiting the window out is what protects a deploy; the retry loop in bin/deploy.sh is not, and it stays as it is."
eval_seed_captured_doc smoke-hook-needs-smoke-token "$OCCURRED" "$SESSION" \
  "The nightly smoke hook needs SMOKE_TOKEN from ops/vault/releasekit-smoke" \
  "The smoke hook (.ci/smoke.sh) aborts with \`smoke: SMOKE_TOKEN missing (RB-590)\` when the variable is empty. Its value is not in the repository: CI reads it from the vault path ops/vault/releasekit-smoke. A vault rotation leaves a job holding an old lease with an empty value, which is what turned the job red on 2026-08-17."
eval_seed_captured_doc deploy-hosts-git-2-30-no-initial-branch "$OCCURRED" "$SESSION" \
  "Deploy hosts run git 2.30, which has no --initial-branch (RB-611)" \
  "\`git init --initial-branch=main\` on a deploy host fails with \`error: unknown option 'initial-branch=main'\` because the hosts run git 2.30.2. The RB-611 workaround is a plain \`git init\` followed by \`git symbolic-ref HEAD refs/heads/main\`."
eval_seed_captured_doc release-train-schedule "$OCCURRED" "$SESSION" \
  "Release trains cut Tuesdays 10:00 UTC; code freeze starts Friday 16:00 UTC" \
  "Stated by the user so it is recorded somewhere: release trains cut on Tuesdays at 10:00 UTC and code freeze starts on Friday at 16:00 UTC. Nothing in the repository says this and new people keep asking."
eval_seed_captured_doc runbook-417-edits-need-ops-ticket "$OCCURRED" "$SESSION" \
  "ops/runbook-417.txt is edited only with an OPS- ticket and ops sign-off" \
  "bin/deploy.sh parses ops/runbook-417.txt, so the file is never edited directly, not even for a comment: every change goes through an OPS- ticket with ops sign-off. OPS-2291 carries the note that staging-green is frozen."
eval_seed_captured_doc make-test-runs-on-build-host-only "$OCCURRED" "$SESSION" \
  "make test runs on the build host only; busybox fails the parser test (RB-622)" \
  "Under the deploy hosts' busybox sh, bin/test.sh fails \`parser strips comments\` with \`expected [key=value] got []\`: busybox printf inside the \`\$(...)\` in the test harness does not expand the escapes the way dash does. RB-622 records that the suite runs on the build host only and has never passed under busybox; do not chase it."

eval_iwe update -k deploy-target-freeze --content '# Release trains deploy to staging-blue while RB-417 is open

staging-green is frozen for the vendored-parser rewrite: the parser team keeps its rewrite baseline there and a deploy resets it. Every release train goes to staging-blue until RB-417 is closed, even though ops/runbook-417.txt lists both targets as valid. On 2026-08-18 a deploy went to staging-green by mistake and was redone on staging-blue; the runbook still does not say so, and OPS-2291 carries the note.' >/dev/null

eval_distill_session "$SESSION" 8 "" \
  busybox-sh-has-no-pipefail lb-drain-window-rb-533 deploy-target-freeze \
  smoke-hook-needs-smoke-token deploy-hosts-git-2-30-no-initial-branch \
  release-train-schedule runbook-417-edits-need-ops-ticket \
  make-test-runs-on-build-host-only
