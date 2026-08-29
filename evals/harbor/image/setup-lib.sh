EVAL_APP=${IWE_EVAL_APP:-/app}
EVAL_LOGS=${IWE_EVAL_LOGS:-/logs}
EVAL_SKILLS=${IWE_EVAL_SKILLS:-/opt/iwe-skills}
EVAL_TOOLS=${IWE_EVAL_TOOLS:-/opt/iwe-evals}
EVAL_FIXTURES=${IWE_EVAL_FIXTURES:-$EVAL_TOOLS/fixtures}
EVAL_NOTES=$EVAL_APP/.eval
EVAL_STATE=$EVAL_APP/.iwe/claude
EVAL_RECORDS=$EVAL_STATE/sessions
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

# Run the session-start hook exactly as the harness would: payload on stdin,
# output kept where the verifier can read it. The post-tool net is fired by
# eval_post_tool_write below, from the settings the fixture ships.
eval_hook() {
  _hook=$1
  _session=${2:-00000000-0000-4000-8000-000000000000}
  _reason=${3:-clear}
  mkdir -p "$EVAL_NOTES" 2>/dev/null
  printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","hook_event_name":"%s","reason":"%s"}' \
    "$_session" "$EVAL_SESSION_DIR/$_session.jsonl" "$EVAL_APP" "$_hook" "$_reason" |
    ( cd "$EVAL_APP" && IWE_MEMORY_TRANSCRIPTS=$EVAL_SESSION_DIR \
      iwe internal claude hook "$_hook" ) >>"$EVAL_NOTES/hook-$_hook.out" 2>&1 || :
  eval_note "ran the $_hook hook for $_session"
}

# Fire a hook the way Claude Code fires it: the command out of the project's
# settings.json, verbatim, with the payload on stdin. Used where the point is
# the wiring itself rather than what the hook prints.
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

