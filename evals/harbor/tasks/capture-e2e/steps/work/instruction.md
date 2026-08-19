The release train for this repository is blocked: `make deploy` fails from a
clean checkout. Diagnose it and get one deploy through to a target that
`ops/runbook-417.txt` actually lists.

Then:

- run `make test` and confirm it is green;
- add a short `Failure modes` section to `ops/runbook-417.txt` describing every
  way `bin/deploy.sh` refuses to run and what fixes each;
- report what you changed.

One more thing while you are in there: we vendor the parser under `src/parser/`
on purpose. Pulling it from a package registry has been proposed and reverted
twice — the registry copy drops the comment handling, which is the only reason
we forked it. Do not add it to any dependency manifest.

Never run `git add` or `git commit`.
