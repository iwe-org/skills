# Proposals for SESSION_ID

## The registry answers 401 'token lacks scope publish' (RB-702) to a read-only token

Publishing to registry.internal needs a token with scope `publish`. A read-only token gets `HTTP 401 {"error":"token lacks scope publish","ref":"RB-702"}` and curl exits 22. The publish-scoped token is the vault entry ops/vault/releasekit-registry; the release job failed because a stale read-only token on the build host shadowed it.

## Nothing under bin/ or .ci/ may source .env; secrets reach a job only through the vault

.env is a gitignored convenience for laptops. No script under bin/ or .ci/ may source or read it: CI injects every secret from the vault and that is the only path a secret takes into a job. .ci/publish.sh used to run `. ./.env` and a stale copy on the build host shadowed the injected token; the line is gone.

## curl against registry.internal needs --cacert /etc/releasekit/ca.pem on the build host (RB-715)

From the build host, curl rejects registry.internal with `curl: (60) SSL certificate problem: self-signed certificate in certificate chain`. Every curl against the registry passes `--cacert /etc/releasekit/ca.pem` (RB-715); .ci/publish.sh does so via `${REGISTRY_CA:-/etc/releasekit/ca.pem}`. The CI image trusts the CA system-wide, so this only bites a publish run by hand.

## A secret never gets a default: an unset REGISTRY_TOKEN exits 6 (RB-720)

No secret in releasekit has a default value — not in the Makefile, not in a script. .ci/publish.sh exits 6 with `publish: REGISTRY_TOKEN unset (RB-720)` when the variable is empty, and that is deliberate: a default is how a laptop token ends up in a release. A `REGISTRY_TOKEN ?= $(vault read ...)` line added to the Makefile was reverted for this reason.

## The registry token rotates on the 1st at 02:00 UTC; a 401 that day is the rotation (RB-708)

The vault entry ops/vault/releasekit-registry rotates on the first of every month at 02:00 UTC (RB-708). A 401 from registry.internal on the 1st is the rotation, not a bug: a job that started before 02:00 and published after it holds a dead lease. Nobody files anything for those; the job is rerun.
