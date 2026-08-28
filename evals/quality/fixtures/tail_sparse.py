from gen import Scenario

GREET = """#!/bin/sh
set -u

name=${1:-world}
msg="hello, $name"
printf '%s\\n' "$msg\""""

TEST = """#!/bin/sh
set -u

fail=0

expect() {
  if [ "$2" = "$3" ]; then
    printf 'ok   %s\\n' "$1"
  else
    printf 'FAIL %s: expected [%s] got [%s]\\n' "$1" "$2" "$3"
    fail=1
  fi
}

expect 'greet defaults to world' 'hello, world' "$(sh bin/greet.sh)"
expect 'greet takes a name' 'hello, ada' "$(sh bin/greet.sh ada)"
expect 'parser strips comments' 'key=value' "$(printf '# note\\nkey=value\\n' | sh src/parser/parse.sh)"

exit $fail"""


def build():
    s = Scenario("tail-sparse", "2026-08-19T14:10:00Z", "a1")

    s.user("Add an --upper flag to bin/greet.sh that upper-cases the greeting, with a test in bin/test.sh. Small change, keep it POSIX, and walk me through it.")
    s.say("Reading greet.sh and the test harness before touching anything.")
    s.read("PROJECT_CWD/bin/greet.sh", GREET)
    s.read("PROJECT_CWD/bin/test.sh", TEST)
    s.say("Two-line change: recognise `--upper` as the first argument, then upper-case the message with `tr` so it stays POSIX.")
    s.edit("PROJECT_CWD/bin/greet.sh",
           "name=${1:-world}\n",
           "upper=0\ncase $1 in\n  --upper) upper=1; shift ;;\nesac\nname=${1:-world}\n")
    s.edit("PROJECT_CWD/bin/greet.sh",
           "msg=\"hello, $name\"\n",
           "msg=\"hello, $name\"\n[ \"$upper\" = 0 ] || msg=$(printf '%s' \"$msg\" | tr '[:lower:]' '[:upper:]')\n")
    s.bash("sh bin/greet.sh --upper ada", "Try the new flag", "HELLO, ADA")
    s.bash("make test", "Run the suite with the flag in place",
           "sh bin/test.sh\nbin/greet.sh: 5: 1: parameter not set\nFAIL greet defaults to world: expected [hello, world] got []\nok   greet takes a name\nok   parser strips comments\nmake: *** [Makefile:7: test] Error 1", error=True)
    s.say("That is the trap: greet.sh runs under `set -u`, and `case $1 in` with no argument at all aborts with `bin/greet.sh: 5: 1: parameter not set` before the default ever applies — so the no-argument test broke. The check has to read `${1:-}`.")
    s.edit("PROJECT_CWD/bin/greet.sh", "case $1 in\n", "case ${1:-} in\n")
    s.bash("sh bin/greet.sh && sh bin/greet.sh --upper && sh bin/greet.sh --upper ada", "Exercise every argument shape",
           "hello, world\nHELLO, WORLD\nHELLO, ADA")
    s.bash("busybox sh bin/greet.sh --upper ada", "Confirm it parses and runs under the deploy hosts' shell", "HELLO, ADA")
    s.say("Works with no arguments, with the flag alone, and with both, under dash and under busybox. Adding the test.")
    s.edit("PROJECT_CWD/bin/test.sh",
           "expect 'greet takes a name' 'hello, ada' \"$(sh bin/greet.sh ada)\"\n",
           "expect 'greet takes a name' 'hello, ada' \"$(sh bin/greet.sh ada)\"\nexpect 'greet upper-cases with --upper' 'HELLO, ADA' \"$(sh bin/greet.sh --upper ada)\"\n")
    s.bash("make test", "Run the suite with the new check",
           "sh bin/test.sh\nok   greet defaults to world\nok   greet takes a name\nok   greet upper-cases with --upper\nok   parser strips comments")
    s.say("Four checks green, up from three. While I am in bin/test.sh: the expect labels are free text, and I would convert the runner to TAP output so CI can count the plan and name failures by number.")
    s.user("Not now. And do not rename any of the expect labels while you are in there — the smoke dashboard keys on the label text. `greet defaults to world` and the rest are identifiers as far as ops is concerned; renaming one drops its history on the dashboard. Nothing in the repo says that, which is why I am saying it.")
    s.say("Understood: the expect labels are stable identifiers the smoke dashboard keys on. The new one stays as written and none of the existing ones change.")
    s.user("Also, keep the replies shorter — I do not need the narration.")
    s.say("Will do.")
    s.bash("git diff --stat", "Size of the change", " bin/greet.sh | 5 ++++-\n bin/test.sh  | 1 +\n 2 files changed, 5 insertions(+), 1 deletion(-)")
    s.bash("make build", "Check the bundle still assembles", "sh bin/build.sh\nbuild.sh: wrote dist/releasekit.tar.gz")
    s.bash("ls -l dist/releasekit.tar.gz", "Bundle size after the change", "-rw-r--r--  1 build build 4126 Aug 19 14:31 dist/releasekit.tar.gz")
    s.say("Bundle is 4126 bytes, same shape as before. Diff is two files, six lines.")
    s.user("I will commit this myself on a branch called wip/greet-upper so I can read it on the train; ignore that branch if you see it later, it dies after the merge.")
    s.say("Noted. One more thought: greet.sh could be renamed hello.sh to match what it prints, since nothing else references the name.")
    s.user("Run the tests once more and we are done.")
    s.bash("make test", "Final run",
           "sh bin/test.sh\nok   greet defaults to world\nok   greet takes a name\nok   greet upper-cases with --upper\nok   parser strips comments")
    s.say("Green. `--upper` is in, guarded by `${1:-}` because of `set -u`; one new test; every existing label untouched.")
    s.user("Good, thanks.")

    s.gold("G1", "parameter not set",
           "set -u aborts greet.sh on a bare $1 when no argument is given; the check must read ${1:-}",
           question="What broke in bin/greet.sh when the new flag was checked with a bare positional, and what is the fix?",
           require=["parameter not set|set -u", "1:-"],
           title="bin/greet.sh under set -u aborts on a bare $1 with no argument",
           body="`case $1 in` in bin/greet.sh fails with `bin/greet.sh: 5: 1: parameter not set` when the script is run with no arguments, because the file runs under `set -u` and the default `${1:-world}` only applies further down. The no-argument test `greet defaults to world` is what caught it. Any positional check in bin/*.sh has to read `${1:-}`; the flag was reworked that way and the suite went green under dash and busybox.",
           answer="Under set -u a bare $1 aborts with `1: parameter not set` when nothing is passed; the check reads `${1:-}` instead.")
    s.gold("G2", "dashboard",
           "expect labels in bin/test.sh are identifiers the smoke dashboard keys on; never rename one",
           question="Why must the strings passed to expect in bin/test.sh never be changed once they exist?",
           require=["dashboard"],
           title="expect labels in bin/test.sh are identifiers the smoke dashboard keys on",
           body="The label string in every `expect` call in bin/test.sh — `greet defaults to world`, `parser strips comments` and the rest — is what the ops smoke dashboard keys on, so renaming one drops that check's history. Nothing in the repository says so. New checks may be added; existing labels are never edited.",
           answer="The smoke dashboard keys on the label text, so renaming one loses that check's history.")
    s.decoy("D1", "TAP output|to TAP", "assistant's TAP-output suggestion, answered with 'not now'")
    s.decoy("D2", "4126", "today's bundle size")
    s.decoy("D3", "shorter|narration", "a correction scoped to the reply style, not the project")
    s.decoy("D4", "wip/greet-upper", "a branch the user will delete after merge")
    s.decoy("D5", "hello\\.sh", "the rename the assistant floated and nobody answered")
    return s
