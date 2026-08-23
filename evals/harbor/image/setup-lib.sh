EVAL_APP=${IWE_EVAL_APP:-/app}
EVAL_CHUNKS=${IWE_MEMORY_STATE:-$EVAL_APP/.iwe/claude-sessions}
EVAL_LOGS=${IWE_EVAL_LOGS:-/logs}
EVAL_SKILLS=${IWE_EVAL_SKILLS:-/opt/iwe-skills}
EVAL_TOOLS=${IWE_EVAL_TOOLS:-/opt/iwe-evals}
EVAL_FIXTURES=${IWE_EVAL_FIXTURES:-$EVAL_TOOLS/fixtures}
EVAL_NOTES=$EVAL_APP/.eval
EVAL_SESSION_DIR=${IWE_EVAL_SESSION_DIR:-$EVAL_LOGS/agent/sessions/projects/-app}

# The workspace at /app is the store: every iwe command runs there, none of them
# with -C.
eval_iwe() {
  ( cd "$EVAL_APP" && iwe "$@" )
}

eval_note() {
  mkdir -p "$EVAL_NOTES" 2>/dev/null
  printf '%s\n' "$*" >>"$EVAL_NOTES/setup.txt"
}

eval_clean_run_state() {
  rm -f "$EVAL_APP/.deploy-receipt" "$EVAL_APP/.deploy-attempts"
  rm -rf "$EVAL_APP/dist"
}

# Memory is switched on by the very command the init skill runs, so the eval
# can never drift from what a user gets. Pass --typed for the optional ontology.
eval_memory_init() {
  iwe internal claude enable "$@" "$EVAL_APP" >/dev/null 2>&1 || :
  _policy=$(eval_iwe find --filter '{ $key: MEMORY }' -f keys --limit 1 2>/dev/null)
  [ -n "$_policy" ] || eval_note "WARNING: memory was not enabled at $EVAL_APP"
  eval_note "memory enabled at $EVAL_APP ${*:-}"
}

# Off again: MEMORY.md is the switch and deleting it is the whole gesture.
eval_memory_disable() {
  eval_iwe delete MEMORY --quiet >/dev/null 2>&1 || :
  eval_note "MEMORY.md deleted, memory off"
}

eval_workspace_remove() {
  rm -rf "$EVAL_APP/.iwe" "$EVAL_APP/iwe.toml"
  eval_note "workspace marker removed"
}

eval_memory_set() {
  eval_iwe update -k MEMORY --set "$1=$2" --expect 1 --quiet >/dev/null 2>&1 || :
  eval_note "policy knob $1 = $2"
}

# Run one of the binary's hook commands exactly as the harness would, payload
# on stdin and the transcript directory pinned so nothing has to be derived.
eval_hook() {
  _hook=$1
  _session=${2:-00000000-0000-4000-8000-000000000000}
  _reason=${3:-clear}
  mkdir -p "$EVAL_NOTES" 2>/dev/null
  set -- internal claude hook "$_hook"
  [ "$_hook" != "stop" ] ||
    set -- "$@" --transcripts "$EVAL_SESSION_DIR" --max-chunks "${EVAL_MAX_CHUNKS:-30}"
  printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","hook_event_name":"%s","reason":"%s","stop_hook_active":false}' \
    "$_session" "$EVAL_SESSION_DIR/$_session.jsonl" "$EVAL_APP" "$_hook" "$_reason" |
    ( cd "$EVAL_APP" && iwe "$@" ) >>"$EVAL_NOTES/hook-$_hook.out" 2>&1 || :
  eval_note "ran the $_hook hook for $_session"
}

# The sweep. Imports every pending span it can see and leaves the block decision
# it would have emitted in .eval/hook-stop.out.
eval_sweep() {
  eval_hook stop "${1:-00000000-0000-4000-8000-000000000000}"
}

