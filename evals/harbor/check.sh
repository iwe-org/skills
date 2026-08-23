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

for script in "$HARBOR/check.sh" "$HARBOR/lib/assert.sh" "$HARBOR/image/setup-lib.sh" \
  "$HARBOR/image/build-fixture.sh" "$HARBOR/image/render-settings.sh" "$HARBOR/image/marker.sh"; do
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
assert_contains "the hooks run the binary's session-start" 'iwe internal claude hook session-start' \
  "$(cat "$ROOT/hooks/hooks.json")"
assert_contains "the hooks run the binary's sweep" 'iwe internal claude hook stop' \
  "$(cat "$ROOT/hooks/hooks.json")"
case $(cat "$ROOT/hooks/hooks.json") in
  *--footer*|*--capture-reason*|*--maintenance-reason*)
    no "the hooks are bare one-liners; the binary carries the default strings" ;;
  *) ok "the hooks are bare one-liners; the binary carries the default strings" ;;
esac
case $(cat "$ROOT/hooks/hooks.json") in
  *SessionEnd*) no "the manifest declares no SessionEnd hook" ;;
  *) ok "the manifest declares no SessionEnd hook" ;;
esac
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
printf '%s\n' '{"type":"user","message":{"content":"IWE memory sweep: call the Agent tool now with subagent_type \"distill\", run_in_background true, and the single-line prompt \"Work the capture jobs waiting in this workspace.\"."}}' >>"$stream"
assert_equal "the stop hook block reason is not a launch" quiet \
  "$(helper_verdict "$helpers/app" "$helpers/logs")"
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Agent","input":{"subagent_type":"distill","run_in_background":true,"prompt":"Work the capture jobs waiting in this workspace."}}]}}' >>"$stream"
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
assert_contains "the rendered hooks point at the binary" 'iwe internal claude hook stop' \
  "$(cat "$rendered")"

printf '# the image has everything it bakes in\n'

for input in hooks/hooks.json agents/distill.md \
  skills/init/SKILL.md skills/distill/SKILL.md skills/reflect/SKILL.md; do
  assert_file "the image can copy $input" "$ROOT/$input"
done

printf '# fixtures cross the sweep threshold\n'

# The shipped default, as the binary's sweep hardcodes it and its embedded
# starter policy documents it; the end-to-end block below asserts the policy
# `internal claude enable` actually writes names the same number.
threshold=30
for fixture in "$HARBOR"/image/fixtures/*.jsonl; do
  lines=$(grep -c . "$fixture")
  if [ "$lines" -ge "$threshold" ]; then
    ok "${fixture##*/} carries $lines lines, at or over the $threshold-line threshold"
  else
    no "${fixture##*/} carries $lines lines, under the $threshold-line threshold"
  fi
  if node -e 'const fs=require("fs");for(const l of fs.readFileSync(process.argv[1],"utf8").split("\n"))if(l.trim())JSON.parse(l)' "$fixture" 2>/dev/null; then
    ok "${fixture##*/} is valid JSONL"
  elif command -v node >/dev/null 2>&1; then
    no "${fixture##*/} is valid JSONL"
  else
    printf 'skip %s is valid JSONL: node is not on PATH\n' "${fixture##*/}"
  fi
done

iwe_supports_the_plugin() {
  command -v iwe >/dev/null 2>&1 || return 1
  command -v jq >/dev/null 2>&1 || return 1
  iwe internal claude hook stop --help >/dev/null 2>&1 || return 1
  iwe internal claude enable --help >/dev/null 2>&1 || return 1
  iwe internal claude digest --help >/dev/null 2>&1 || return 1
  iwe internal claude job next --help >/dev/null 2>&1 || return 1
  iwe internal claude job brief --help >/dev/null 2>&1 || return 1
  iwe internal claude job frontier --help >/dev/null 2>&1 || return 1
  iwe internal claude job complete --help 2>/dev/null | grep -q -- '--lines' || return 1
  iwe create --help 2>/dev/null | grep -q -- '--if-exists' || return 1
  iwe update --help 2>/dev/null | grep -q -- '--append' || return 1
  iwe delete --help 2>/dev/null | grep -q -- '--expect'
}

