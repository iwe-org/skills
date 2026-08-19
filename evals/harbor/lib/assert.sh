EVAL_APP=${IWE_EVAL_APP:-/app}
EVAL_CHUNKS=${IWE_MEMORY_STATE:-$EVAL_APP/.iwe/claude-sessions}
EVAL_LOGS=${IWE_EVAL_LOGS:-/logs}
EVAL_SKILLS=${IWE_EVAL_SKILLS:-/opt/iwe-skills}
EVAL_NOTES=$EVAL_APP/.eval
EVAL_VERIFIER=$EVAL_LOGS/verifier
EVAL_REPORT=$EVAL_VERIFIER/report.txt
EVAL_ROWS=''

reward_init() {
  mkdir -p "$EVAL_VERIFIER" "$EVAL_NOTES" 2>/dev/null
  EVAL_ROWS=$EVAL_VERIFIER/.rows
  : >"$EVAL_ROWS"
  : >"$EVAL_REPORT"
}

note() {
  printf '%s\n' "$*" >>"$EVAL_REPORT"
  printf '%s\n' "$*"
}

eval_number() {
  case ${1:-} in
    ''|*[!0-9.]*) printf '0' ;;
    *) printf '%s' "$1" ;;
  esac
}

score() {
  printf '%s\t%s\tscore\n' "$1" "$(eval_number "$2")" >>"$EVAL_ROWS"
  note "score $1 = $(eval_number "$2")"
}

metric() {
  printf '%s\t%s\tmetric\n' "$1" "$(eval_number "$2")" >>"$EVAL_ROWS"
  note "metric $1 = $(eval_number "$2")"
}

check() {
  _name=$1
  shift
  if "$@" >/dev/null 2>&1; then
    score "$_name" 1
  else
    score "$_name" 0
  fi
}

check_not() {
  _name=$1
  shift
  if "$@" >/dev/null 2>&1; then
    score "$_name" 0
  else
    score "$_name" 1
  fi
}

answer() {
  _name=$1
  shift
  if "$@" >/dev/null 2>&1; then
    metric "$_name" 1
  else
    metric "$_name" 0
  fi
}

marker_fired() {
  _hits=$(find "$EVAL_NOTES/hooks" -maxdepth 1 -name "$1-*.json" 2>/dev/null)
  [ -n "$_hits" ]
}

wait_for() {
  _limit=$1
  shift
  _waited=0
  while [ "$_waited" -lt "$_limit" ]; do
    "$@" >/dev/null 2>&1 && return 0
    sleep 1
    _waited=$((_waited + 1))
  done
  "$@" >/dev/null 2>&1
}