# Fire a hook the way Claude Code fires it: the command out of the project's
# settings.json, verbatim, with the payload on stdin. Used where the point is
# the wiring itself rather than what the sweep does.
eval_hook_from_settings() {
  _event=$1
  _session=${2:-00000000-0000-4000-8000-000000000000}
  _settings=$EVAL_APP/.claude/settings.json
  [ -f "$_settings" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  _command=$(jq -r --arg event "$_event" '.hooks[$event][0].hooks[0].command // empty' "$_settings")
  [ -n "$_command" ] || return 0
  mkdir -p "$EVAL_NOTES" 2>/dev/null
  printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","hook_event_name":"%s","reason":"clear","stop_hook_active":false}' \
    "$_session" "$EVAL_SESSION_DIR/$_session.jsonl" "$EVAL_APP" "$_event" |
    sh -c "$_command" >>"$EVAL_NOTES/hook-settings.out" 2>&1 || :
  eval_note "fired the $_event hook exactly as settings.json declares it"
}

# A knowledge document in the shape the starter policy describes: flat key,
# `created` stamp, no type.
eval_seed_doc() {
  _key=$1
  _created=$2
  _title=$3
  _body=$4
  printf -- '---\ncreated: "%s"\n---\n\n# %s\n\n%s\n' "$_created" "$_title" "$_body" |
    eval_iwe create "$_key" --content - --if-exists skip >/dev/null
  eval_note "seeded $_key created $_created"
}

# A knowledge document as chunk capture writes one under the starter policy's
# provenance section: one date — the chunk header's occurred stamp, stamped as
# created — plus the session it came from, and an origin judged from the digest.
eval_seed_captured_doc() {
  _key=$1
  _created=$2
  _session=$3
  _origin=$4
  _title=$5
  _body=$6
  printf -- '---\ncreated: "%s"\nsession: "%s"\norigin: %s\n---\n\n# %s\n\n%s\n' \
    "$_created" "$_session" "$_origin" "$_title" "$_body" |
    eval_iwe create "$_key" --content - --if-exists skip >/dev/null
  eval_note "seeded $_key created $_created origin $_origin"
}

# The same, for a store running the optional typed ontology.
eval_seed_typed_doc() {
  _type=$1
  _key=$2
  _created=$3
  _title=$4
  _body=$5
  printf -- '---\ntype: %s\ncreated: "%s"\nsession: ""\n---\n\n# %s\n\n%s\n' \
    "$_type" "$_created" "$_title" "$_body" |
    eval_iwe create "$_key" --strict --content - --if-exists skip >/dev/null
  eval_iwe attach -k "$_key" --to daily --quiet >/dev/null 2>&1 || true
  eval_note "seeded $_type $_key created $_created"
}

eval_seed_session_doc() {
  _key=$1
  _created=$2
  _session=$3
  printf -- '---\nsession: "%s"\ncreated: "%s"\ndistilled_lines: 0\n---\n\n# Session %s\n\nAgent session in this workspace.\n' \
    "$_session" "$_created" "$_session" |
    eval_iwe create "sessions/$_key" --content - --if-exists skip >/dev/null
  eval_note "seeded session sessions/$_key created $_created"
}

eval_seed_topic() {
  _key=$1
  _title=$2
  shift 2
  _links=''
  for _member in "$@"; do
    _links="$_links[${_member##*/}](../$_member)

"
  done
  printf -- '---\ntype: topic\ncreated: "%s"\n---\n\n# %s\n\nDocuments this topic covers.\n\n%s' \
    "$(date '+%Y-%m-%d %H:%M')" "$_title" "$_links" |
    eval_iwe create "topics/$_key" --strict --content - --if-exists skip >/dev/null
  eval_note "seeded topic topics/$_key over $*"
}

# A chunk as the sweep imports one, with a `claimed` stamp of your choosing — an
# old one is the lease a dead capture left on it. Written by path, because that
# is how the machinery reads its own state.
# eval_seed_capture_chunk <session> <claimed> <covers_from> <covers_lines> [body]
eval_seed_capture_chunk() {
  _session=$1
  _claimed=$2
  _from=$3
  _covers=$4
  _body=${5:-[user]
a digest no capture ever read}
  mkdir -p "$EVAL_CHUNKS/$_session" 2>/dev/null
  _padded=$(printf '%06d' "$_from")
  printf -- '---\nsession: "%s"\ncreated: "%s"\ncovers_from: %s\ncovers_lines: %s\nmax_items: 3\nclaimed: "%s"\n---\n\n# Capture chunk %s lines %s-%s\n\n%s\n' \
    "$_session" "$_claimed" "$_from" "$_covers" "$_claimed" "$_session" "$_from" "$_covers" "$_body" \
    >"$EVAL_CHUNKS/$_session/$_padded.md"
  eval_note "seeded capture chunk $_session/$_padded claimed $_claimed under $EVAL_CHUNKS"
}

eval_session_dirs() {
  printf '%s\n' "$EVAL_SESSION_DIR"
  find "$EVAL_LOGS" -type d -name projects 2>/dev/null | while read -r _projects; do
    find "$_projects" -mindepth 1 -maxdepth 1 -type d 2>/dev/null
  done
}

eval_seed_transcript() {
  _fixture=$1
  _session=$2
  [ -f "$EVAL_FIXTURES/$_fixture" ] || {
    eval_note "fixture $_fixture is missing"
    return 1
  }
  eval_session_dirs | sort -u | while read -r _dir; do
    mkdir -p "$_dir" 2>/dev/null || continue
    sed -e "s|SESSION_ID|$_session|g" -e "s|PROJECT_CWD|$EVAL_APP|g" \
      "$EVAL_FIXTURES/$_fixture" >"$_dir/$_session.jsonl"
  done
  eval_note "seeded transcript $_session from $_fixture"
}

# The watermark is a field on the session document and nothing else.
eval_watermark() {
  _session=$1
  _lines=$2
  eval_seed_session_doc "$_session" "$(date '+%Y-%m-%d %H:%M')" "$_session"
  eval_iwe update -k "sessions/$_session" --set distilled_lines="$_lines" \
    --expect 1 --quiet >/dev/null 2>&1 || :
  eval_note "watermark $_session = $_lines"
}

eval_settle_watermarks() {
  eval_session_dirs | sort -u | while read -r _dir; do
    for _t in "$_dir"/*.jsonl; do
      [ -f "$_t" ] || continue
      _name=${_t##*/}
      eval_watermark "${_name%.jsonl}" "$(wc -l <"$_t" | tr -d ' ')"
    done
  done
  eval_note "watermarks settled over every seeded transcript"
}

