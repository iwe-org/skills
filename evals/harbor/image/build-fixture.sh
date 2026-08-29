#!/bin/sh
set -eu

dest=${1:-}
repo=${2:-}

if [ -z "$dest" ] || [ -z "$repo" ]; then
  printf 'usage: build-fixture.sh <dest> <skills-repo-root>\n' >&2
  exit 2
fi
[ -f "$repo/hooks/hooks.json" ] || {
  printf 'build-fixture: %s is not the skills repository\n' "$repo" >&2
  exit 2
}

rm -rf "$dest"
mkdir -p "$dest/bin" "$dest/ops" "$dest/src/parser" "$dest/.claude/skills"

cat >"$dest/README.md" <<'EOF'
# releasekit

Release tooling for the platform team. Everything here is POSIX shell, so there
is nothing to install and nothing to build a container for.

| command | what it does |
|---|---|
| `make build` | assemble the release bundle into `dist/` |
| `make test` | run the shell test suite |
| `make deploy` | push the current bundle to a deploy target |

The bundle format is the tarball `dist/releasekit.tar.gz`; `bin/build.sh`
writes it and `bin/deploy.sh` consumes it. Operational procedures that are not
part of the code live under `ops/`.
EOF

cat >"$dest/CLAUDE.md" <<'EOF'
# CLAUDE.md

Guidance for agents working in this repository.

## Project

`releasekit` is the platform team's release tooling. POSIX shell only — no
package manager, no build step beyond `make build`.

## Rules

- Never run `git add` or `git commit`. Every change is reviewed as a diff.
- Keep `bin/*.sh` POSIX; the deploy hosts have no bash.

## Project memory

This repository is an IWE workspace, and durable notes from past sessions live
in it as ordinary markdown. Before starting a task, check whether it already
knows something:

```bash
iwe find --lexical "<terms about the task>" --limit 5
iwe retrieve -k <key>
```

Run these from the repository root, as plain `iwe` commands — the workspace is
the store. The `MEMORY.md` document says what is kept here and how it is
written.
EOF

cat >"$dest/Makefile" <<'EOF'
.POSIX:

build:
	sh bin/build.sh

test:
	sh bin/test.sh

deploy:
	sh bin/deploy.sh

.PHONY: build test deploy
EOF

cat >"$dest/.gitignore" <<'EOF'
dist/
.deploy-receipt
.deploy-attempts
.eval/
EOF

cat >"$dest/bin/build.sh" <<'EOF'
#!/bin/sh
set -eu

mkdir -p dist
tar czf dist/releasekit.tar.gz bin ops src
printf 'build.sh: wrote dist/releasekit.tar.gz\n'
EOF

cat >"$dest/bin/greet.sh" <<'EOF'
#!/bin/sh
set -u

name=${1:-world}
msg="hello, $name"
printf '%s\n' "$msg"
EOF

cat >"$dest/bin/test.sh" <<'EOF'
#!/bin/sh
set -u

fail=0

expect() {
  if [ "$2" = "$3" ]; then
    printf 'ok   %s\n' "$1"
  else
    printf 'FAIL %s: expected [%s] got [%s]\n' "$1" "$2" "$3"
    fail=1
  fi
}

expect 'greet defaults to world' 'hello, world' "$(sh bin/greet.sh)"
expect 'greet takes a name' 'hello, ada' "$(sh bin/greet.sh ada)"
expect 'parser strips comments' 'key=value' "$(printf '# note\nkey=value\n' | sh src/parser/parse.sh)"

exit $fail
EOF

cat >"$dest/bin/deploy.sh" <<'EOF'
#!/bin/sh
set -u

target=${DEPLOY_ENV:-}
printf '%s %s\n' "$(date -u '+%H:%M:%S')" "${target:-<unset>}" >>.deploy-attempts

# How many times a push is retried while the load balancer drains a node.
RETRY_BUDGET=${RETRY_BUDGET:-3}

if [ ! -f dist/releasekit.tar.gz ]; then
  printf 'deploy.sh: refusing to run: dist/releasekit.tar.gz is missing, run make build first\n' >&2
  exit 2
fi

if [ -z "$target" ]; then
  printf 'deploy.sh: refusing to run: DEPLOY_ENV is unset (RB-417)\n' >&2
  exit 3
fi

known=$(sed -n 's/^  target: //p' ops/runbook-417.txt 2>/dev/null)
for candidate in $known; do
  if [ "$candidate" = "$target" ]; then
    attempt=0
    while [ "$attempt" -lt "$RETRY_BUDGET" ]; do
      attempt=$((attempt + 1))
      printf '%s\n' "$target" >.deploy-receipt
      printf 'deploy.sh: deployed dist/releasekit.tar.gz to %s\n' "$target"
      exit 0
    done
    printf 'deploy.sh: gave up after %s attempt(s)\n' "$RETRY_BUDGET" >&2
    exit 5
  fi
done

printf "deploy.sh: unknown deploy target '%s' (RB-417)\n" "$target" >&2
exit 4
EOF

cat >"$dest/ops/runbook-417.txt" <<'EOF'
RB-417 — deploy targets

Every deploy is gated on the DEPLOY_ENV environment variable. bin/deploy.sh
reads the list below and refuses anything that is not on it.

  target: staging-blue
  target: staging-green

Rotations and freezes are announced in the release channel, not here.
EOF

cat >"$dest/src/parser/parse.sh" <<'EOF'
#!/bin/sh
set -u

while IFS= read -r line; do
  case $line in
    ''|'#'*) continue ;;
  esac
  printf '%s\n' "$line"
done
EOF

cat >"$dest/src/parser/README.md" <<'EOF'
# parser

Reads a config stream on stdin and prints the significant lines.
EOF

chmod +x "$dest"/bin/*.sh "$dest/src/parser/parse.sh"

sh "$(dirname -- "$0")/render-settings.sh" "$repo/hooks/hooks.json" \
  "$dest/.claude/settings.json"

for skill in init distill reflect; do
  mkdir -p "$dest/.claude/skills/$skill"
  cp -R "$repo/skills/$skill/." "$dest/.claude/skills/$skill/"
done

git -C "$dest" init -q -b main
git -C "$dest" add -A
GIT_AUTHOR_NAME=releasekit GIT_AUTHOR_EMAIL=releasekit@example.com \
  GIT_COMMITTER_NAME=releasekit GIT_COMMITTER_EMAIL=releasekit@example.com \
  GIT_AUTHOR_DATE='2026-01-05T09:00:00+00:00' GIT_COMMITTER_DATE='2026-01-05T09:00:00+00:00' \
  git -C "$dest" commit -q -m 'releasekit at rest'

printf 'build-fixture: wrote %s\n' "$dest"