reward_write() {
  if agent_api_error; then
    metric agent_api_error 1
    note 'WARNING: the agent stream carries an API error (credit, quota, auth or rate limit).'
    note 'The session died for reasons outside the plugin; this trial scores nothing about it.'
    note 'Do not read this reward as a regression and do not tune a verifier against it.'
  else
    metric agent_api_error 0
  fi
  _reward=$(awk -F'\t' '$3 == "score" { sum += $2; n += 1 }
    END { if (n > 0) printf "%.4f", sum / n; else printf "0" }' "$EVAL_ROWS")
  [ -z "${EVAL_REWARD_OVERRIDE:-}" ] || _reward=$EVAL_REWARD_OVERRIDE
  {
    printf '{"reward": %s' "$_reward"
    awk -F'\t' '{ printf ", \"%s\": %s", $1, $2 }' "$EVAL_ROWS"
    printf '}\n'
  } >"$EVAL_VERIFIER/reward.json"
  printf '%s\n' "$_reward" >"$EVAL_VERIFIER/reward.txt"
  rm -f "$EVAL_ROWS"
  eval_collect
  note "reward $_reward"
}

eval_collect() {
  _dump=$EVAL_VERIFIER/state.txt
  {
    printf '# policy\n'
    mem_iwe find --filter '{ $key: MEMORY }' --project 'fm=$frontmatter' -f json 2>/dev/null
    printf '\n# session records\n'
    mem_iwe find --filter '{ distilled_lines: { $exists: true } }' --limit 0 \
      --project 'session=session,lines=distilled_lines,at=distilled_at,ended=ended' 2>/dev/null
    printf '\n# capture chunks\n'
    chunk_files | while read -r _chunk; do
      printf '%s: ' "${_chunk#"$EVAL_APP/"}"
      sed -n '/^---$/,/^---$/p' "$_chunk" 2>/dev/null | tr '\n' ' '
      printf '\n'
    done
    printf '\n# knowledge documents\n'
    mem_iwe find --filter "$(knowledge_filter)" --limit 0 \
      --project 'key=$key,title=$title,created=created' 2>/dev/null
    printf '\n# capture notes\n'
    grep -r -- '— captured' "$EVAL_APP/sessions" 2>/dev/null
    printf '\n# hook output\n'
    cat "$EVAL_NOTES"/hook-*.out 2>/dev/null
    printf '\n# eval notes\n'
    cat "$EVAL_NOTES"/*.txt 2>/dev/null
    printf '\n# transcripts\n'
    eval_transcripts
    printf '\n# subagent transcripts\n'
    eval_subagent_transcripts
    printf '\n# settings\n'
    cat "$EVAL_APP/.claude/settings.json" 2>/dev/null
  } >"$_dump" 2>/dev/null
  if [ -d "$EVAL_APP/.iwe" ]; then
    ( cd "$EVAL_APP" && tar czf "$EVAL_VERIFIER/memory.tar.gz" \
      --exclude .git --exclude .claude --exclude dist . ) >/dev/null 2>&1
  fi
  return 0
}

eval_session_dirs() {
  find "$EVAL_LOGS" -type d -name projects 2>/dev/null | while read -r _projects; do
    find "$_projects" -mindepth 1 -maxdepth 1 -type d 2>/dev/null
  done
}

eval_transcripts() {
  eval_session_dirs | while read -r _dir; do
    find "$_dir" -maxdepth 1 -name '*.jsonl' 2>/dev/null
  done
}

eval_subagent_transcripts() {
  find "$EVAL_LOGS" -path '*subagent*' -name '*.jsonl' 2>/dev/null
}

eval_stream() {
  find "$EVAL_LOGS" -name 'claude-code.txt' -exec cat {} + 2>/dev/null
}

eval_transcript_text() {
  eval_transcripts | while read -r _t; do
    cat "$_t" 2>/dev/null
  done
}

eval_all_text() {
  eval_stream
  eval_transcript_text
  eval_subagent_transcripts | while read -r _t; do
    cat "$_t" 2>/dev/null
  done
}

eval_longest_tail() {
  _max=0
  eval_transcripts >"$EVAL_VERIFIER/.tails" 2>/dev/null
  while read -r _t; do
    _n=$(wc -l <"$_t" 2>/dev/null | tr -d ' ')
    case $_n in
      ''|*[!0-9]*) continue ;;
    esac
    [ "$_n" -le "$_max" ] || _max=$_n
  done <"$EVAL_VERIFIER/.tails"
  rm -f "$EVAL_VERIFIER/.tails"
  printf '%s\n' "$_max"
}

stream_has() {
  eval_all_text | grep -q -- "$1"
}

agent_launched() {
  eval_all_text | grep -qE '\\?"subagent_type\\?"[ ]*:[ ]*\\?"'"$1"'\\?"'
}

memory_query_seen() {
  eval_all_text | grep -q '"command":"[^"]*iwe '
}

agent_api_error() {
  eval_all_text | grep -qE 'Credit balance is too low|"api_error_status": *[0-9]|rate_limit_error|overloaded_error|authentication_error|insufficient_quota'
}

# --- the store ------------------------------------------------------------
#
# The workspace at /app is the store. Verifiers step into it rather than
# reaching in with -C, exactly as the hooks and agents do.

mem_iwe() {
  ( cd "$EVAL_APP" && iwe "$@" 2>/dev/null )
}

is_workspace() {
  [ -d "$EVAL_APP/.iwe" ] || [ -f "$EVAL_APP/iwe.toml" ]
}

memory_enabled() {
  _hit=$(mem_iwe find --filter '{ $key: MEMORY }' -f keys --limit 1)
  [ -n "$_hit" ]
}

memory_knob() {
  mem_iwe find --filter '{ $key: MEMORY }' --project 'fm=$frontmatter' -f json --limit 1 |
    jq -r --arg name "$1" '.[0].fm[$name] // empty' 2>/dev/null
}

# The store's knowledge: dated documents that are neither machinery nor policy.
# The repository's own markdown — README, CLAUDE.md, docs — is in the same graph
# and carries no `created` stamp, which is what keeps it out of these counts.
knowledge_filter() {
  printf '{ created: { $exists: true }, distilled_lines: { $exists: false }, covers_lines: { $exists: false }, $key: { $nin: [MEMORY, queries] } }'
}

# What capture actually wrote: the documents a session record includes. This is
# the provenance mechanism, so asserting on it also tests that the capture
# note's inclusion links resolved.
captured_filter() {
  printf '{ $includedBy: { match: { distilled_lines: { $exists: true } } } }'
}

captured_keys() {
  mem_keys "$(captured_filter)"
}

captured_count() {
  mem_count "$(captured_filter)"
}

mem_keys() {
  mem_iwe find --filter "$1" -f keys --limit 0
}

mem_count() {
  _n=$(mem_keys "$1" | grep -c .)
  case $_n in
    ''|*[!0-9]*) _n=0 ;;
  esac
  printf '%s\n' "$_n"
}

knowledge_count() {
  mem_count "$(knowledge_filter)"
}

mem_valid() {
  mem_iwe schema validate >/dev/null 2>&1
}

# Knowledge documents whose content mentions a string.
mem_text() {
  _base=$(knowledge_filter)
  _filter="${_base%\}}, \$content: { \$text: \"$1\" } }"
  mem_iwe find --filter "$_filter" -f keys --limit 0
}

mem_has_text() {
  _hits=$(mem_text "$1")
  [ -n "$_hits" ]
}

# Type-scoped content search, for a store running an ontology that has types.
mem_type_has_text() {
  _filter="{ type: { \$in: [$1] }, \$content: { \$text: \"$2\" } }"
  _hits=$(mem_iwe find --filter "$_filter" -f keys --limit 0)
  [ -n "$_hits" ]
}

daily_links_a_memory() {
  grep -rqE '\((\.\./)?(learnings|gotchas|decisions)/' "$EVAL_APP/daily" 2>/dev/null
}

mem_attached_today() {
  grep -rq -- "$1" "$EVAL_APP/daily" 2>/dev/null
}

daily_link_count() {
  _n=$(grep -rc -- "$1" "$EVAL_APP/daily" 2>/dev/null |
    awk -F: '{ sum += $NF } END { print sum + 0 }')
  eval_number "$_n"
  printf '\n'
}

# The machinery keeps no state files: what it writes are documents, all of them
# under the one prefix it owns.
store_has_no_state_files() {
  _stray=$(find "$EVAL_APP/sessions" -type f ! -name '*.md' 2>/dev/null)
  [ -z "$_stray" ]
}

run_in_app() {
  ( cd "$EVAL_APP" && "$@" )
}

git_head_untouched() {
  _n=$(git -C "$EVAL_APP" log --oneline 2>/dev/null | grep -c .)
  [ "$_n" = "1" ] || return 1
  git -C "$EVAL_APP" diff --cached --quiet 2>/dev/null
}

# --- sweep state, all of it read out of the store -------------------------

mem_watermark() {
  _w=$(mem_iwe find --filter "{ distilled_lines: { \$exists: true }, session: \"$1\" }" \
    --project 'lines=distilled_lines' -f json --limit 1 |
    jq -r '.[0].lines // 0' 2>/dev/null)
  case ${_w:-} in
    ''|null|*[!0-9]*) _w=0 ;;
  esac
  printf '%s\n' "$_w"
}

mem_watermark_max() {
  _max=$(mem_iwe find --filter '{ distilled_lines: { $exists: true } }' \
    --project 'lines=distilled_lines' -f json --limit 0 |
    jq -r '[.[].lines // 0] | max // 0' 2>/dev/null)
  case ${_max:-} in
    ''|null|*[!0-9]*) _max=0 ;;
  esac
  printf '%s\n' "$_max"
}

session_records() {
  mem_count '{ distilled_lines: { $exists: true } }'
}

# A session record that carries a capture note has been through a completed
# capture, whatever the capture decided to keep.
capture_noted() {
  grep -q -- '— captured' "$EVAL_APP/sessions/$1.md" 2>/dev/null
}

# The provenance mechanism: the capture note's inclusion links make the
# session record include every document that capture wrote.
provenance_linked() {
  mem_iwe find --filter "{ \$includedBy: sessions/$1 }" -f keys | grep -q .
}

# The starter policy's provenance fields, on every knowledge document — and
# exactly one date: `created`, holding when the fact came about. A document
# carrying a second `occurred` stamp beside it fails this.
knowledge_carries_provenance() {
  _all=$(knowledge_count)
  [ "$_all" -gt 0 ] || return 1
  _stamped=$(mem_count '{ created: { $exists: true }, origin: { $exists: true }, occurred: { $exists: false }, distilled_lines: { $exists: false }, covers_lines: { $exists: false }, $key: { $nin: [MEMORY, queries] } }')
  [ "$_all" = "$_stamped" ]
}

# The machinery's session time range, stamped from transcript timestamps.
session_time_stamped() {
  mem_iwe find --filter '{ distilled_lines: { $exists: true }, started: { $exists: true }, ended: { $exists: true } }' -f keys --limit 1 | grep -q .
}

# The chunk queue, read off disk the way the machinery reads it: plain files
# under the workspace's `.iwe/claude-sessions/`, never documents in the graph.
chunk_files() {
  find "$EVAL_CHUNKS" -mindepth 2 -name '*.md' 2>/dev/null | sort
}

session_chunk_files() {
  find "$EVAL_CHUNKS/$1" -name '*.md' 2>/dev/null | sort
}

# A chunk is pending until completion stamps `captured_at` on it. Chunks are
# never deleted, so the stamp — not the file — is what leaves the queue.
pending_chunk_files() {
  chunk_files | while read -r _chunk; do
    grep -q '^captured_at:' "$_chunk" 2>/dev/null || printf '%s\n' "$_chunk"
  done
}

pending_chunks() {
  eval_number "$(pending_chunk_files | grep -c . || :)"
  printf '\n'
}

session_has_chunks() {
  [ -n "$(session_chunk_files "$1")" ]
}

# The tail was imported at some point: either its chunks are still on disk, or
# the capture that worked them left the watermark behind.
tail_claimed() {
  session_has_chunks "$1" && return 0
  [ "$(mem_watermark "$1")" -gt 0 ]
}

no_stale_claims() {
  [ "$(pending_chunks)" = "0" ]
}

# Transcripts with more lines than their session record accounts for.
pending_tails() {
  _pending=0
  eval_transcripts >"$EVAL_VERIFIER/.pending" 2>/dev/null
  while read -r _t; do
    [ -f "$_t" ] || continue
    _name=${_t##*/}
    _lines=$(wc -l <"$_t" 2>/dev/null | tr -d ' ')
    case ${_lines:-} in
      ''|*[!0-9]*) continue ;;
    esac
    [ "$_lines" -gt "$(mem_watermark "${_name%.jsonl}")" ] || continue
    _pending=$((_pending + 1))
  done <"$EVAL_VERIFIER/.pending"
  rm -f "$EVAL_VERIFIER/.pending"
  printf '%s\n' "$_pending"
}

