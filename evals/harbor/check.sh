#!/bin/sh
set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
HARBOR=$ROOT/evals/harbor
TASKS=$HARBOR/tasks
WORK=$(mktemp -d "${TMPDIR:-/tmp}/iwe-harbor-check.XXXXXX") || exit 1
KEEP=${IWE_EVAL_KEEP:-0}
ONLY=${1:-}

cleanup() {
  [ "$KEEP" = "1" ] || rm -rf "$WORK"
  [ "$KEEP" = "0" ] || printf 'work kept in %s\n' "$WORK"
}
trap cleanup EXIT INT TERM

passed=0
failed=0

ok() {
  passed=$((passed + 1))
  printf 'ok   %s\n' "$1"
}

no() {
  failed=$((failed + 1))
  printf 'FAIL %s\n' "$1"
  [ "$#" -lt 2 ] || printf '     %s\n' "$2"
}

assert_equal() {
  if [ "$2" = "$3" ]; then
    ok "$1"
  else
    no "$1" "expected [$2] got [$3]"
  fi
}

assert_contains() {
  case $3 in
    *"$2"*) ok "$1" ;;
    *) no "$1" "does not contain [$2]" ;;
  esac
}

assert_file() {
  if [ -f "$2" ]; then
    ok "$1"
  else
    no "$1" "$2 is missing"
  fi
}

step_names() {
  awk '
    /^\[\[steps\]\]/ { instep = 1; next }
    instep && $1 == "name" {
      sub(/^[^=]*=[ \t]*"/, "")
      sub(/"[ \t]*$/, "")
      print
      instep = 0
    }
  ' "$1"
}

task_dirs() {
  for dir in "$TASKS"/*; do
    [ -d "$dir" ] || continue
    [ -z "$ONLY" ] || [ "${dir##*/}" = "$ONLY" ] || continue
    printf '%s\n' "$dir"
  done
}

printf '# shell scripts parse\n'

for script in "$HARBOR/check.sh" "$HARBOR/gate.sh" "$HARBOR/report.sh" "$HARBOR/lib/assert.sh" \
  "$HARBOR/image/setup-lib.sh" "$HARBOR/image/build-fixture.sh" "$HARBOR/image/render-settings.sh" \
  "$HARBOR/image/marker.sh" "$ROOT/evals/quality/propose.sh" "$ROOT/evals/quality/mint-gold.sh"; do
  if sh -n "$script" 2>/dev/null; then
    ok "sh -n ${script#$ROOT/}"
  else
    no "sh -n ${script#$ROOT/}"
  fi
done

printf '# the shipped configuration is well formed\n'

if command -v jq >/dev/null 2>&1; then
  for json in "$ROOT/hooks/hooks.json"; do
    if jq -e . "$json" >/dev/null 2>&1; then
      ok "${json#$ROOT/} is valid JSON"
    else
      no "${json#$ROOT/} is valid JSON"
    fi
  done
else
  printf 'skip the shipped configuration checks: jq is not on PATH\n'
fi
assert_contains "the hook runs the binary's session-start" 'iwe internal claude hook session-start' \
  "$(cat "$ROOT/hooks/hooks.json")"
case $(cat "$ROOT/hooks/hooks.json") in
  *--footer*|*--capture-reason*|*--maintenance-reason*)
    no "the hooks are bare one-liners; the binary carries the default strings" ;;
  *) ok "the hooks are bare one-liners; the binary carries the default strings" ;;
esac
# Nothing reads a transcript unattended any more: the plugin installs two
# hooks, session-start and the post-tool net, and neither writes a memory
# document or moves a distilled line. A Stop entry reinstating the sweep is the
# regression to catch.
case $(cat "$ROOT/hooks/hooks.json") in
  *'"Stop"'*) no "the manifest declares no Stop hook" ;;
  *) ok "the manifest declares no Stop hook" ;;
esac
case $(cat "$ROOT/hooks/hooks.json") in
  *SessionEnd*) no "the manifest declares no SessionEnd hook" ;;
  *) ok "the manifest declares no SessionEnd hook" ;;
esac
if command -v jq >/dev/null 2>&1; then
  events=$(jq -r '.hooks | keys | sort | join(",")' "$ROOT/hooks/hooks.json" 2>/dev/null)
  assert_equal "the only hook events are session start and the post-tool net" \
    "PostToolUse,SessionStart" "$events"
  matcher=$(jq -r '.hooks.PostToolUse[0].matcher' "$ROOT/hooks/hooks.json" 2>/dev/null)
  assert_equal "the net watches the writing tools and Bash" \
    "Write|Edit|MultiEdit|Bash" "$matcher"
  case $(jq -r '.hooks.PostToolUse[0].hooks[0].command' "$ROOT/hooks/hooks.json") in
    *'|| true') ok "the net never fails the tool call it follows" ;;
    *) no "the net never fails the tool call it follows" ;;
  esac
fi
if [ -e "$ROOT/agents" ]; then
  no "no background agent ships with the plugin" "$ROOT/agents still exists"
else
  ok "no background agent ships with the plugin"
fi
case $(cat "$ROOT/hooks/hooks.json") in
  *CLAUDE_PLUGIN_ROOT*|*jq*) no "the hook commands need no plugin root and no jq" ;;
  *) ok "the hook commands need no plugin root and no jq" ;;
esac

printf '# verifier helpers\n'

helper_verdict() {
  ( IWE_EVAL_APP=$1
    IWE_EVAL_LOGS=$2
    export IWE_EVAL_APP IWE_EVAL_LOGS
    . "$HARBOR/lib/assert.sh"
    if agent_launched distill; then printf 'launched\n'; else printf 'quiet\n'; fi )
}

helpers=$WORK/helpers
mkdir -p "$helpers/app" "$helpers/logs/agent"
stream=$helpers/logs/agent/claude-code.txt
printf '%s\n' '{"type":"system","subtype":"init","agents":["distill"],"tools":["Agent","Bash"]}' >"$stream"
assert_equal "the agent roster in a session init is not a launch" quiet \
  "$(helper_verdict "$helpers/app" "$helpers/logs")"