# Fire the PostToolUse net over one file the way Claude Code fires it: the
# command out of the project's settings.json, verbatim, with a Write payload on
# stdin. The oracle uses this because it edits files directly rather than
# through the tool calls that would trigger the hook for a real agent.
eval_post_tool_write() {
  _relative=$1
  _tool=${2:-Write}
  _settings=$EVAL_APP/.claude/settings.json
  [ -f "$_settings" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  _command=$(jq -r '.hooks.PostToolUse[0].hooks[0].command // empty' "$_settings")
  [ -n "$_command" ] || return 0
  mkdir -p "$EVAL_NOTES" 2>/dev/null
  jq -n --arg cwd "$EVAL_APP" --arg tool "$_tool" --arg path "$EVAL_APP/$_relative" \
    '{cwd: $cwd, hook_event_name: "PostToolUse", tool_name: $tool,
      tool_input: {file_path: $path}, tool_response: {success: true}}' |
    ( cd "$EVAL_APP" && sh -c "$_command" ) >>"$EVAL_NOTES/post-tool.out" 2>&1 || :
  eval_note "fired the post-tool net over $_relative"
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

# A knowledge document as a distill run writes one under the starter policy's
# provenance section: one date — the `occurred` stamp of the span it was read
# from, stamped as created — plus the session it came from.
eval_seed_captured_doc() {
  _key=$1
  _created=$2
  _session=$3
  _title=$4
  _body=$5
  printf -- '---\ncreated: "%s"\nsession: "%s"\n---\n\n# %s\n\n%s\n' \
    "$_created" "$_session" "$_title" "$_body" |
    eval_iwe create "$_key" --content - --if-exists skip >/dev/null
  eval_note "seeded $_key created $_created"
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

# A session record as the engine keeps one: the whole of a session's state is
# .iwe/claude/sessions/<id>.yaml, outside the graph. Seeding one stands for a
# session already seen — the distilled line set, no completion stamp, which is
# what `adopt` leaves. `session complete` refuses an id it has never heard of,
# so this is also what makes a ledger entry legal for a session whose
# transcript is not on disk. An existing record keeps everything but the line.
# eval_seed_session_record <session> [lines]
eval_seed_session_record() {
  _session=$1
  _lines=${2:-0}
  _record=$EVAL_RECORDS/$_session.yaml
  mkdir -p "$EVAL_RECORDS" 2>/dev/null
  if [ -f "$_record" ]; then
    grep -v '^distilled_lines:' "$_record" >"$_record.next"
    printf 'distilled_lines: %s\n' "$_lines" >>"$_record.next"
    mv "$_record.next" "$_record"
  else
    printf 'session: %s\ndistilled_lines: %s\n' "$_session" "$_lines" >"$_record"
  fi
  eval_note "seeded session record $_session distilled through line $_lines"
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

# `session list` reads the last message's timestamp, so a conversation is live
# because its transcript says so, not because its file was touched. This is how
# a seeded fixture becomes one.
eval_make_live() {
  _session=$1
  _now=$(date -u '+%Y-%m-%dT%H:%M:%S.000Z')
  eval_session_dirs | sort -u | while read -r _dir; do
    _t=$_dir/$_session.jsonl
    [ -f "$_t" ] || continue
    sed -e "s/\"timestamp\":\"[^\"]*\"/\"timestamp\":\"$_now\"/g" \
      -e "s/\"timestamp\": \"[^\"]*\"/\"timestamp\": \"$_now\"/g" \
      "$_t" >"$_t.next" && mv "$_t.next" "$_t"
  done
  eval_note "restamped $_session to now: it reads as a live conversation"
}

# The line a session is distilled through is a field on its record and
# nothing else.
eval_watermark() {
  eval_seed_session_record "$1" "$2"
}

eval_settle_watermarks() {
  eval_session_dirs | sort -u | while read -r _dir; do
    for _t in "$_dir"/*.jsonl; do
      [ -f "$_t" ] || continue
      _name=${_t##*/}
      eval_watermark "${_name%.jsonl}" "$(wc -l <"$_t" | tr -d ' ')"
    done
  done
  eval_note "every seeded transcript is distilled to its end"
}

# --- the foreground flow, driven by an oracle -----------------------------
#
# There is no queue and no background agent. What an oracle stands in for is a
# user sitting in front of the proposals: read the span, then record what was
# selected. The two are separate commands on purpose — reading writes nothing,
# so a run that stops after reading leaves the store untouched.

eval_session() {
  ( cd "$EVAL_APP" && IWE_MEMORY_TRANSCRIPTS=$EVAL_SESSION_DIR \
    iwe internal claude session "$@" ) 2>&1
}

# Read one session's undistilled span the way a distill run reads it, a window
# at a time, leaving the digests where a verifier can see what was on offer.
# Prints the line the reading reached.
# eval_read_session <session>
eval_read_session() {
  _session=$1
  _from=0
  _window=0
  mkdir -p "$EVAL_NOTES" 2>/dev/null
  while [ "$_window" -lt 20 ]; do
    _read=$(eval_session read "$_session" --from "$_from") || break
    printf '%s\n' "$_read" >>"$EVAL_NOTES/session-read.out"
    _covered=$(printf '%s\n' "$_read" | sed -n 's/^covers_lines: //p' | head -1)
    case ${_covered:-} in
      ''|*[!0-9]*) break ;;
    esac
    [ "$_covered" -gt "$_from" ] || break
    _from=$_covered
    _window=$((_window + 1))
  done
  eval_note "read $_window window(s) of $_session, through line $_from"
  printf '%s\n' "$_from"
}

# Record a selection: the span that was read, how many items were put up, one
# title the user turned down, and the keys they kept.
# eval_record_selection <session> <lines> <offered> <rejected-title> [key...]
eval_record_selection() {
  _session=$1
  _lines=$2
  _offered=$3
  _rejected=$4
  shift 4
  _keys=$#
  while [ "$_keys" -gt 0 ]; do
    set -- "$@" --wrote "$1"
    shift
    _keys=$((_keys - 1))
  done
  [ -z "$_rejected" ] || set -- "$@" --rejected "$_rejected"
  [ -z "$_lines" ] || set -- "$@" --lines "$_lines"
  _report=$(eval_session complete "$_session" --offered "$_offered" "$@")
  eval_note "session complete $_session${_lines:+ through $_lines}: ${_report:-no output}"
}

# A selection made in the session at hand: the items came out of the live
# conversation, not a span on disk, so nothing was read and no line moves —
# only the ledger and the links to what was kept.
# eval_record_in_session <session> <offered> [key...]
eval_record_in_session() {
  _here=$1
  _put_up=$2
  shift 2
  eval_record_selection "$_here" "" "$_put_up" "" "$@"
}

# The oracle's whole distill run over one session: read it, then record the
# selection. Any document the "user" kept is written by the caller first.
# eval_distill_session <session> <offered> <rejected-title> [key...]
eval_distill_session() {
  _session=$1
  _offered=$2
  _rejected=$3
  shift 3
  _through=$(eval_read_session "$_session")
  eval_record_selection "$_session" "$_through" "$_offered" "$_rejected" "$@"
}

# An offer the user declined mid-conversation: the ledger records it, and
# nothing else moves.
# eval_record_declined_offer <session> <title>
eval_record_declined_offer() {
  _report=$(eval_session complete "$1" --offered 1 --rejected "$2")
  eval_note "declined offer on $1: ${_report:-no output}"
}

# Mark sessions seen without reading them.
eval_adopt() {
  eval_session adopt "$@" >>"$EVAL_NOTES/session-adopt.out" 2>&1 || :
  eval_note "adopted ${*:-every pending session}"
}

# What the flow reads before it proposes anything.
eval_brief() {
  ( cd "$EVAL_APP" && iwe internal claude session brief ) >>"$EVAL_NOTES/session-brief.out" 2>&1 || :
  eval_note 'read the session brief'
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

# --- quality fixtures -----------------------------------------------------

eval_slug() {
  printf '%s' "$1" | tr 'A-Z' 'a-z' | sed -e 's/[^a-z0-9]/-/g' -e 's/--*/-/g' -e 's/^-//' -e 's/-$//'
}

# Sixty plausible, irrelevant documents in the starter shape, so recall has to
# find the right eight among seventy rather than among eight.
eval_seed_distractors() {
  _n=0
  while IFS='|' read -r _title _body; do
    case $_title in
      ''|'#'*) continue ;;
    esac
    eval_seed_doc "$(eval_slug "$_title")" "$2" "$_title" "$_body"
    _n=$((_n + 1))
  done <"$1"
  eval_note "seeded $_n distractor documents"
}

# A labelled fixture's question set, fixtures/questions/<fixture>.tsv: one
# row per question — n, class, question, require, forbid, answer. The gold
# rows ask one question per gold item; a stale row asks something the
# repository answers and a seeded document contradicts.
eval_question_file() {
  printf '%s/questions/%s.tsv\n' "$EVAL_FIXTURES" "${1:-tail-dense}"
}

# eval_seed_questions [fixture] [class]: render the questions, numbered as
# the file numbers them, into .eval/questions.md. A class keeps only its rows.
eval_seed_questions() {
  _fixture=${1:-tail-dense}
  _class=${2:-}
  mkdir -p "$EVAL_NOTES" 2>/dev/null
  awk -F'\t' -v class="$_class" '
    /^[ \t]*#/ || NF < 3 { next }
    class == "" || $2 == class { printf "%s. %s\n", $1, $3 }
  ' "$(eval_question_file "$_fixture")" >"$EVAL_NOTES/questions.md"
  eval_note "wrote $(grep -c . "$EVAL_NOTES/questions.md") question(s) from questions/$_fixture.tsv to .eval/questions.md"
}

# The answers the oracle gives, in the shape the instruction asks for.
# eval_oracle_answers [fixture] [class]
eval_oracle_answers() {
  awk -F'\t' -v class="${2:-}" '
    /^[ \t]*#/ || NF < 6 { next }
    class == "" || $2 == class { printf "%s. %s\n", $1, $6 }
  ' "$(eval_question_file "${1:-tail-dense}")"
}

# The questions' own words, as search terms for an oracle that has to be seen
# consulting memory. eval_oracle_search_terms [fixture] [class]
eval_oracle_search_terms() {
  awk -F'\t' -v class="${2:-}" '
    /^[ \t]*#/ || NF < 3 { next }
    class == "" || $2 == class { print $3 }
  ' "$(eval_question_file "${1:-tail-dense}")" | tr -c 'A-Za-z0-9 \n' ' ' | tr -s ' '
}

# A labelled fixture's oracle, fixtures/oracle/<fixture>.md: the proposals a
# perfect distill run over the transcript would put up, one `## ` heading per
# item with the document body a perfect run would write. check.sh scores it
# against the gold set and expects 1.0, so a gold row no oracle can hit is
# caught before a model is ever asked to.
eval_oracle_file() {
  printf '%s/oracle/%s.md\n' "$EVAL_FIXTURES" "$1"
}

# eval_oracle_proposals <fixture> <session>: the oracle's proposals file.
eval_oracle_proposals() {
  mkdir -p "$EVAL_NOTES" 2>/dev/null
  sed "s|SESSION_ID|$2|g" "$(eval_oracle_file "$1")" >"$EVAL_NOTES/proposals.md"
  eval_note "wrote the oracle proposals for $1 to .eval/proposals.md"
}

# eval_seed_oracle_docs <fixture> <session> <occurred>: one knowledge document
# per oracle proposal, keyed by a slug of its title as the starter policy
# says, stamped with the occurred time and the session. Prints the keys.
eval_seed_oracle_docs() {
  _dir=$EVAL_NOTES/oracle-docs
  rm -rf "$_dir"
  mkdir -p "$_dir"
  awk -v dir="$_dir" '
    /^## / { if (out != "") close(out); n += 1; out = sprintf("%s/%03d", dir, n); sub(/^## /, ""); print >out; next }
    out != "" { print >>out }
  ' "$(eval_oracle_file "$1")"
  for _u in "$_dir"/*; do
    [ -f "$_u" ] || continue
    _title=$(head -1 "$_u")
    _body=$(awk 'NR > 1 { if (!started && $0 == "") next; started = 1; line[++n] = $0 }
      END { while (n > 0 && line[n] == "") n -= 1; for (i = 1; i <= n; i++) print line[i] }' "$_u")
    _key=$(eval_slug "$_title")
    eval_seed_captured_doc "$_key" "$3" "$2" "$_title" "$_body"
    printf '%s\n' "$_key"
  done
}

# When a seeded session's span occurred: its transcript's first timestamp, in
# the shape the policy stamps `created` with.
eval_occurred() {
  sed -n 's/.*"timestamp":"\([0-9-]*\)T\([0-9]*:[0-9]*\):[^"]*".*/\1 \2/p' \
    "$EVAL_SESSION_DIR/$1.jsonl" 2>/dev/null | head -1
}
