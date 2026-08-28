# Proposals for SESSION_ID

## set -o pipefail breaks bin/deploy.sh on the deploy hosts

The deploy hosts run busybox sh, which rejects the option with `bin/deploy.sh: line 3: set: Illegal option -o pipefail`. The line was added beside `set -u` and reverted after `busybox sh -n bin/deploy.sh` failed; the build host's dash accepts it, which is why CI would not have caught it. Parse any change to bin/*.sh under busybox before keeping it.

## The load-balancer drain takes 150 seconds (RB-533)

RB-533 records that a load-balancer drain takes 150 seconds, and nobody deploys inside a drain window, retries or no retries. Waiting the window out is what protects a deploy; the retry loop in bin/deploy.sh is not, and it stays as it is.

## staging-green is frozen until RB-417 closes; release trains go to staging-blue

A deploy went to staging-green because ops/runbook-417.txt lists it as valid; the user reversed it. The parser team keeps its rewrite baseline on staging-green and a deploy resets it, so staging-green is frozen until RB-417 closes and every release train goes to staging-blue. The runbook does not say so; OPS-2291 carries the note.

## The nightly smoke hook needs SMOKE_TOKEN from ops/vault/releasekit-smoke

The smoke hook (.ci/smoke.sh) aborts with `smoke: SMOKE_TOKEN missing (RB-590)` when the variable is empty. Its value is not in the repository: CI reads it from the vault path ops/vault/releasekit-smoke. A vault rotation leaves a job holding an old lease with an empty value, which is what turned the job red on 2026-08-17.

## Deploy hosts run git 2.30, which has no --initial-branch (RB-611)

`git init --initial-branch=main` on a deploy host fails with `error: unknown option 'initial-branch=main'` because the hosts run git 2.30.2. The RB-611 workaround is a plain `git init` followed by `git symbolic-ref HEAD refs/heads/main`.

## Release trains cut Tuesdays 10:00 UTC; code freeze starts Friday 16:00 UTC

Stated by the user so it is recorded somewhere: release trains cut on Tuesdays at 10:00 UTC and code freeze starts on Friday at 16:00 UTC. Nothing in the repository says this and new people keep asking.

## ops/runbook-417.txt is edited only with an OPS- ticket and ops sign-off

bin/deploy.sh parses ops/runbook-417.txt, so the file is never edited directly, not even for a comment: every change goes through an OPS- ticket with ops sign-off. OPS-2291 carries the note that staging-green is frozen.

## make test runs on the build host only; busybox fails the parser test (RB-622)

Under the deploy hosts' busybox sh, bin/test.sh fails `parser strips comments` with `expected [key=value] got []`: busybox printf inside the `$(...)` in the test harness does not expand the escapes the way dash does. RB-622 records that the suite runs on the build host only and has never passed under busybox; do not chase it.