printf '%s\n' '{"type":"user","message":{"content":"the distill skill runs in the foreground and spawns nothing"}}' >>"$stream"
assert_equal "prose naming the skill is not a launch" quiet \
  "$(helper_verdict "$helpers/app" "$helpers/logs")"
# The verifiers assert the *absence* of this, so the detector has to be able to
# see one: a distill subagent is exactly what the foreground flow must not do.
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Agent","input":{"subagent_type":"distill","run_in_background":true,"prompt":"work the queue"}}]}}' >>"$stream"
assert_equal "an Agent tool call is a launch" launched \
  "$(helper_verdict "$helpers/app" "$helpers/logs")"

api_error_verdict() {
  ( IWE_EVAL_APP=$1
    IWE_EVAL_LOGS=$2
    export IWE_EVAL_APP IWE_EVAL_LOGS
    . "$HARBOR/lib/assert.sh"
    if agent_api_error; then printf 'poisoned\n'; else printf 'clean\n'; fi )
}

assert_equal "an ordinary session is not flagged as an API failure" clean \
  "$(api_error_verdict "$helpers/app" "$helpers/logs")"
printf '%s\n' '{"type":"result","subtype":"error_during_execution","api_error_status":400,"error":"Credit balance is too low"}' >>"$stream"
assert_equal "a credit-exhausted session is flagged" poisoned \
  "$(api_error_verdict "$helpers/app" "$helpers/logs")"

printf '# the image writes settings from the shipped hook manifest\n'

rendered=$WORK/settings.json
sh "$HARBOR/image/render-settings.sh" "$ROOT/hooks/hooks.json" "$rendered"
assert_equal "the settings are the manifest verbatim" "$(cat "$ROOT/hooks/hooks.json")" "$(cat "$rendered")"
assert_contains "the rendered hooks point at the binary" 'iwe internal claude hook session-start' \
  "$(cat "$rendered")"

printf '# the image has everything it bakes in\n'

assert_file "the build context is filtered" "$ROOT/.dockerignore"
for pattern in 'private/' '.git/'; do
  assert_contains "and excludes $pattern" "$pattern" "$(cat "$ROOT/.dockerignore" 2>/dev/null)"
done

for input in hooks/hooks.json \
  skills/init/SKILL.md skills/distill/SKILL.md skills/reflect/SKILL.md; do
  assert_file "the image can copy $input" "$ROOT/$input"
done

printf '# the seeded transcripts are readable\n'

for fixture in "$HARBOR"/image/fixtures/*.jsonl; do
  lines=$(grep -c . "$fixture")
  if [ "$lines" -gt 0 ]; then
    ok "${fixture##*/} carries $lines lines"
  else
    no "${fixture##*/} carries $lines lines"
  fi
  if node -e 'const fs=require("fs");for(const l of fs.readFileSync(process.argv[1],"utf8").split("\n"))if(l.trim())JSON.parse(l)' "$fixture" 2>/dev/null; then
    ok "${fixture##*/} is valid JSONL"
  elif command -v node >/dev/null 2>&1; then
    no "${fixture##*/} is valid JSONL"
  else
    printf 'skip %s is valid JSONL: node is not on PATH\n' "${fixture##*/}"
  fi
done

# The phantom-decision fixture is the whole reason capture became manual: an
# assistant recommendation the user answered with "leave it alone". If the
# argument or the refusal ever falls out of it, distill-current stops testing
# anything.
phantom=$HARBOR/image/fixtures/tail-phantom.jsonl
assert_contains "the phantom fixture carries the recommendation" 'RETRY_BUDGET' "$(cat "$phantom")"
assert_contains "and the refusal that answers it" 'Leave deploy.sh alone' "$(cat "$phantom")"
assert_contains "and a fact the user did confirm" 'DEPLOY_ENV is unset' "$(cat "$phantom")"
# And the half that makes it more than a refusal: the same recommendation put
# up a second time, which the user answers by changing the subject.
assert_contains "and a second recommendation nobody answered" 'Different subject' "$(cat "$phantom")"
recommendations=$(grep -c 'RETRY_BUDGET' "$phantom")
if [ "$recommendations" -ge 3 ]; then
  ok "the phantom fixture argues the retry budget more than once"
else
  no "the phantom fixture argues the retry budget more than once" "$recommendations mention(s)"
fi

printf '# the gold sets label what their fixtures carry\n'

# A gold row whose pattern the transcript no longer contains would cap recall
# below 1.0 for every run and read as a regression in the skill. So every
# pattern has to compile and has to occur in its fixture, and each labelled
# fixture needs something to keep and something to leave out.
tab=$(printf '\t')
for gold in "$HARBOR"/image/fixtures/gold/*.tsv; do
  [ -f "$gold" ] || continue
  name=${gold##*/}
  name=${name%.tsv}
  fixture=$HARBOR/image/fixtures/$name.jsonl
  assert_file "gold/$name.tsv labels a fixture that exists" "$fixture"
  [ -f "$fixture" ] || continue
  flat=$WORK/$name.flat
  tr '\n' ' ' <"$fixture" >"$flat"
  golds=0
  decoys=0
  while IFS="$tab" read -r id class pattern note; do
    case $id in
      ''|'#'*) continue ;;
    esac
    case $class in
      gold) golds=$((golds + 1)) ;;
      decoy|secret) decoys=$((decoys + 1)) ;;
      *) no "gold/$name.tsv row $id has a known class" "$class" ; continue ;;
    esac
    if printf 'x\n' | grep -qiE -- "$pattern" 2>/dev/null; [ $? -le 1 ]; then
      ok "gold/$name.tsv $id compiles"
    else
      no "gold/$name.tsv $id compiles" "$pattern"
    fi
    if grep -qiE -- "$pattern" "$flat" 2>/dev/null; then
      ok "gold/$name.tsv $id occurs in the fixture"
    else
      no "gold/$name.tsv $id occurs in the fixture" "$pattern"
    fi
  done <"$gold"
  if [ "$golds" -gt 0 ] && [ "$decoys" -gt 0 ]; then
    ok "gold/$name.tsv has $golds gold and $decoys decoy row(s)"
  else
    no "gold/$name.tsv has $golds gold and $decoys decoy row(s)" "both classes are needed"
  fi