backlog_drained() {
  [ "$(pending_tails)" = "0" ]
}

# --- what a backfill drain leaves behind ----------------------------------
#
# `chunk_chars` and `max_items_per_chunk` are read at import time and stamped
# into every chunk document, so the chunks themselves are the durable record of
# the budget a drain imported under — a restore afterwards cannot erase it.

chunk_item_budget() {
  session_chunk_files "$1" | while read -r _chunk; do
    sed -n 's/^max_items: *//p' "$_chunk" 2>/dev/null | head -1
  done | sort -n | tail -1
}

chunk_budget_at_least() {
  _found=$(eval_number "$(chunk_item_budget "$1")")
  [ "$_found" -ge "$2" ]
}

session_chunk_count() {
  eval_number "$(session_chunk_files "$1" | grep -c . || :)"
  printf '\n'
}

baseline_chunks() {
  eval_number "$(cat "$EVAL_NOTES/baseline-chunks" 2>/dev/null)"
  printf '\n'
}

# The whole point of the larger budget: the same span, fewer passes.
chunks_below_baseline() {
  _baseline=$(baseline_chunks)
  [ "$_baseline" -gt 0 ] || return 1
  [ "$(session_chunk_count "$1")" -lt "$_baseline" ]
}

# The live-capture defaults, back in place after the last wave's import.
capture_defaults_restored() {
  case $(memory_knob chunk_chars) in
    10000|'') ;;
    *) return 1 ;;
  esac
  case $(memory_knob max_items_per_chunk) in
    3|'') return 0 ;;
  esac
  return 1
}