printf '# the sweep, end to end, against a real workspace\n'

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
    assert_file "the fixture carries the distill agent" "$wiring/app/.claude/agents/distill.md"
    if command -v node >/dev/null 2>&1; then
      if node -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))' "$settings" 2>/dev/null; then
        ok "the fixture settings are valid JSON"
      else
        no "the fixture settings are valid JSON"
      fi
    fi

    store=$wiring/app
    session=aaaaaaaa-0000-4000-8000-00000000c0de
    tail=$wiring/transcripts/$session.jsonl
    lines=0
    : >"$tail"
    while [ "$lines" -lt $((threshold + 20)) ]; do
      printf '{"type":"assistant","timestamp":"2026-08-19T07:%02d:%02d.000Z","message":{"content":[{"type":"text","text":"line %s"}]}}\n' \
        $((lines / 60)) $((lines % 60)) "$lines" >>"$tail"
      lines=$((lines + 1))
    done
    payload=$(printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","hook_event_name":"Stop","stop_hook_active":false}' \
      "$session" "$tail" "$store")

    sweep() {
      printf '%s' "$payload" | iwe internal claude hook stop 2>/dev/null
    }
    in_store() {
      ( cd "$store" && iwe "$@" 2>/dev/null )
    }

    assert_empty_output() {
      if [ -z "$2" ]; then
        ok "$1"
      else
        no "$1" "printed [$2]"
      fi
    }
    assert_empty_output "the sweep stays silent outside a workspace" "$(sweep)"

    ( cd "$store" && iwe init --defaults >/dev/null 2>&1 )
    assert_empty_output "a workspace with no MEMORY.md is just as silent" "$(sweep)"
    if [ ! -d "$store/sessions" ]; then
      ok "and it wrote nothing while it was inert"
    else
      no "and it wrote nothing while it was inert"
    fi

    if iwe internal claude enable --queries "$store" >/dev/null 2>&1; then
      ok "enable writes the policy"
    else
      no "enable writes the policy"
    fi
    assert_contains "the starter policy documents the sweep default" \
      "sweep_threshold_lines\` ($threshold)" "$(cat "$store/MEMORY.md" 2>/dev/null)"
    if iwe internal claude enable "$store" >/dev/null 2>&1; then
      no "enable refuses a workspace that already has one"
    else
      ok "enable refuses a workspace that already has one"
    fi

    blocked=$(sweep)
    assert_contains "the sweep blocks once the policy exists" '"decision": "block"' "$blocked"
    assert_contains "the block asks for capture" 'IWE memory sweep' "$blocked"
    agent_name=$(sed -n 's/^name:[[:space:]]*//p' "$ROOT/agents/distill.md" | head -1)
    assert_contains "and, installed as a project agent, the reason names it bare" \
      "subagent_type \\\"$agent_name\\\"" "$blocked"
    case $blocked in
      *"$store"*) no "the block carries no path" ;;
      *) ok "the block carries no path" ;;
    esac

    plugin_name=$(jq -r .name "$ROOT/.claude-plugin/plugin.json")
    plugin_store=$wiring/plugin-app
    rm -rf "$plugin_store"
    cp -R "$store" "$plugin_store"
    plugin_payload=$(printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","hook_event_name":"Stop","stop_hook_active":false}' \
      "$session" "$tail" "$plugin_store")
    plugin_blocked=$(printf '%s' "$plugin_payload" \
      | IWE_MEMORY_STATE=$wiring/plugin-state CLAUDE_PLUGIN_ROOT=$ROOT iwe internal claude hook stop 2>/dev/null)
    assert_contains "run as a plugin hook, the reason names the agent under the plugin's namespace" \
      "subagent_type \\\"$plugin_name:$agent_name\\\"" "$plugin_blocked"
    rm -rf "$plugin_store" "$wiring/plugin-state"
    queue=$store/.iwe/claude-sessions
    chunks() {
      find "$queue" -mindepth 2 -name '*.md' 2>/dev/null | sort
    }
    chunk_count() {
      chunks | grep -c . || :
    }

    assert_file "the sweep imported the tail as a chunk under .iwe/claude-sessions" "$queue/$session/000000.md"
    assert_file "the sweep created the session record" "$store/sessions/$session.md"
    if [ -d "$store/sessions/$session" ]; then
      no "and wrote no chunk directory into the store"
    else
      ok "and wrote no chunk directory into the store"
    fi
    covers=$(sed -n 's/^covers_lines: //p' "$(chunks | tail -1)" 2>/dev/null | head -1)
    assert_equal "the chunks cover the whole tail" "$lines" "${covers:-0}"
    if grep -q '^type:' "$store/sessions/$session.md" "$queue/$session"/*.md 2>/dev/null; then
      no "the machinery stamps no type of its own"
    else
      ok "the machinery stamps no type of its own"
    fi

    imported=$(chunk_count)
    second=$(sweep)
    assert_equal "a second sweep imports the same span, not more" "$imported" "$(chunk_count)"
    assert_empty_output "and does not ask for a second agent while the claim is live" "$second"

    served=$( cd "$store" && iwe internal claude job next 2>/dev/null )
    assert_contains "job next serves the chunk at the watermark" "covers_from: 0" "$served"
    assert_contains "and names the session it came from" "session: $session" "$served"
    assert_contains "and shows when the span happened" "occurred: " "$served"

    briefed=$( cd "$store" && iwe internal claude job brief 2>/dev/null )
    assert_contains "job brief serves the policy body" 'Memory policy' "$briefed"
    assert_contains "and the store's inferred schema" '=== schema:' "$briefed"
    assert_contains "and the documents to imitate" '=== recent:' "$briefed"
    # Only the shape it teaches: the policy body legitimately names those
    # fields, because telling capture to filter them out is its job.
    taught=$(printf '%s\n' "$briefed" | sed -n '/^=== schema:/,$p')
    case $taught in
      *distilled_lines*|*covers_lines*)
        no "the brief leaves the machinery out of the shape it teaches" ;;
      *) ok "the brief leaves the machinery out of the shape it teaches" ;;
    esac

    batched=$( cd "$store" && iwe internal claude job frontier 2>/dev/null )
    assert_contains "job frontier serves a batch" 'servable session(s)' "$batched"
    assert_equal "one entry per session, and this store has one session" "1" \
      "$(printf '%s\n' "$batched" | grep -c '^session: ')"
    assert_contains "and the entry carries the same header job next prints" \
      "session: $session" "$batched"

    printf '# Deploy fix order\n\nMigrations must land before make deploy or the release breaks.\n' |
      ( cd "$store" && iwe create deploy-fix-order --content - >/dev/null 2>&1 )
    first=$(printf '%s' "$served" | sed -n 's/^covers_lines: //p' | head -1)
    ( cd "$store" && iwe internal claude job complete "$session" --lines "$first" \
      --wrote deploy-fix-order --title "Deploy ordering" \
      --summary "Pinned the migration-before-deploy order." >/dev/null 2>&1 )
    record=$(cat "$store/sessions/$session.md")
    assert_contains "the chunk records when its span happened" "occurred:" "$(cat "$(chunks | head -1)")"
    assert_contains "the session record records when it started" "started: " "$record"
    assert_contains "and when it was last seen" "ended: " "$record"
    assert_contains "the first completion titles the record" "# Deploy ordering" "$record"
    assert_contains "and writes the one-line summary" "Pinned the migration-before-deploy order." "$record"
    assert_contains "the capture note holds an inclusion link" "[Deploy fix order](../deploy-fix-order)" "$record"
    assert_equal "the graph answers what the session produced" "deploy-fix-order" \
      "$(in_store find --filter "{ \$includedBy: sessions/$session }" -f keys)"

    turn=0
    while [ "$turn" -le "$imported" ]; do
      turn=$((turn + 1))
      pending=$( cd "$store" && iwe internal claude job next 2>/dev/null )
      [ -n "$pending" ] || break
      through=$(printf '%s' "$pending" | sed -n 's/^covers_lines: //p' | head -1)
      ( cd "$store" && iwe internal claude job complete "$session" --lines "$through" \
        >/dev/null 2>&1 ) || break
    done
    assert_equal "working the queue leaves the watermark at the tail's end" "$lines" \
      "$(in_store find --filter "{ session: \"$session\", distilled_lines: { \$exists: true } }" \
        --project 'lines=distilled_lines' -f json --limit 1 | jq -r '.[0].lines // 0' 2>/dev/null)"
    assert_empty_output "a drained queue stays silent" "$( cd "$store" && iwe internal claude job next 2>/dev/null )"
    assert_empty_output "a settled store stays silent — nothing runs in the background but capture" "$(sweep)"

    # The read-only modes take the store from the working directory, exactly as
    # the sweep does, so they run from inside it.
    surveyed=$( cd "$store" && iwe internal claude hook stop --survey \
      --transcripts "$wiring/transcripts" </dev/null 2>/dev/null )
    assert_contains "the survey reports the transcript directory" "$wiring/transcripts" "$surveyed"
    assert_contains "the survey counts the tail" "$lines" "$surveyed"
    assert_contains "the survey names the threshold" "threshold: $threshold lines" "$surveyed"
    assert_contains "the survey counts the queue" "pending chunk(s)" "$surveyed"
    assert_contains "the survey carries the yield column" "signal" "$surveyed"
    assert_contains "and totals the user turns still on offer" "user turn(s)" "$surveyed"
    before=$(chunk_count)
    ( cd "$store" && iwe internal claude hook stop --survey \
      --transcripts "$wiring/transcripts" </dev/null ) >/dev/null 2>&1
    assert_equal "the survey imports nothing" "$before" "$(chunk_count)"

    injected=$(printf '{"session_id":"%s","cwd":"%s","hook_event_name":"SessionStart"}' \
      "$session" "$store" | iwe internal claude hook session-start 2>/dev/null)
    assert_contains "session start injects the index" '<iwe-memory>' "$injected"
    assert_contains "the injection points at the policy" 'iwe retrieve -k MEMORY' "$injected"
    assert_contains "the injection names the cookbook" 'query cookbook' "$injected"
    case $injected in
      *"$session"*) no "the injection leaves the machinery out" ;;
      *) ok "the injection leaves the machinery out" ;;
    esac

    in_store delete MEMORY --expect 1 --quiet >/dev/null
    assert_empty_output "deleting MEMORY.md turns everything off again" \
      "$(sweep; printf '{"session_id":"%s","cwd":"%s"}' "$session" "$store" |
        iwe internal claude hook session-start 2>&1)"
  else
    no "the fixture project builds"
  fi

  printf '# the queue serves the most recent session first\n'

  order=$WORK/order
  mkdir -p "$order/store" "$order/transcripts"
  iwe internal claude enable "$order/store" >/dev/null 2>&1
  # Two backlogs, told apart only by when their conversations happened: the
  # sweep imports both, so `created` is the same minute for each.
  for pair in 'old-session 11' 'new-session 19'; do
    who=${pair% *}
    day=${pair#* }
    tail=$order/transcripts/$who.jsonl
    : >"$tail"
    turn=0
    while [ "$turn" -lt $((threshold + 20)) ]; do
      printf '{"type":"user","timestamp":"2026-08-%sT07:%02d:%02d.000Z","message":{"content":"line %s"}}\n' \
        "$day" $((turn / 60)) $((turn % 60)) "$turn" >>"$tail"
      turn=$((turn + 1))
    done
  done
  in_order() {
    ( cd "$order/store" && iwe "$@" 2>/dev/null )
  }

  ranked=$(in_order internal claude hook stop --survey --transcripts "$order/transcripts" </dev/null)
  assert_contains "the survey counts every pending user turn as signal" \
    "carrying $((2 * (threshold + 20))) user turn(s)" "$ranked"

  printf '{"cwd":"%s"}' "$order/store" |
    ( cd "$order/store" && iwe internal claude hook stop --transcripts "$order/transcripts" ) >/dev/null 2>&1

  head_of_queue=$(in_order internal claude job next | sed -n 's/^session: //p' | head -1)
  assert_equal "job next serves the session whose conversation is most recent" \
    "new-session" "$head_of_queue"

  frontier=$(in_order internal claude job frontier)
  assert_equal "job frontier serves one chunk per session, newest first" \
    "new-session old-session" \
    "$(printf '%s\n' "$frontier" | sed -n 's/^session: //p' | tr '\n' ' ' | sed 's/ $//')"

  in_order internal claude job complete new-session --lines $((threshold + 20)) >/dev/null 2>&1
  assert_equal "and the older backlog is served once the recent session drains" \
    "old-session" "$(in_order internal claude job next | sed -n 's/^session: //p' | head -1)"
else
  printf '# skipped: needs iwe >=0.20.0 (internal claude hook, internal claude digest, internal claude job next/brief/frontier, job complete --lines, create --if-exists, update --append, delete --expect) and jq on PATH\n'
fi

printf '# nothing reaches into a store with -C\n'

offenders=$(grep -rln -- 'iwe -C ' "$ROOT/agents" "$ROOT/hooks" \
  "$ROOT/skills/init" "$ROOT/skills/distill" "$ROOT/skills/reflect" \
  "$HARBOR/lib" "$HARBOR/image/setup-lib.sh" "$HARBOR/image/build-fixture.sh" \
  "$HARBOR/tasks" 2>/dev/null || :)
if [ -z "$offenders" ]; then
  ok "no shipped script, agent, skill or task uses -C"
else
  no "no shipped script, agent, skill or task uses -C" "$(printf '%s' "$offenders" | tr '\n' ' ')"
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
  printf '# skipped: the oracle simulation needs iwe >=0.20.0 and jq on PATH\n'
  printf '\n%s passed, %s failed\n' "$passed" "$failed"
  [ "$failed" -eq 0 ]
  exit
fi

printf '# oracle simulation, without docker or a model\n'

simulate() {
  task=$1
  name=${task##*/}
  root=$WORK/$name
  app=$root/app
  logs=$root/logs

  mkdir -p "$logs/verifier" "$logs/agent/sessions/projects/-app"
  sh "$HARBOR/image/build-fixture.sh" "$app" "$ROOT" >"$root/build.log" 2>&1 || {
    no "$name builds its fixture project" "$(tail -3 "$root/build.log")"
    return
  }
  ok "$name builds its fixture project"

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
      ok "$name/$step sets its environment up"
    else
      no "$name/$step sets its environment up" "$(tail -3 "$root/setup-$step.log")"
      return
    fi
    if [ -f "$app/setup.sh" ]; then
      no "$name/$step setup deleted itself"
    else
      ok "$name/$step setup deleted itself"
    fi
    if ( cd "$app" && sh "$dir/solution/solve.sh" ) >"$root/solve-$step.log" 2>&1; then
      ok "$name/$step oracle runs"
    else
      no "$name/$step oracle runs" "$(tail -3 "$root/solve-$step.log")"
      return
    fi
    sh "$dir/tests/test.sh" >"$root/verify-$step.log" 2>&1
    reward=$(cat "$logs/verifier/reward.txt" 2>/dev/null)
    if [ "$reward" = "1.0000" ]; then
      ok "$name/$step verifier green-lights the oracle"
    else
      no "$name/$step verifier green-lights the oracle" \
        "reward $reward, failed: $(grep '^score .* = 0$' "$logs/verifier/report.txt" 2>/dev/null | sed 's/^score //;s/ = 0$//' | tr '\n' ' ')"
    fi
    if grep -q '"reward":' "$logs/verifier/reward.json" 2>/dev/null; then
      ok "$name/$step writes a named reward set"
    else
      no "$name/$step writes a named reward set"
    fi
  done
}

for task in $(task_dirs); do
  simulate "$task"
done

printf '\n%s passed, %s failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