done

distractors=$(grep -c '^[^#].*|' "$HARBOR/image/fixtures/distractors.txt" 2>/dev/null)
if [ "${distractors:-0}" -ge 50 ]; then
  ok "the distractor corpus carries $distractors documents"
else
  no "the distractor corpus carries $distractors documents" "fewer than 50"
fi

printf '# every labelled fixture carries a question set and an oracle\n'

# A labelled fixture is measurable end to end only when three files agree: the
# gold set says what to keep, the question set asks one question per gold item
# with answer patterns that avoid the question's own words, and the oracle
# proposes exactly the gold items in the shape a good document has. The oracle
# is scored here with the same helpers the verifiers use, and has to reach
# recall 1.0, precision 1.0 and no decoy, secret or fold — a gold row no oracle
# can hit would cap every model run below 1.0 and read as a regression.
score_oracle() {
  ( IWE_EVAL_APP=$WORK/oracle-self/app
    IWE_EVAL_LOGS=$WORK/oracle-self/logs
    IWE_EVAL_FIXTURES=$HARBOR/image/fixtures
    export IWE_EVAL_APP IWE_EVAL_LOGS IWE_EVAL_FIXTURES
    . "$HARBOR/lib/assert.sh"
    units=$WORK/oracle-self/units-$1
    gold_split_proposals "$HARBOR/image/fixtures/oracle/$1.md" "$units"
    gold_eval "$1" "$units"
    printf '%s %s %s %s %s\n' \
      "$(gold_fraction "$(gold_stat "$units" gold_hits)" "$(gold_stat "$units" gold_total)")" \
      "$(gold_fraction "$(gold_stat "$units" units_on_gold)" "$(gold_stat "$units" units)")" \
      "$(gold_stat "$units" decoy_units)" "$(gold_stat "$units" secret_units)" "$(gold_stat "$units" folded_units)" )
}
oracle_answers_ok() {
  ( IWE_EVAL_APP=$WORK/oracle-self/app
    IWE_EVAL_LOGS=$WORK/oracle-self/logs
    IWE_EVAL_FIXTURES=$HARBOR/image/fixtures
    IWE_EVAL_SESSION_DIR=$WORK/oracle-self/logs
    export IWE_EVAL_APP IWE_EVAL_LOGS IWE_EVAL_FIXTURES IWE_EVAL_SESSION_DIR
    . "$HARBOR/image/setup-lib.sh"
    . "$HARBOR/lib/assert.sh"
    answers=$WORK/oracle-self/answers-$1.txt
    eval_oracle_answers "$1" >"$answers"
    n=$(bank_question_count "$1")
    printf '%s/%s\n' "$(bank_hits "$answers" "$n" "$1")" "$n" )
}
mkdir -p "$WORK/oracle-self/app" "$WORK/oracle-self/logs"
for gold in "$HARBOR"/image/fixtures/gold/*.tsv; do
  [ -f "$gold" ] || continue
  name=${gold##*/}
  name=${name%.tsv}
  questions=$HARBOR/image/fixtures/questions/$name.tsv
  oracle=$HARBOR/image/fixtures/oracle/$name.md
  assert_file "questions/$name.tsv exists" "$questions"
  assert_file "oracle/$name.md exists" "$oracle"
  [ -f "$questions" ] && [ -f "$oracle" ] || continue
  golds=$(awk -F'\t' '!/^[ \t]*#/ && NF >= 3 && $2 == "gold"' "$gold" | grep -c .)
  gold_questions=$(awk -F'\t' '!/^[ \t]*#/ && NF >= 3 && $2 == "gold"' "$questions" | grep -c .)
  assert_equal "questions/$name.tsv asks one question per gold item" "$golds" "$gold_questions"
  # Rows are read with awk, field by field: `read` with a tab IFS collapses
  # the empty forbid column a gold row carries, and `awk -v` would expand the
  # backslashes a pattern needs.
  question_field() {
    awk -F'\t' -v n="$1" -v col="$2" '!/^[ \t]*#/ && NF >= 3 && $1 == n { print $col; exit }' "$questions"
  }
  for n in $(awk -F'\t' '!/^[ \t]*#/ && NF >= 3 { print $1 }' "$questions"); do
    class=$(question_field "$n" 2)
    case $class in
      gold|stale) ;;
      *) no "questions/$name.tsv row $n has a known class" "$class"; continue ;;
    esac
    [ -n "$(question_field "$n" 4)" ] || no "questions/$name.tsv row $n requires something"
    [ -n "$(question_field "$n" 6)" ] || no "questions/$name.tsv row $n carries an oracle answer"
    printf '%s;;%s\n' "$(question_field "$n" 4)" "$(question_field "$n" 5)" |
      awk '{ n = split($0, a, ";;"); for (i = 1; i <= n; i++) if (a[i] != "") print a[i] }' >"$WORK/oracle-self/patterns"
    while IFS= read -r pattern; do
      if printf 'x\n' | grep -qiE -- "$pattern" 2>/dev/null; [ $? -le 1 ]; then
        ok "questions/$name.tsv row $n pattern compiles: $pattern"
      else
        no "questions/$name.tsv row $n pattern compiles" "$pattern"
      fi
    done <"$WORK/oracle-self/patterns"
  done
  assert_equal "oracle/$name.md scores recall 1, precision 1, no decoy, no secret, no fold" "1.0000 1.0000 0 0 0" "$(score_oracle "$name")"
  answered=$(oracle_answers_ok "$name")
  assert_equal "the oracle answers pass every question of $name" "${answered#*/}/${answered#*/}" "$answered"
done

