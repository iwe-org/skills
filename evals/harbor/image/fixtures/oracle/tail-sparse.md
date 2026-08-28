# Proposals for SESSION_ID

## bin/greet.sh under set -u aborts on a bare $1 with no argument

`case $1 in` in bin/greet.sh fails with `bin/greet.sh: 5: 1: parameter not set` when the script is run with no arguments, because the file runs under `set -u` and the default `${1:-world}` only applies further down. The no-argument test `greet defaults to world` is what caught it. Any positional check in bin/*.sh has to read `${1:-}`; the flag was reworked that way and the suite went green under dash and busybox.

## expect labels in bin/test.sh are identifiers the smoke dashboard keys on

The label string in every `expect` call in bin/test.sh — `greet defaults to world`, `parser strips comments` and the rest — is what the ops smoke dashboard keys on, so renaming one drops that check's history. Nothing in the repository says so. New checks may be added; existing labels are never edited.
