#!/bin/sh
# The inner loop for distill quality: run the distill-propose instruction over
# a labelled fixture with `claude -p`, score the proposals against the gold set
# with the same helpers the Harbor verifier uses, and print one row per run.
#
#   sh evals/quality/propose.sh                 one run, tail-dense, default model
#   sh evals/quality/propose.sh -n 5 -m opus    five runs
#   sh evals/quality/propose.sh --dry-run       score the oracle instead of a model
#   IWE_BIN=../iwe/target/debug/iwe sh evals/quality/propose.sh
#
# The model runs under the user's own `claude` login: ANTHROPIC_API_KEY is
# unset so nothing bills a key, and the session-id variables of any enclosing
# Claude Code session are unset so the child is its own session.
set -u

HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH='' cd -- "$HERE/../.." && pwd)
HARBOR=$ROOT/evals/harbor
TASK=$HARBOR/tasks/distill-propose/steps/propose

fixture=tail-dense
runs=1
model=${PROPOSE_MODEL:-sonnet}
budget=${PROPOSE_BUDGET_USD:-3}
dry=0
keep=0

usage() {
  sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
  printf '\noptions: -f <fixture> -n <runs> -m <model> -b <max-budget-usd> --dry-run --keep\n'
}

while [ "$#" -gt 0 ]; do
  case $1 in
    -f) fixture=$2; shift 2 ;;
    -n) runs=$2; shift 2 ;;
    -m) model=$2; shift 2 ;;
    -b) budget=$2; shift 2 ;;
    --dry-run) dry=1; shift ;;
    --keep) keep=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'propose: unknown argument %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

if [ -n "${IWE_BIN:-}" ]; then
  PATH=$(CDPATH='' cd -- "$(dirname -- "$IWE_BIN")" && pwd):$PATH
  export PATH
fi

for tool in iwe jq; do
  command -v "$tool" >/dev/null 2>&1 || { printf 'propose: %s is not on PATH\n' "$tool" >&2; exit 2; }
done
[ "$dry" = 1 ] || command -v claude >/dev/null 2>&1 || { printf 'propose: claude is not on PATH\n' >&2; exit 2; }
[ -f "$HARBOR/image/fixtures/$fixture.jsonl" ] || { printf 'propose: no fixture %s.jsonl\n' "$fixture" >&2; exit 2; }
[ -f "$HARBOR/image/fixtures/gold/$fixture.tsv" ] || { printf 'propose: no gold set for %s\n' "$fixture" >&2; exit 2; }

summary=$(mktemp "${TMPDIR:-/tmp}/iwe-propose-summary.XXXXXX") || exit 1
trap 'rm -f "$summary"' EXIT INT TERM

printf 'fixture %s, engine %s, %s\n' "$fixture" "$(iwe --version 2>/dev/null | head -1)" \
  "$([ "$dry" = 1 ] && printf 'oracle (dry run)' || printf 'model %s' "$model")"
printf '%-4s %-7s %-9s %-9s %-5s %-6s %-6s %-9s %-8s %-5s %s\n' \
  run recall precision proposals gold decoys secret untouched cost turns seconds

score_run() {
  ( IWE_EVAL_APP=$1
    IWE_EVAL_LOGS=$2
    IWE_EVAL_FIXTURES=$HARBOR/image/fixtures
    export IWE_EVAL_APP IWE_EVAL_LOGS IWE_EVAL_FIXTURES
    . "$HARBOR/lib/assert.sh"
    units=$2/units
    gold_split_proposals "$1/.eval/proposals.md" "$units"
    gold_eval "$fixture" "$units"
    if store_is_untouched; then untouched=1; else untouched=0; fi
    printf '%s %s %s %s %s %s %s\n' \
      "$(gold_fraction "$(gold_stat "$units" gold_hits)" "$(gold_stat "$units" gold_total)")" \
      "$(gold_fraction "$(gold_stat "$units" units_on_gold)" "$(gold_stat "$units" units)")" \
      "$(gold_stat "$units" units)" "$(gold_stat "$units" gold_hits)" \
      "$(gold_stat "$units" decoy_units)" "$(gold_stat "$units" secret_units)" "$untouched" )
}