# The four generated fixtures are committed as data; the generator that wrote
# them lives in evals/quality/fixtures/. When python3 is around, regenerate
# into scratch and compare, so an edit to a scenario is never committed
# without its fixture and vice versa.
if command -v python3 >/dev/null 2>&1; then
  mkdir -p "$WORK/gen"
  if GEN_OUT=$WORK/gen python3 "$ROOT/evals/quality/fixtures/gen.py" >"$WORK/gen.log" 2>&1; then
    ok "the fixture generator runs clean"
    for generated in $(cd "$WORK/gen" && find . -type f | sort); do
      generated=${generated#./}
      if cmp -s "$WORK/gen/$generated" "$HARBOR/image/fixtures/$generated"; then
        ok "generated $generated matches the committed file"
      else
        no "generated $generated matches the committed file" "run python3 evals/quality/fixtures/gen.py"
      fi
    done
  else
    no "the fixture generator runs clean" "$(tail -3 "$WORK/gen.log")"
  fi
else
  printf 'skip the fixture generator: python3 is not on PATH\n'
fi

# The scorer itself, on two hand-made units: one on gold, one a decoy that
# also leaks the secret, so every counter it keeps is exercised.
gold_verdict() {
  ( IWE_EVAL_APP=$WORK/gold-self/app
    IWE_EVAL_LOGS=$WORK/gold-self/logs
    IWE_EVAL_FIXTURES=$HARBOR/image/fixtures
    export IWE_EVAL_APP IWE_EVAL_LOGS IWE_EVAL_FIXTURES
    . "$HARBOR/lib/assert.sh"
    units=$WORK/gold-self/units
    gold_split_proposals "$WORK/gold-self/proposals.md" "$units"
    gold_eval tail-dense "$units"
    printf '%s %s %s %s %s %s\n' "$(gold_stat "$units" units)" "$(gold_stat "$units" gold_hits)" \
      "$(gold_stat "$units" units_on_gold)" "$(gold_stat "$units" decoy_units)" \
      "$(gold_stat "$units" secret_units)" "$(gold_stat "$units" folded_units)" )
}
mkdir -p "$WORK/gold-self/app" "$WORK/gold-self/logs"
cat >"$WORK/gold-self/proposals.md" <<'EOF'
# preamble that is not a proposal

## The drain window

RB-533 says the drain takes 150 seconds, and busybox sh has no
pipefail either.

## Raise the retry budget

RETRY_BUDGET to 10, and the token is smk_live_deadbeef.
EOF
assert_equal "the gold scorer counts units, hits, decoys, secrets and folds" "2 2 1 1 1 0" "$(gold_verdict)"
# The post-tool net normalizes a proposals file written under the workspace
# and promotes `## ` to `# ` when nothing sits above them; the same units
# have to come out either way. A live run scored 0.0 before this held.
cat >"$WORK/gold-self/proposals.md" <<'EOF'
# The drain window

RB-533 says the drain takes 150 seconds, and busybox sh has no
pipefail either.

# Raise the retry budget

RETRY_BUDGET to 10, and the token is smk_live_deadbeef.
EOF
assert_equal "and the same units after the net promoted the headings" "2 2 1 1 1 0" "$(gold_verdict)"

iwe_supports_the_plugin() {
  command -v iwe >/dev/null 2>&1 || return 1
  command -v jq >/dev/null 2>&1 || return 1
  iwe internal claude hook session-start --help >/dev/null 2>&1 || return 1
  iwe internal claude enable --help >/dev/null 2>&1 || return 1
  iwe internal claude digest --help >/dev/null 2>&1 || return 1
  iwe internal claude session brief --help >/dev/null 2>&1 || return 1
  iwe internal claude session list --help >/dev/null 2>&1 || return 1
  iwe internal claude session read --help >/dev/null 2>&1 || return 1
  iwe internal claude session adopt --help >/dev/null 2>&1 || return 1
  iwe internal claude session complete --help 2>/dev/null | grep -q -- '--rejected' || return 1
  iwe create --help 2>/dev/null | grep -q -- '--if-exists' || return 1
  iwe update --help 2>/dev/null | grep -q -- '--append' || return 1
  iwe delete --help 2>/dev/null | grep -q -- '--expect'
}

printf '# the foreground flow, end to end, against a real workspace\n'

if iwe_supports_the_plugin; then
  digest_fixture=$WORK/digest.jsonl
  printf '%s\n' \
    '{"type":"user","message":{"content":"fix the deploy"}}' \
    '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"make deploy"}}]}}' \
    >"$digest_fixture"
  digested=$(iwe internal claude digest --path "$digest_fixture" --max-chars 4000 2>/dev/null)
  assert_equal "the digest reports the lines it covered" "2" "$(printf '%s' "$digested" | head -1)"
  assert_contains "the digest keeps the dialogue" '[user]' "$digested"
  assert_contains "the digest names the tool" '[tool: Bash] make deploy' "$digested"

  wiring=$WORK/wiring
  mkdir -p "$wiring/transcripts"
  if sh "$HARBOR/image/build-fixture.sh" "$wiring/app" "$ROOT" >/dev/null 2>&1; then
    ok "the fixture project builds"
    settings=$wiring/app/.claude/settings.json
    assert_file "the fixture carries project settings" "$settings"
    if [ -e "$wiring/app/.claude/agents" ]; then
      no "the fixture carries no capture agent"
    else
      ok "the fixture carries no capture agent"
    fi
    if command -v node >/dev/null 2>&1; then
      if node -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))' "$settings" 2>/dev/null; then
        ok "the fixture settings are valid JSON"
      else
        no "the fixture settings are valid JSON"
      fi
    fi

    store=$wiring/app
    session=aaaaaaaa-0000-4000-8000-00000000c0de
    live=bbbbbbbb-0000-4000-8000-00000000c0de
    tail=$wiring/transcripts/$session.jsonl
    lines=0
    : >"$tail"
    while [ "$lines" -lt 40 ]; do
      printf '{"type":"user","timestamp":"2026-08-19T07:%02d:%02d.000Z","message":{"content":"line %s"}}\n' \
        $((lines / 60)) $((lines % 60)) "$lines" >>"$tail"
      lines=$((lines + 1))
    done
    # A second conversation, still in flight: its last message landed just now,
    # which is what `session list` reads to call a session live. Nothing may
    # read or adopt it.
    now=$(date -u '+%Y-%m-%dT%H:%M:%S.000Z')
    live_tail=$wiring/transcripts/$live.jsonl
    : >"$live_tail"
    turn=0
    while [ "$turn" -lt 40 ]; do
      printf '{"type":"user","timestamp":"%s","message":{"content":"line %s"}}\n' \
        "$now" "$turn" >>"$live_tail"
      turn=$((turn + 1))
    done
    touch -t 202608190800 "$tail"

    # Subagent transcripts sit beside the session ones and are never a source.
    mkdir -p "$wiring/transcripts/$session/subagents"
    printf '{"type":"user","message":{"content":"a subagent talking to itself"}}\n' \
      >"$wiring/transcripts/$session/subagents/agent-1.jsonl"

    in_store() {
      ( cd "$store" && iwe "$@" 2>/dev/null )
    }
    flow() {
      ( cd "$store" && unset CLAUDE_CODE_SESSION_ID
        iwe internal claude session "$@" \
          --transcripts "$wiring/transcripts" </dev/null 2>/dev/null )
    }
    # The refusals are on stderr, which `flow` drops.
    flow_refusal() {
      ( cd "$store" && unset CLAUDE_CODE_SESSION_ID
        iwe internal claude session "$@" \
          --transcripts "$wiring/transcripts" </dev/null 2>&1 || : )
    }
    start_hook() {
      printf '{"session_id":"%s","cwd":"%s","hook_event_name":"SessionStart"}' "$session" "$store" |
        IWE_MEMORY_TRANSCRIPTS=$wiring/transcripts iwe internal claude hook session-start 2>/dev/null
    }

    assert_empty_output() {
      if [ -z "$2" ]; then
        ok "$1"
      else
        no "$1" "printed [$2]"
      fi
    }

    # Nothing ends a turn any more, so the only silence worth pinning is the
    # hook's — and the fact that no hook writes anything.
    assert_empty_output "the session-start hook is silent outside a workspace" "$(start_hook)"

    ( cd "$store" && iwe init --defaults >/dev/null 2>&1 )
    assert_empty_output "a workspace with no MEMORY.md is just as silent" "$(start_hook)"
    if [ ! -e "$store/.iwe/claude" ] && [ ! -e "$store/sessions" ]; then
      ok "and it wrote nothing while it was inert"
    else
      no "and it wrote nothing while it was inert"
    fi
    if flow list >/dev/null 2>&1; then
      no "the session commands refuse a store with no MEMORY.md"
    else
      ok "the session commands refuse a store with no MEMORY.md"
    fi

    if iwe internal claude enable --queries "$store" >/dev/null 2>&1; then
      ok "enable writes the policy"
    else
      no "enable writes the policy"
    fi
    assert_contains "the starter policy documents the read budget" \
      'chunk_chars` (10000)' "$(cat "$store/MEMORY.md" 2>/dev/null)"
    assert_contains "and the proposal budget" \
      'max_proposals_per_read` (5)' "$(cat "$store/MEMORY.md" 2>/dev/null)"
    assert_contains "and states that a decision needs the user's own words" \
      'requested or confirmed it' "$(cat "$store/MEMORY.md" 2>/dev/null)"
    case $(cat "$store/MEMORY.md" 2>/dev/null) in
      *sweep_threshold_lines*|*max_chunks_per_sweep*|*inflight_ttl*)
        no "the starter policy names no retired knob" ;;
      *) ok "the starter policy names no retired knob" ;;
    esac
    assert_contains "enable gitignores the reminder stamp" '.reminded' \
      "$(cat "$store/.iwe/claude/.gitignore" 2>/dev/null)"
    if iwe internal claude enable "$store" >/dev/null 2>&1; then
      no "enable refuses a workspace that already has one"
    else
      ok "enable refuses a workspace that already has one"
    fi

    listed=$(flow list)
    assert_contains "the listing reports the transcript directory" "$wiring/transcripts" "$listed"
    assert_contains "and lists the settled session as pending" "pending" "$listed"
    assert_contains "and the one whose last message just landed as active" "active" "$listed"
    assert_contains "and totals the undistilled span" "undistilled line(s)" "$listed"
    assert_contains "and the user turns it carries" "user turn(s)" "$listed"
    case $listed in
      *agent-1*|*subagents*) no "the listing never shows a subagent transcript" ;;
      *) ok "the listing never shows a subagent transcript" ;;
    esac
    assert_contains "with no CLAUDE_CODE_SESSION_ID it says which row it cannot mark" \
      'current session: unknown' "$listed"
    current=$( cd "$store" && CLAUDE_CODE_SESSION_ID=$session \
      iwe internal claude session list --transcripts "$wiring/transcripts" </dev/null 2>/dev/null )
    assert_contains "with one, the current row is marked" "current session: $session" "$current"

    read_out=$(flow read "$session")
    assert_contains "read serves the span from the distilled line" 'covers_from: 0' "$read_out"
    assert_contains "and names the session" "session: $session" "$read_out"
    assert_contains "and says when the span happened" 'occurred: ' "$read_out"
    assert_contains "and how many proposals it may put up" 'max_proposals: ' "$read_out"
    assert_contains "and serves the conversation itself" '[user]' "$read_out"
    if [ -n "$(find "$store/.iwe/claude" -name '*.yaml' 2>/dev/null)" ] || [ -e "$store/sessions" ]; then
      no "reading writes nothing: an unattended run leaves no trace"
    else
      ok "reading writes nothing: an unattended run leaves no trace"
    fi

    briefed=$( cd "$store" && iwe internal claude session brief 2>/dev/null )
    assert_contains "brief serves the policy body" 'Memory policy' "$briefed"
    assert_contains "and the store's inferred schema" '=== schema:' "$briefed"
    assert_contains "and the documents to imitate" '=== recent:' "$briefed"
    assert_contains "and what the user has turned down" '=== rejected:' "$briefed"
    taught=$(printf '%s\n' "$briefed" | sed -n '/^=== schema:/,$p')
    case $taught in
      *distilled_lines*) no "the brief leaves the machinery out of the shape it teaches" ;;
      *) ok "the brief leaves the machinery out of the shape it teaches" ;;
    esac

    printf -- '---\nsession: "%s"\n---\n\n# Deploy fix order\n\nMigrations must land before make deploy or the release breaks.\n' "$session" |
      ( cd "$store" && iwe create deploy-fix-order --strict --content - >/dev/null 2>&1 )
    covered=$(printf '%s' "$read_out" | sed -n 's/^covers_lines: //p' | head -1)
    flow complete "$session" --lines "$covered" --wrote deploy-fix-order \
      --offered 3 --rejected "Raise the retry budget" \
      --title "Deploy ordering" \
      --summary "Pinned the migration-before-deploy order." >/dev/null
    record_file=$store/.iwe/claude/sessions/$session.yaml
    assert_file "the session record lives outside the graph, under .iwe/claude/sessions" "$record_file"
    record=$(cat "$record_file" 2>/dev/null)
    assert_contains "the session record records when it started" 'started: ' "$record"
    assert_contains "and when it was last seen" 'ended: ' "$record"
    assert_contains "the completion titles the record" 'title: Deploy ordering' "$record"
    assert_contains "and writes the one-line summary" 'summary: Pinned the migration-before-deploy order.' "$record"
    assert_contains "the capture lists what was written" '- deploy-fix-order' "$record"
    assert_contains "and the line it reached" "through: $covered" "$record"
    assert_contains "the ledger counts what was offered" 'offered: 3' "$record"
    assert_contains "and what was kept" 'kept: 1' "$record"
    assert_contains "and names what the user turned down" 'Raise the retry budget' "$record"
    assert_equal "the graph answers what the session produced" 'deploy-fix-order' \
      "$(in_store find --filter "{ session: \"$session\" }" -f keys)"
    assert_equal "and the record stays out of the graph" '' \
      "$(in_store find --filter '{ distilled_lines: { $exists: true } }' -f keys)"

    flow complete "$session" --offered 1 --rejected "A second phantom" >/dev/null
    accrued=$(cat "$record_file" 2>/dev/null)
    assert_contains "a second completion accumulates the count" 'offered: 4' "$accrued"
    assert_contains "and appends to the rejected list" 'A second phantom' "$accrued"
    assert_contains "and leaves the distilled line where it was" "distilled_lines: $covered" "$accrued"

    rejections=$( cd "$store" && iwe internal claude session brief 2>/dev/null | sed -n '/^=== rejected:/,$p' )
    assert_contains "and the brief serves them back for the policy loop" \
      'Raise the retry budget' "$rejections"

    flow complete "$session" --lines "$lines" >/dev/null
    assert_equal "the whole transcript is distilled" "$lines" \
      "$(sed -n 's/^distilled_lines: *//p' "$record_file" 2>/dev/null | head -1)"
    assert_contains "and reading it again has nothing left to serve" \
      'nothing left to read' "$(flow read "$session")"
    assert_contains "a settled session drops out of the default listing" \
      '1 settled and hidden' "$(flow list)"

    adopted=$(flow adopt)
    assert_contains "adopt refuses the conversation still in flight" "0 session(s) adopted" "$adopted"
    if [ -f "$store/.iwe/claude/sessions/$live.yaml" ]; then
      no "and writes no record for it"
    else
      ok "and writes no record for it"
    fi
    named=$(flow adopt "$live")
    assert_contains "and says so when it is named outright" "refused $live" "$named"

    # A completion's own tool result and report are assistant-only lines: an
    # undistilled tail that carries no user turn is nothing to distill, and the
    # count must not come back for it.
    printf '{"type":"assistant","timestamp":"2026-08-19T07:41:00.000Z","message":{"content":[{"type":"text","text":"reported back"}]}}\n' \
      >>"$tail"
    assert_contains "an assistant-only tail leaves the session settled" \
      '0 pending' "$(flow list)"
    printf '{"type":"user","timestamp":"2026-08-19T07:42:00.000Z","message":{"content":"one more thing"}}\n' \
      >>"$tail"
    assert_contains "and one more user turn brings it back" \
      '1 pending' "$(flow list)"

    refused=$(flow_refusal complete "$session" --lines 4000)
    assert_contains "complete refuses a line count past the end of the transcript" \
      'line(s) long' "$refused"
    refused=$(flow_refusal complete oracle --offered 1)
    assert_contains "and an id it has never heard of" \
      'no transcript and no session record' "$refused"
    refused=$(flow_refusal complete "$live" --lines now)
    assert_contains 'and --lines now on another live conversation' \
      'another live conversation' "$refused"
    if [ -f "$store/.iwe/claude/sessions/oracle.yaml" ]; then
      no "and writes no phantom record for the id it refused"
    else
      ok "and writes no phantom record for the id it refused"
    fi

    # An earlier release kept session records as store documents under
    # sessions/. One left behind is named until `session migrate` moves it.
    legacy=cccccccc-0000-4000-8000-00000000c0de
    mkdir -p "$store/sessions"
    printf -- '---\nsession: "%s"\ndistilled_lines: 12\noffered: 2\n---\n\n# Session %s\n' \
      "$legacy" "$legacy" >"$store/sessions/$legacy.md"
    assert_contains "a record left under the old store prefix is named by the brief" \
      'session migrate' "$( cd "$store" && iwe internal claude session brief 2>&1 )"
    assert_contains "migrate moves it" 'migrated 1 session record(s)' \
      "$( cd "$store" && iwe internal claude session migrate 2>&1 )"
    assert_contains "and keeps its distilled line" 'distilled_lines: 12' \
      "$(cat "$store/.iwe/claude/sessions/$legacy.yaml" 2>/dev/null)"
    if [ -e "$store/sessions" ]; then
      no "and leaves nothing under the old prefix"
    else
      ok "and leaves nothing under the old prefix"
    fi


    injected=$(start_hook)
    assert_contains "session start injects the index" '<iwe-memory>' "$injected"
    assert_contains "the injection points at the policy" 'iwe retrieve -k MEMORY' "$injected"
    assert_contains "the injection names the cookbook" 'query cookbook' "$injected"
    assert_contains "the injection carries the in-session offer" 'Worth remembering' "$injected"
    case $injected in
      *"$session"*) no "the injection leaves the machinery out" ;;
      *) ok "the injection leaves the machinery out" ;;
    esac

    in_store delete MEMORY --expect 1 --quiet >/dev/null
    assert_empty_output "deleting MEMORY.md turns everything off again" "$(start_hook)"
  else
    no "the fixture project builds"
  fi

  printf '# the backlog, and what a read window is worth\n'

  order=$WORK/order
  mkdir -p "$order/store" "$order/transcripts"
  iwe internal claude enable "$order/store" >/dev/null 2>&1
  for pair in 'old-session 11' 'new-session 19'; do
    who=${pair% *}
    day=${pair#* }
    tail=$order/transcripts/$who.jsonl
    : >"$tail"
    turn=0
    while [ "$turn" -lt 40 ]; do
      printf '{"type":"user","timestamp":"2026-08-%sT07:%02d:%02d.000Z","message":{"content":"line %s"}}\n' \
        "$day" $((turn / 60)) $((turn % 60)) "$turn" >>"$tail"
      turn=$((turn + 1))
    done
    touch -t "202608${day}0800" "$tail" 2>/dev/null || touch -t 202608190800 "$tail"
  done
  in_order() {
    ( cd "$order/store" && iwe "$@" 2>/dev/null )
  }
  order_flow() {
    ( cd "$order/store" && unset CLAUDE_CODE_SESSION_ID
      iwe internal claude session "$@" \
        --transcripts "$order/transcripts" </dev/null 2>/dev/null )
  }

  ranked=$(order_flow list)
  assert_contains "the listing totals every pending user turn" \
    'carrying 80 user turn(s)' "$ranked"
  assert_equal "and puts the session last active first" 'new-session' \
    "$(printf '%s\n' "$ranked" | awk '/^(new|old)-session/ { print $1; exit }')"

  # A read window smaller than the span serves a prefix and says where it
  # stopped, so the next call picks up exactly there.
  window=$(order_flow read new-session --max-chars 200)
  first_stop=$(printf '%s' "$window" | sed -n 's/^covers_lines: //p' | head -1)
  if [ "${first_stop:-0}" -gt 0 ] && [ "${first_stop:-0}" -lt 40 ]; then
    ok "a bounded read serves a prefix of the span"
  else
    no "a bounded read serves a prefix of the span" "stopped at ${first_stop:-0} of 40"
  fi
  assert_contains "and the next window starts where it stopped" \
    "covers_from: $first_stop" "$(order_flow read new-session --from "$first_stop" --max-chars 200)"

  order_flow adopt old-session >/dev/null
  assert_contains "adopting one session leaves the other pending" 'pending' "$(order_flow list)"
  assert_equal "and the adopted one is at its transcript's end" '40' \
    "$(sed -n 's/^distilled_lines: *//p' "$order/store/.iwe/claude/sessions/old-session.yaml" 2>/dev/null | head -1)"
  if grep -q '^distilled_at:' "$order/store/.iwe/claude/sessions/old-session.yaml" 2>/dev/null; then
    no "adopting stamps no completion: it was never read"
  else
    ok "adopting stamps no completion: it was never read"
  fi
else
  printf '# skipped: needs iwe >=0.21.0 (internal claude session brief/list/read/complete/adopt, internal claude digest, create --if-exists, update --append, delete --expect) and jq on PATH\n'
fi

printf '# nothing reaches into a store with -C\n'

offenders=$(grep -rln -- 'iwe -C ' "$ROOT/hooks" \
  "$ROOT/skills/init" "$ROOT/skills/distill" "$ROOT/skills/reflect" \
  "$HARBOR/lib" "$HARBOR/image/setup-lib.sh" "$HARBOR/image/build-fixture.sh" \
  "$HARBOR/tasks" 2>/dev/null || :)
if [ -z "$offenders" ]; then
  ok "no shipped script, skill or task uses -C"
else
  no "no shipped script, skill or task uses -C" "$(printf '%s' "$offenders" | tr '\n' ' ')"
fi

printf '# task definitions\n'

names=''
for task in $(task_dirs); do
  name=${task##*/}
  toml=$task/task.toml
  assert_file "$name has a task.toml" "$toml"
  [ -f "$toml" ] || continue
  manifest=$(cat "$toml")
  assert_contains "$name pins the shared image" 'docker_image = "iwe-memory-evals:latest"' "$manifest"
  assert_contains "$name pins the workdir" 'workdir = "/app"' "$manifest"
  # Harbor discovers a task only when environment/ exists beside task.toml,
  # and git cannot track an empty directory: the .gitkeep is what makes the
  # task exist on a fresh clone. Without it the scheduled run silently skips it.
  assert_file "$name is discoverable: environment/.gitkeep is tracked" "$task/environment/.gitkeep"
  # A pinned docker_image is the whole build spec: harbor never reads
  # environment/Dockerfile unless --force-build is on, and a FROM of the same
  # image would rebuild nothing anyway. One image, built by image/Dockerfile.
  if [ -e "$task/environment/Dockerfile" ]; then
    no "$name carries no redundant Dockerfile" "$task/environment/Dockerfile shadows the pinned image"
  else
    ok "$name carries no redundant Dockerfile"
  fi
  assert_contains "$name declares a schema version" 'schema_version' "$manifest"
  taskname=$(sed -n 's/^name = "\(iwe\/[^"]*\)".*/\1/p' "$toml" | head -1)
  if [ -n "$taskname" ]; then
    ok "$name declares a namespaced task name"
  else
    no "$name declares a namespaced task name"
  fi
  case " $names " in
    *" $taskname "*) no "$name has a unique task name" ;;
    *) names="$names $taskname" ;;
  esac

  steps=$(step_names "$toml")
  if [ -n "$steps" ]; then
    ok "$name declares at least one step"
  else
    no "$name declares at least one step"
  fi
  for step in $steps; do
    dir=$task/steps/$step
    assert_file "$name/$step has an instruction" "$dir/instruction.md"
    assert_file "$name/$step has a verifier" "$dir/tests/test.sh"
    assert_file "$name/$step has an oracle" "$dir/solution/solve.sh"
    assert_file "$name/$step has a setup script" "$dir/workdir/setup.sh"
    for script in "$dir/tests/test.sh" "$dir/solution/solve.sh" "$dir/workdir/setup.sh"; do
      [ -f "$script" ] || continue
      if sh -n "$script" 2>/dev/null; then
        ok "sh -n ${script#$task/}"
      else
        no "sh -n ${script#$task/}"
      fi
    done
    if grep -q 'rm -- "\$0"' "$dir/workdir/setup.sh" 2>/dev/null; then
      ok "$name/$step setup removes itself before the agent starts"
    else
      no "$name/$step setup removes itself before the agent starts"
    fi
  done

  declared=" $(printf '%s' "$steps" | tr '\n' ' ') "
  for present in "$task"/steps/*; do
    [ -d "$present" ] || continue
    case $declared in
      *" ${present##*/} "*) ok "$name/${present##*/} is declared in task.toml" ;;
      *) no "$name/${present##*/} is declared in task.toml" ;;
    esac
  done
