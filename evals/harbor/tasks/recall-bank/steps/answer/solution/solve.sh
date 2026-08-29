#!/bin/sh
set -eu

. "${IWE_EVAL_SETUP:-/opt/iwe-evals/setup-lib.sh}"

for terms in "deploy target staging" "pipefail deploy" "drain RB-533" "smoke token vault" "git initial-branch" "release train schedule" "runbook edit ticket" "make test busybox" "DEPLOY_ENV unset exit"; do
  eval_iwe find --lexical "$terms" --limit 3 >/dev/null
  eval_stream_note "{\"type\":\"tool_use\",\"name\":\"Bash\",\"input\":{\"command\":\"iwe find --lexical \\\"$terms\\\" --limit 3\"}}"
done

# The stale document says 7; the script says 3, and the script is right here.
grep -n 'exit 3' bin/deploy.sh >/dev/null

cat >answers.txt <<'EOF'
1. staging-blue — staging-green is frozen for the parser rewrite until RB-417 closes.
2. The deploy hosts run busybox sh, which rejects it: "set: Illegal option -o pipefail"; it was reverted.
3. 150 seconds, recorded in RB-533; nobody deploys inside a drain window.
4. SMOKE_TOKEN, which CI reads from the vault path ops/vault/releasekit-smoke (RB-590).
5. The hosts run git 2.30, which predates the option; a plain init then git symbolic-ref HEAD refs/heads/main (RB-611).
6. Trains cut Tuesdays at 10:00 UTC; freeze starts Friday 16:00 UTC.
7. An OPS- ticket and ops sign-off, because bin/deploy.sh parses the file.
8. On the build host only; under busybox the parser test fails (RB-622).
9. Exit 3 — bin/deploy.sh says so; the memory document claiming otherwise is stale.
EOF