i=1
while [ "$i" -le "$runs" ]; do
  work=$(mktemp -d "${TMPDIR:-/tmp}/iwe-propose.XXXXXX") || exit 1
  app=$work/app
  logs=$work/logs
  mkdir -p "$logs/verifier" "$logs/agent/sessions/projects/-app"
  sh "$HARBOR/image/build-fixture.sh" "$app" "$ROOT" >"$work/build.log" 2>&1 || {
    printf 'propose: fixture build failed, see %s/build.log\n' "$work" >&2
    exit 1
  }

  IWE_EVAL_APP=$app
  IWE_EVAL_LOGS=$logs
  IWE_EVAL_SKILLS=$ROOT
  IWE_EVAL_TOOLS=$HARBOR/image
  IWE_EVAL_FIXTURES=$HARBOR/image/fixtures
  IWE_EVAL_SETUP=$HARBOR/image/setup-lib.sh
  IWE_EVAL_LIB=$HARBOR/lib/assert.sh
  IWE_EVAL_SESSION_DIR=$logs/agent/sessions/projects/-app
  IWE_EVAL_FIXTURE=$fixture
  export IWE_EVAL_APP IWE_EVAL_LOGS IWE_EVAL_SKILLS IWE_EVAL_TOOLS IWE_EVAL_FIXTURES
  export IWE_EVAL_SETUP IWE_EVAL_LIB IWE_EVAL_SESSION_DIR IWE_EVAL_FIXTURE

  cp -R "$TASK/workdir/." "$app/"
  ( cd "$app" && sh ./setup.sh ) >"$work/setup.log" 2>&1 || {
    printf 'propose: setup failed, see %s/setup.log\n' "$work" >&2
    exit 1
  }

  cost=0
  turns=0
  seconds=0
  if [ "$dry" = 1 ]; then
    ( cd "$app" && sh "$TASK/solution/solve.sh" ) >"$work/solve.log" 2>&1 || {
      printf 'propose: oracle failed, see %s/solve.log\n' "$work" >&2
      exit 1
    }
  else
    started=$(date +%s)
    ( cd "$app" && env -u ANTHROPIC_API_KEY -u CLAUDE_CODE_SESSION_ID -u CLAUDECODE \
        -u CLAUDE_CODE_ENTRYPOINT -u CLAUDE_CODE_CHILD_SESSION \
        IWE_MEMORY_TRANSCRIPTS="$IWE_EVAL_SESSION_DIR" \
        claude -p --output-format json --model "$model" \
          --setting-sources project --no-session-persistence \
          --max-budget-usd "$budget" \
          --allowedTools 'Skill,Bash(iwe:*),Read,Write,Edit' \
        <"$TASK/instruction.md" ) >"$work/result.json" 2>"$work/claude.err"
    seconds=$(( $(date +%s) - started ))
    if jq -e . "$work/result.json" >/dev/null 2>&1; then
      cost=$(jq -r '.total_cost_usd // 0 | . * 10000 | round / 10000' "$work/result.json")
      turns=$(jq -r '.num_turns // 0' "$work/result.json")
      jq -r '.result // empty' "$work/result.json" >"$work/result.txt"
      if [ "$(jq -r '.is_error // false' "$work/result.json")" = "true" ]; then
        printf 'propose: run %s ended in error: %s\n' "$i" "$(head -c 300 "$work/result.txt")" >&2
      fi
    else
      printf 'propose: run %s produced no JSON result, see %s/claude.err\n' "$i" "$work" >&2
    fi
  fi

  set -- $(score_run "$app" "$logs")
  printf '%-4s %-7s %-9s %-9s %-5s %-6s %-6s %-9s %-8s %-5s %s\n' \
    "$i" "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$cost" "$turns" "$seconds"
  printf '%s %s %s %s\n' "$1" "$2" "$cost" "$5" >>"$summary"
  if [ "$keep" = 1 ]; then
    printf '     kept %s\n' "$work"
  else
    rm -rf "$work"
  fi
  i=$((i + 1))
done

awk '{ r += $1; p += $2; c += $3; d += $4; n += 1 }
  END { if (n > 0) printf "mean recall %.4f  precision %.4f  decoys %.2f  cost %.4f over %d run(s)\n", r / n, p / n, d / n, c / n, n }' "$summary"