# The pending queue, read off disk the way `job next` reads it.
eval_pending_chunks() {
  find "$EVAL_CHUNKS" -mindepth 2 -name '*.md' 2>/dev/null | sort |
    while read -r _chunk; do
      grep -q '^captured_at:' "$_chunk" 2>/dev/null || printf '%s\n' "$_chunk"
    done
}

# Work the queue the way the distill agent would: take each chunk with
# `job next` and finish it through the CLI's atomic completion — watermark,
# capture note and the captured stamp in one step. It drains the whole queue,
# because that is what one agent run does; the keys given are recorded as
# `--wrote` on the first chunk of the named session.
# eval_complete_capture <session> [key...]
eval_complete_capture() {
  _session=$1
  shift
  _items=$#
  _wrote=''
  while [ "$#" -gt 0 ]; do
    _wrote="$_wrote --wrote $1"
    shift
  done
  _worked=0
  while [ "$_worked" -lt 50 ]; do
    _chunk=$(eval_iwe internal claude job next 2>/dev/null) || :
    [ -n "$_chunk" ] || break
    _this=$(printf '%s\n' "$_chunk" | sed -n 's/^session: //p' | head -1)
    _through=$(printf '%s\n' "$_chunk" | sed -n 's/^covers_lines: //p' | head -1)
    [ -n "$_this" ] && [ -n "$_through" ] || break
    _keys=''
    if [ "$_this" = "$_session" ]; then
      _keys=$_wrote
      _wrote=''
    fi
    # shellcheck disable=SC2086
    _report=$(eval_iwe internal claude job complete "$_this" --lines "$_through" $_keys 2>&1) || :
    eval_note "job complete $_this through line $_through: ${_report:-no output}"
    case $_report in
      completed*) _worked=$((_worked + 1)) ;;
      *) break ;;
    esac
  done
  eval_note "worked $_worked chunk(s) from $_session with $_items item(s)"
}

# Expire every claim on the pending chunks, the way the TTL would, and record
# how many there were so a verifier can report a capture that died with its
# step. The chunks themselves stay — they are materializations, not claims.
eval_release_dead_claims() {
  mkdir -p "$EVAL_NOTES" 2>/dev/null
  _released=$(eval_pending_chunks | grep -c . || :)
  case ${_released:-} in
    ''|*[!0-9]*) _released=0 ;;
  esac
  if [ "$_released" -gt 0 ]; then
    eval_pending_chunks | while read -r _chunk; do
      rm -f "$_chunk"
    done
    eval_note "released $_released pending chunk(s) before this step"
  fi
  printf '%s\n' "$_released" >"$EVAL_NOTES/released-claims"
}

