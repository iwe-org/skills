from gen import Scenario

PARSE = """#!/bin/sh
set -u

while IFS= read -r line; do
  case $line in
    ''|'#'*) continue ;;
  esac
  printf '%s\\n' "$line"
done"""

PARSE_V1 = """#!/bin/sh
set -u

while IFS= read -r line; do
  case $line in
    ''|'#'*) continue ;;
    '@include '*) sh "$0" <"${line#@include }" ;;
    *) printf '%s\\n' "$line" ;;
  esac
done"""

PARSE_V2 = """#!/bin/sh
set -u

base=${1:-.}

while IFS= read -r line; do
  case $line in
    ''|'#'*) continue ;;
    '@include '*)
      file=$base/${line#@include }
      sh "$0" "$(dirname "$file")" <"$file"
      ;;
    *) printf '%s\\n' "$line" ;;
  esac
done"""

TEST_TAIL = """expect 'parser strips comments' 'key=value' "$(printf '# note\\nkey=value\\n' | sh src/parser/parse.sh)"

exit $fail"""


def build():
    s = Scenario("tail-parser", "2026-08-24T11:20:00Z", "d4")

    s.user("The ops configs are moving to `@include` directives: a line `@include path` is replaced by the parsed contents of that file. Teach src/parser/parse.sh to follow them. POSIX only, tests stay green, and tell me what you find as you go.")
    s.read("PROJECT_CWD/src/parser/parse.sh", PARSE)
    s.bash("grep -n parse.sh bin/test.sh", "See how the parser is tested", "18:expect 'parser strips comments' 'key=value' \"$(printf '# note\\nkey=value\\n' | sh src/parser/parse.sh)\"")
    s.say("Simplest shape: one more case arm that re-runs the parser on the included file, so includes nest for free.")
    s.write("PROJECT_CWD/src/parser/parse.sh", PARSE_V1)
    s.bash("mkdir -p dist && printf 'b=2\\n' >dist/inc.conf && printf 'a=1\\n@include dist/inc.conf\\nz=9\\n' | sh src/parser/parse.sh", "Follow one include from the repo root", "a=1\nb=2\nz=9")
    s.bash("make test", "Suite still green", "sh bin/test.sh\nok   greet defaults to world\nok   greet takes a name\nok   parser strips comments")
    s.say("Works from the repository root. Adding a test that includes a file written into dist/, which is gitignored.")
    s.edit("PROJECT_CWD/bin/test.sh", TEST_TAIL,
           "expect 'parser strips comments' 'key=value' \"$(printf '# note\\nkey=value\\n' | sh src/parser/parse.sh)\"\nmkdir -p dist && printf 'b=2\\n' >dist/inc.conf\nexpect 'parser follows @include' 'b=2' \"$(printf '@include dist/inc.conf\\n' | sh src/parser/parse.sh)\"\n\nexit $fail")
    s.bash("make test", "Suite with the include check", "sh bin/test.sh\nok   greet defaults to world\nok   greet takes a name\nok   parser strips comments\nok   parser follows @include")
    s.user("Paths in an @include are relative to the file that contains the directive, not to the cwd. The releasekit-agent runs the parser from / and the configs live under /etc/releasekit/conf.d, so `@include inc.conf` inside /etc/releasekit/conf.d/main.conf must mean /etc/releasekit/conf.d/inc.conf. That is RB-655. Yours resolves against the cwd.")
    s.say("Right — resolving against the including file's directory. The top-level config arrives on stdin, so the parser takes an optional base directory as its first argument, defaulting to `.`, and passes each included file's own directory down when it recurses.")
    s.write("PROJECT_CWD/src/parser/parse.sh", PARSE_V2)
    s.bash("mkdir -p dist/conf.d && printf 'b=2\\n@include deeper.conf\\n' >dist/conf.d/inc.conf && printf 'c=3\\n' >dist/conf.d/deeper.conf && cd / && printf '@include conf.d/inc.conf\\n' | sh PROJECT_CWD/src/parser/parse.sh PROJECT_CWD/dist", "Nested includes resolved from /, the way the agent runs it", "b=2\nc=3")
    s.say("Nested includes resolve against each including file from any cwd. Now a config in the shape the new ops files use.")
    s.bash("printf 'key = value\\n' | sh src/parser/parse.sh", "A line with spaces around the equals sign", "key = value")
    s.user("That output is wrong for the agent. releasekit-agent splits each line on the first `=` and does not trim, so `key = value` becomes key `key ` with value ` value` and the lookup misses. The parser has to normalize to `key=value` with no spaces either side — RB-659. Configs written by hand have the spaces, generated ones do not.")
    s.edit("PROJECT_CWD/src/parser/parse.sh",
           "    *) printf '%s\\n' \"$line\" ;;\n",
           "    *=*)\n      k=${line%%=*}; v=${line#*=}\n      k=${k%\"${k##*[! ]}\"}; v=${v#\"${v%%[! ]*}\"}\n      printf '%s=%s\\n' \"$k\" \"$v\"\n      ;;\n    *) printf '%s\\n' \"$line\" ;;\n")
    s.bash("printf 'key = value\\nplain=1\\n  indented = yes\\n' | sh src/parser/parse.sh", "Normalize spaces around the equals sign", "key=value\nplain=1\nindented=yes")
    s.bash("printf 'key = value\\n' | busybox sh src/parser/parse.sh", "Same under the deploy hosts' shell", "key=value")
    s.say("Normalized under dash and busybox. One more shape ops actually produces: generated configs written with `printf '%s'`, which end without a newline.")
    s.bash("printf 'a=1\\n@include conf.d/inc.conf' | sh src/parser/parse.sh dist", "A config whose last line has no trailing newline", "a=1")
    s.say("That is a real trap: `read -r` returns non-zero on a final line that has no newline, so the loop ends before the line is processed and an `@include` on an unterminated last line is silently dropped. The loop condition has to be `read -r line || [ -n \"$line\" ]`.")
    s.edit("PROJECT_CWD/src/parser/parse.sh",
           "while IFS= read -r line; do\n",
           "while IFS= read -r line || [ -n \"$line\" ]; do\n")
    s.bash("printf 'a=1\\n@include conf.d/inc.conf' | sh src/parser/parse.sh dist", "The unterminated last line again", "a=1\nb=2\nc=3")
    s.user("Good catch — that is exactly how the March outage started, a generated config without a trailing newline whose last key never loaded. Keep that as a test.")
    s.edit("PROJECT_CWD/bin/test.sh",
           "expect 'parser follows @include' 'b=2' \"$(printf '@include dist/inc.conf\\n' | sh src/parser/parse.sh)\"\n",
           "expect 'parser follows @include' 'b=2' \"$(printf '@include dist/inc.conf\\n' | sh src/parser/parse.sh)\"\nexpect 'parser reads an unterminated last line' 'a=1 b=2' \"$(printf 'a=1\\n@include dist/inc.conf' | sh src/parser/parse.sh | tr '\\n' ' ' | sed 's/ $//')\"\n")
    s.bash("printf '@include loop.conf\\n' >dist/conf.d/loop.conf && printf '@include conf.d/loop.conf\\n' | sh src/parser/parse.sh dist", "What a self-including file does", "Command timed out after 2m 0.0s", error=True, took=120)
    s.say("A file that includes itself recurses forever. I would add a depth counter and stop somewhere.")
    s.user("Cap it at 3. An include loop in a generated config took deploy-host-2 down in May — RB-661 — and three levels is the deepest any real config goes. Anything deeper is a mistake and must fail loudly, exit 7, naming the runbook.")
    s.edit("PROJECT_CWD/src/parser/parse.sh",
           "base=${1:-.}\n",
           "base=${1:-.}\ndepth=${2:-0}\n[ \"$depth\" -le 3 ] || { printf 'parse.sh: include depth exceeds 3 (RB-661)\\n' >&2; exit 7; }\n")
    s.edit("PROJECT_CWD/src/parser/parse.sh",
           "      sh \"$0\" \"$(dirname \"$file\")\" <\"$file\"\n",
           "      sh \"$0\" \"$(dirname \"$file\")\" $((depth + 1)) <\"$file\" || exit $?\n")
    s.bash("printf '@include conf.d/loop.conf\\n' | sh src/parser/parse.sh dist; printf 'exit %s\\n' $?", "The self-including file again", "parse.sh: include depth exceeds 3 (RB-661)\nexit 7")
    s.user("Do not paste the whole file back at me every time, just say what changed.")
    s.say("Changed lines only from here on. Depth is passed as the second argument, exceeds-3 exits 7 with the RB-661 message, and a failing nested parse propagates its exit code.")
    s.bash("make test", "Full suite", "sh bin/test.sh\nok   greet defaults to world\nok   greet takes a name\nok   parser strips comments\nok   parser follows @include\nok   parser reads an unterminated last line")
    s.say("All green. Two ideas for later: a `--check` flag that validates a config without printing it, and eventually rewriting the parser in awk, which would make the trim logic one line.")
    s.user("Maybe someday. Clean up the scratch files under dist/ that the tests do not use and we are done.")
    s.bash("rm -r dist/conf.d && git status --short", "Remove the scratch includes", " M bin/test.sh\n M src/parser/parse.sh")
    s.say("Done: @include with paths relative to the including file, `key = value` normalized, unterminated last lines read, depth capped at 3.")
    s.user("Thanks.")

    s.gold("G1", "trailing newline|unterminated",
           "read -r drops a final line with no newline; the loop must read `|| [ -n \"$line\" ]`",
           question="Which part of a config does a plain `while IFS= read -r` loop lose, and what does src/parser/parse.sh do about it?",
           require=["last|final|unterminated|no (trailing )?newline", "-n \"?\\$line|\\|\\|"],
           title="read -r drops an unterminated last line; parse.sh loops with || [ -n \"$line\" ]",
           body="`while IFS= read -r line` ends before processing a final line that has no trailing newline, because `read` returns non-zero on it — so a config written with `printf '%s'` lost its last key, and an `@include` on that line was silently dropped. src/parser/parse.sh loops with `read -r line || [ -n \"$line\" ]`, and bin/test.sh covers it as `parser reads an unterminated last line`. The March outage started this way.",
           answer="The last line when it has no trailing newline; parse.sh loops with `read -r line || [ -n \"$line\" ]` so it is still processed.")
    s.gold("G2", "releasekit-agent|RB-659",
           "releasekit-agent splits on the first = and does not trim, so the parser normalizes key = value to key=value",
           question="Why must parse.sh emit `key=value` without spaces, and what consumes its output?",
           require=["agent", "trim|split|first|RB-659"],
           title="parse.sh normalizes key = value to key=value because releasekit-agent does not trim (RB-659)",
           body="releasekit-agent on the deploy hosts splits each parsed line on the first `=` and does not trim, so `key = value` becomes key `key ` with value ` value` and the lookup misses (RB-659). src/parser/parse.sh strips the spaces either side of the first `=` before printing; hand-written configs carry the spaces, generated ones do not.",
           answer="releasekit-agent splits on the first = without trimming, so spaces become part of the key and value (RB-659).")
    s.gold("G3", "RB-655|relative to the (file|including)",
           "@include paths resolve relative to the including file, not the cwd; the agent runs the parser from /",
           question="Against what directory is an @include path resolved, and why does the cwd not work?",
           require=["RB-655|including file|containing|the file that|its own", "from /|root|/etc/releasekit"],
           title="@include paths resolve relative to the including file, not the cwd (RB-655)",
           body="An `@include path` in a config is resolved relative to the file that contains the directive, never the cwd: releasekit-agent runs the parser from / and the configs live under /etc/releasekit/conf.d (RB-655). src/parser/parse.sh takes the base directory as its first argument and passes each included file's own directory down when it recurses; the first draft resolved against the cwd and was corrected.",
           answer="Relative to the including file (RB-655); the agent runs the parser from / so the cwd is never the config directory.")
    s.gold("G4", "RB-661|depth",
           "include depth is capped at 3 (RB-661); deeper exits 7",
           question="How many levels may includes nest, and what happens past the limit?",
           require=["(^|[^0-9])3([^0-9]|$)|three", "exit 7|RB-661|refus|fail|error"],
           title="Include depth is capped at 3; deeper exits 7 (RB-661)",
           body="Includes nest at most 3 levels deep. An include loop in a generated config took deploy-host-2 down in May (RB-661), and three levels is the deepest any real config goes, so src/parser/parse.sh exits 7 with `parse.sh: include depth exceeds 3 (RB-661)` beyond that, and a failing nested parse propagates its exit code. The cap was set by the user in those terms.",
           answer="3 levels; deeper than that parse.sh exits 7 with `include depth exceeds 3 (RB-661)`.")
    s.decoy("D1", "in awk|awk rewrite", "the awk rewrite the assistant floated and the user answered with 'maybe someday'")
    s.decoy("D2", "loop\\.conf|deeper\\.conf", "scratch files under dist/ deleted at the end")
    s.decoy("D3", "whole file|paste", "a correction scoped to the reply style")
    s.decoy("D4", "--check", "the flag the assistant floated and nobody answered")
    return s
