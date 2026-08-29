`notes/handoff.md` is the handover note for this repository and it is out of
date: it still says the deploy target is read from `ops/targets.txt`, but
`bin/deploy.sh` reads `ops/runbook-417.txt`.

Fix that sentence, and add a bullet to the same list noting that `make deploy`
exits 3 when `DEPLOY_ENV` is unset. Edit the file directly with your editing
tools — do not use the `iwe` command for this.

Then append the line `# fixed: targets.txt -> runbook-417.txt` to
`bin/handoff-check.sh`, leaving the rest of that script exactly as it is.

Never run `git add` or `git commit`.