# How many chunks the span would have become at a given character budget,
# computed the way the sweep computes it — one `digest` call per chunk, from
# the watermark, until the transcript runs out. A backfill raises the budget to
# spend fewer passes on the same span, and this is the number it has to beat.
# eval_chunks_at <transcript> <max_chars>
eval_chunks_at() {
  _tail=$1
  _budget=$2
  _from=0
  _chunks=0
  while [ "$_chunks" -lt 200 ]; do
    _covered=$(iwe internal claude digest --path "$_tail" --from "$_from" \
      --max-chars "$_budget" 2>/dev/null | head -1)
    case ${_covered:-0} in
      ''|*[!0-9]*) break ;;
    esac
    [ "$_covered" -gt 0 ] || break
    _from=$((_from + _covered))
    _chunks=$((_chunks + 1))
  done
  printf '%s\n' "$_chunks"
}

# Record that baseline for a seeded session, so a verifier compares the drain
# against a number this fixture actually produces rather than a hard-coded one.
# eval_record_chunk_baseline <session> <max_chars>
eval_record_chunk_baseline() {
  mkdir -p "$EVAL_NOTES" 2>/dev/null
  _tail=$EVAL_SESSION_DIR/$1.jsonl
  [ -f "$_tail" ] || return 0
  _baseline=$(eval_chunks_at "$_tail" "$2")
  printf '%s\n' "$_baseline" >"$EVAL_NOTES/baseline-chunks"
  eval_note "at $2 characters the span of $1 is $_baseline chunk(s)"
}

# Work the queue the way the two-speed drain does: take a batch with
# `job frontier` — one pending chunk per session — and complete every entry in
# it, then take the next batch. The keys given are recorded as `--wrote` on the
# first chunk of the named session; every other entry completes with nothing,
# which is what a triaged empty looks like.
# eval_triage_capture <session> [key...]
eval_triage_capture() {
  _session=$1
  shift
  _wrote=''
  while [ "$#" -gt 0 ]; do
    _wrote="$_wrote --wrote $1"
    shift
  done
  mkdir -p "$EVAL_NOTES" 2>/dev/null
  _rounds=0
  while [ "$_rounds" -lt 20 ]; do
    eval_iwe internal claude job frontier >"$EVAL_NOTES/frontier.out" 2>/dev/null || :
    [ -s "$EVAL_NOTES/frontier.out" ] || break
    _rounds=$((_rounds + 1))
    eval_note "job frontier served batch $_rounds"
    awk '/^session: /{ session = $2 } /^covers_lines: /{ print session " " $2 }' \
      "$EVAL_NOTES/frontier.out" >"$EVAL_NOTES/frontier.list"
    while read -r _this _through; do
      [ -n "$_this" ] && [ -n "$_through" ] || continue
      _keys=''
      if [ "$_this" = "$_session" ]; then
        _keys=$_wrote
        _wrote=''
      fi
      # shellcheck disable=SC2086
      _report=$(eval_iwe internal claude job complete "$_this" --lines "$_through" $_keys 2>&1) || :
      eval_note "job complete $_this through line $_through: ${_report:-no output}"
    done <"$EVAL_NOTES/frontier.list"
  done
  eval_note "worked $_rounds frontier batch(es) starting from $_session"
}

eval_stream_note() {
  mkdir -p "$EVAL_LOGS/agent" 2>/dev/null
  printf '%s\n' "$*" >>"$EVAL_LOGS/agent/claude-code.txt"
}

eval_marker_hooks() {
  _settings=$EVAL_APP/.claude/settings.json
  [ -f "$_settings" ] || return 0
  if ! command -v jq >/dev/null 2>&1; then
    eval_note "jq is unavailable, marker hooks not installed"
    return 0
  fi
  mkdir -p "$EVAL_NOTES/hooks"
  jq --arg tool "$EVAL_TOOLS/marker.sh" '
    .hooks |= with_entries(
      .key as $event
      | .value += [{ hooks: [{ type: "command", command: ($tool + " " + $event), timeout: 10 }] }]
    )
  ' "$_settings" >"$_settings.next" && mv "$_settings.next" "$_settings"
  eval_note "marker hooks installed beside the plugin hooks"
}

eval_finish() {
  eval_note "setup complete"
}