# A chunk boundary landing mid-line is a boundary, not content: the marker
# belongs in the digest and never in a memory document.
no_truncation_marker_in_memory() {
  ! mem_has_text 'truncated at'
}

# Sessions whose capture read the span and kept nothing — the cheap completion
# a triage pass is supposed to produce.
empty_captures() {
  eval_number "$(grep -rl -- 'captured 0 item(s)' "$EVAL_APP/sessions" 2>/dev/null | grep -c . || :)"
  printf '\n'
}

frontier_used() {
  stream_has 'job frontier'
}

stream_count() {
  eval_number "$(eval_all_text | grep -c -- "$1" || :)"
  printf '\n'
}

# Nothing from the plugin's optional ontology exists here — the check that the
# machinery imposed no structure of its own.
no_default_ontology() {
  _found=$(find "$EVAL_APP/learnings" "$EVAL_APP/decisions" "$EVAL_APP/gotchas" \
    "$EVAL_APP/topics" "$EVAL_APP/daily" -name '*.md' 2>/dev/null)
  [ -z "$_found" ] || return 1
  [ "$(mem_count '{ type: { $in: [learning, decision, gotcha, topic] } }')" = "0" ]
}

# What the sweep decided, as it left it in .eval/hook-stop.out. Only says
# anything when the sweep was run by an oracle rather than by the live hook.
# The binary's built-in reason names distill, so the block text is the
# same whether the oracle or the plugin's hook ran it.
eval_sweep_blocked() {
  grep -q '"decision": *"block"' "$EVAL_NOTES/hook-stop.out" 2>/dev/null
}

chunk_created_at() {
  _chunk=$(session_chunk_files "$1" | head -1)
  [ -n "$_chunk" ] || return 0
  sed -n 's/^created: *//p' "$_chunk" 2>/dev/null | head -1 | tr -d '"'
}

# --- the fixture project --------------------------------------------------

deploy_target() {
  cat "$EVAL_APP/.deploy-receipt" 2>/dev/null
}

deploy_target_known() {
  case $(deploy_target) in
    staging-blue|staging-green) return 0 ;;
  esac
  return 1
}

deploy_attempts() {
  eval_number "$(grep -c . "$EVAL_APP/.deploy-attempts" 2>/dev/null)"
  printf '\n'
}

deploy_blind_attempts() {
  eval_number "$(grep -c '<unset>' "$EVAL_APP/.deploy-attempts" 2>/dev/null)"
  printf '\n'
}