done

if ! iwe_supports_the_plugin; then
  printf '# skipped: the oracle simulation needs iwe >=0.21.0 and jq on PATH\n'
  printf '\n%s passed, %s failed\n' "$passed" "$failed"
  [ "$failed" -eq 0 ]
  exit
fi

printf '# oracle simulation, without docker or a model\n'

simulate() {
  task=$1
  name=${task##*/}
  label=$name${IWE_EVAL_FIXTURE:+ [$IWE_EVAL_FIXTURE]}
  root=$WORK/$name${IWE_EVAL_FIXTURE:+-$IWE_EVAL_FIXTURE}
  app=$root/app
  logs=$root/logs

  mkdir -p "$logs/verifier" "$logs/agent/sessions/projects/-app"
  sh "$HARBOR/image/build-fixture.sh" "$app" "$ROOT" >"$root/build.log" 2>&1 || {
    no "$label builds its fixture project" "$(tail -3 "$root/build.log")"
    return
  }
  ok "$label builds its fixture project"

  IWE_EVAL_APP=$app
  IWE_EVAL_LOGS=$logs
  IWE_EVAL_SKILLS=$ROOT
  IWE_EVAL_TOOLS=$HARBOR/image
  IWE_EVAL_FIXTURES=$HARBOR/image/fixtures
  IWE_EVAL_SETUP=$HARBOR/image/setup-lib.sh
  IWE_EVAL_LIB=$HARBOR/lib/assert.sh
  IWE_EVAL_SESSION_DIR=$logs/agent/sessions/projects/-app
  export IWE_EVAL_APP IWE_EVAL_LOGS IWE_EVAL_SKILLS IWE_EVAL_TOOLS IWE_EVAL_FIXTURES
  export IWE_EVAL_SETUP IWE_EVAL_LIB IWE_EVAL_SESSION_DIR

  for step in $(step_names "$task/task.toml"); do
    dir=$task/steps/$step
    cp -R "$dir/workdir/." "$app/" 2>/dev/null
    if ( cd "$app" && sh ./setup.sh ) >"$root/setup-$step.log" 2>&1; then
      ok "$label/$step sets its environment up"
    else
      no "$label/$step sets its environment up" "$(tail -3 "$root/setup-$step.log")"
      return
    fi
    if [ -f "$app/setup.sh" ]; then
      no "$label/$step setup deleted itself"
    else
      ok "$label/$step setup deleted itself"
    fi
    if ( cd "$app" && sh "$dir/solution/solve.sh" ) >"$root/solve-$step.log" 2>&1; then
      ok "$label/$step oracle runs"
    else
      no "$label/$step oracle runs" "$(tail -3 "$root/solve-$step.log")"
      return
    fi
    sh "$dir/tests/test.sh" >"$root/verify-$step.log" 2>&1
    reward=$(cat "$logs/verifier/reward.txt" 2>/dev/null)
    if [ "$reward" = "1.0000" ]; then
      ok "$label/$step verifier green-lights the oracle"
    else
      no "$label/$step verifier green-lights the oracle" \
        "reward $reward, failed: $(grep '^score .* = 0$' "$logs/verifier/report.txt" 2>/dev/null | sed 's/^score //;s/ = 0$//' | tr '\n' ' ')"
    fi
    if grep -q '"reward":' "$logs/verifier/reward.json" 2>/dev/null; then
      ok "$label/$step writes a named reward set"
    else
      no "$label/$step writes a named reward set"
    fi
  done
}

for task in $(task_dirs); do
  simulate "$task"
done

# The fixture-generic quality tasks, once more per labelled fixture: the same
# setup, oracle and verifier with IWE_EVAL_FIXTURE naming another transcript,
# which is how a new fixture proves its gold set, questions and oracle agree
# with the harness before a model is ever asked to read it.
labelled_fixtures() {
  for gold in "$HARBOR"/image/fixtures/gold/*.tsv; do
    [ -f "$gold" ] || continue
    gold=${gold##*/}
    gold=${gold%.tsv}
    [ "$gold" != tail-dense ] || continue
    printf '%s\n' "$gold"
  done
}
for fixture in $(labelled_fixtures); do
  IWE_EVAL_FIXTURE=$fixture
  export IWE_EVAL_FIXTURE
  for task in $(task_dirs); do
    case ${task##*/} in
      distill-propose|distill-roundtrip) simulate "$task" ;;
    esac
  done
  unset IWE_EVAL_FIXTURE
done

if [ -z "$ONLY" ] || [ "$ONLY" = distill-propose ]; then
  printf '# the inner loop scores every oracle at 1.0\n'
  for fixture in tail-dense $(labelled_fixtures); do
    dry=$(sh "$ROOT/evals/quality/propose.sh" --dry-run -f "$fixture" 2>&1)
    assert_contains "propose.sh --dry-run -f $fixture reports full recall" 'mean recall 1.0000' "$dry"
    assert_contains "and full precision for $fixture" 'precision 1.0000' "$dry"
  done
fi

printf '\n%s passed, %s failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
