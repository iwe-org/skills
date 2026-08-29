EVAL_APP=${IWE_EVAL_APP:-/app}
EVAL_LOGS=${IWE_EVAL_LOGS:-/logs}
EVAL_SESSION_DIR=${IWE_EVAL_SESSION_DIR:-$EVAL_LOGS/agent/sessions/projects/-app}
EVAL_SKILLS=${IWE_EVAL_SKILLS:-/opt/iwe-skills}
EVAL_NOTES=$EVAL_APP/.eval
EVAL_VERIFIER=$EVAL_LOGS/verifier
EVAL_STATE=$EVAL_APP/.iwe/claude
EVAL_RECORDS=$EVAL_STATE/sessions
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
    printf '\n# session records: distilled line, ledger and captures\n'
    session_record_dump
    printf '\n# the session listing\n'
    session_listing --all
    printf '\n# knowledge documents\n'
    mem_iwe find --filter "$(knowledge_filter)" --limit 0 \
      --project 'key=$key,title=$title,created=created,session=session' 2>/dev/null
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

# The store's knowledge: dated documents that are not the policy. The
# repository's own markdown — README, CLAUDE.md, docs — is in the same graph
# and carries no `created` stamp, which is what keeps it out of these counts.
# Session records are not in the graph at all, so nothing filters them.
knowledge_filter() {
  printf '{ created: { $exists: true }, $key: { $nin: [MEMORY, queries] } }'
}

# What capture actually wrote: the keys the session records list under their
# captures. `session complete --wrote` resolved each against the graph when it
# ran, so this is the machinery's own side of provenance.
captured_keys() {
  session_record_wrote
}

captured_count() {
  _n=$(captured_keys | grep -c .)
  case $_n in
    ''|*[!0-9]*) _n=0 ;;
  esac
  printf '%s\n' "$_n"
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

# The machinery keeps its state in one directory outside the graph,
# .iwe/claude/: a yaml record per session, the reminder stamp and the gitignore
# that hides it. Nothing else may appear there, and nothing may come back under
# the store prefix an earlier release kept its records in.
store_has_no_state_files() {
  [ ! -e "$EVAL_APP/sessions" ] || return 1
  [ ! -e "$EVAL_APP/.iwe/claude-sessions" ] || return 1
  _stray=$(find "$EVAL_STATE" -type f ! -name '*.yaml' \
    ! -name '.reminded' ! -name '.gitignore' 2>/dev/null)
  [ -z "$_stray" ]
}

# The reminder stamp moves whenever the hook reminds, so an unmoved stamp is
# the reminder not repeating — evidence a model run leaves behind too. The
# setup stashes what it wrote, because a stamp written `now` cannot be a
# literal in a verifier.
reminder_stamp_unchanged() {
  _before=$EVAL_NOTES/reminded.before
  [ -f "$_before" ] || return 1
  [ "$(cat "$EVAL_STATE/.reminded" 2>/dev/null)" = "$(cat "$_before" 2>/dev/null)" ]
}

reminder_stamp_ignored() {
  [ ! -f "$EVAL_STATE/.reminded" ] && return 0
  grep -q '\.reminded' "$EVAL_STATE/.gitignore" 2>/dev/null
}

run_in_app() {
  ( cd "$EVAL_APP" && "$@" )
}

# --- the post-tool net ----------------------------------------------------

# A document is in the store's canonical form when normalizing it again is a
# no-op: `iwe normalize -k` prints only the paths it actually had to change.
is_canonical() {
  _out=$(mem_iwe normalize -k "$1" 2>/dev/null)
  [ -z "$_out" ]
}

# The inverse, for files the net must never touch: byte-for-byte what was seeded.
file_is_verbatim() {
  [ "$(cat "$EVAL_APP/$1" 2>/dev/null)" = "$2" ]
}

git_head_untouched() {
  _n=$(git -C "$EVAL_APP" log --oneline 2>/dev/null | grep -c .)
  [ "$_n" = "1" ] || return 1
  git -C "$EVAL_APP" diff --cached --quiet 2>/dev/null
}

# --- how far each session is distilled, read off the session records ------
#
# A session's whole state is .iwe/claude/sessions/<id>.yaml, outside the graph:
# the line it is distilled through, when, the transcript's span, the selection
# ledger and every capture with the keys it wrote. The helpers here read that
# file in the shape serde_yaml writes it, and nothing else.

session_record_path() {
  printf '%s/%s.yaml\n' "$EVAL_RECORDS" "$1"
}

session_record_field() {
  sed -n "s/^$2: *//p" "$(session_record_path "$1")" 2>/dev/null | head -1
}

# One of the two lists a record carries: the titles under `rejected:`, or the
# keys under every capture's `wrote:`, one per line, quotes stripped.
session_record_list() {
  awk -v want="$2" '
    /^[^ -]/ { top = $1; sub(/:$/, "", top); inner = "" }
    /^- / && top == "captures" { inner = "" }
    /^  [^ -]/ && top == "captures" { inner = $1; sub(/:$/, "", inner) }
    want == "rejected" && top == "rejected" && /^- / { item = substr($0, 3) }
    want == "wrote" && top == "captures" && inner == "wrote" && /^  - / { item = substr($0, 5) }
    item != "" { gsub(/^["'"'"']|["'"'"']$/, "", item); print item; item = "" }
  ' "$(session_record_path "$1")" 2>/dev/null
}

session_record_ids() {
  for _r in "$EVAL_RECORDS"/*.yaml; do
    [ -f "$_r" ] || continue
    _r=${_r##*/}
    printf '%s\n' "${_r%.yaml}"
  done
}

session_record_wrote() {
  session_record_ids | while read -r _id; do
    session_record_list "$_id" wrote
  done
}

session_record_dump() {
  session_record_ids | while read -r _id; do
    printf -- '--- %s.yaml\n' "$_id"
    cat "$(session_record_path "$_id")"
  done
}

mem_watermark() {
  _w=$(session_record_field "$1" distilled_lines)
  case ${_w:-} in
    ''|*[!0-9]*) _w=0 ;;
  esac
  printf '%s\n' "$_w"
}

mem_watermark_max() {
  _max=0
  for _id in $(session_record_ids); do
    _w=$(mem_watermark "$_id")
    [ "$_w" -le "$_max" ] || _max=$_w
  done
  printf '%s\n' "$_max"
}

session_records() {
  eval_number "$(session_record_ids | grep -c .)"
  printf '\n'
}

# A completion that kept something appends a capture to the record: when it
# ran, the line it reached and the keys it wrote. A completion that kept
# nothing stamps `distilled_at` and adds no capture — see session_distilled.
capture_noted() {
  grep -q '^captures:' "$(session_record_path "$1")" 2>/dev/null
}

# The provenance mechanism, from the record's side: every key a completion
# listed under `wrote:` is a document in the graph now, and there is at least
# one. `complete` refused keys it could not resolve when it ran; this is that
# they are still there.
provenance_linked() {
  _wrote=$(session_record_list "$1" wrote)
  [ -n "$_wrote" ] || return 1
  printf '%s\n' "$_wrote" | while read -r _key; do
    [ -n "$_key" ] || continue
    mem_iwe retrieve -k "$_key" >/dev/null || exit 1
  done
}

# The other direction, under a policy whose shape carries it: the documents a
# session produced say so themselves, `{ session: "<id>" }` in their frontmatter.
session_produced() {
  mem_keys "{ session: \"$1\" }"
}

# The starter policy's provenance fields, on every knowledge document — the
# session it came from, and exactly one date: `created`, holding when the fact
# came about. A document carrying a second `occurred` stamp beside it fails this.
knowledge_carries_provenance() {
  _all=$(knowledge_count)
  [ "$_all" -gt 0 ] || return 1
  _stamped=$(mem_count '{ created: { $exists: true }, session: { $exists: true }, occurred: { $exists: false }, $key: { $nin: [MEMORY, queries] } }')
  [ "$_all" = "$_stamped" ]
}

# The machinery's session time range, stamped from transcript timestamps.
session_time_stamped() {
  for _id in $(session_record_ids); do
    _r=$(session_record_path "$_id")
    if grep -q '^started: ' "$_r" && grep -q '^ended: ' "$_r"; then
      return 0
    fi
  done
  return 1
}

# --- the session family, the only reader memory has ----------------------
#
# Nothing sweeps: what a session's state is comes from `session list`, and what
# a distill run did to it comes from the record it wrote.

session_listing() {
  ( cd "$EVAL_APP" && IWE_MEMORY_TRANSCRIPTS=$EVAL_SESSION_DIR \
    iwe internal claude session list "$@" 2>/dev/null )
}

session_row() {
  session_listing --all | grep "^$1" | head -1
}

session_state() {
  session_row "$1" | awk '{ print $(NF-1) }'
}

session_is() {
  _row=$(session_row "$1")
  [ -n "$_row" ] || return 1
  case " $_row " in
    *" $2 "*) return 0 ;;
  esac
  return 1
}

session_listed() {
  [ -n "$(session_row "$1")" ]
}

# `session read` never advances anything on its own — reading is separate from
# recording, which is what makes an unattended run harmless.
session_read_span() {
  ( cd "$EVAL_APP" && IWE_MEMORY_TRANSCRIPTS=$EVAL_SESSION_DIR \
    iwe internal claude session read "$1" 2>/dev/null )
}

# The selection ledger the feedback loop learns from.
session_field() {
  session_record_field "$1" "$2"
}

session_offered() {
  eval_number "$(session_field "$1" offered)"
  printf '\n'
}

session_kept() {
  eval_number "$(session_field "$1" kept)"
  printf '\n'
}

session_rejected_count() {
  eval_number "$(session_record_list "$1" rejected | grep -c .)"
  printf '\n'
}

session_rejected() {
  session_record_list "$1" rejected | grep -q -- "$2"
}

# A session record exists at all: the distill run reached its completion step.
session_recorded() {
  [ -f "$(session_record_path "$1")" ]
}

# Read and completed: a distill run stamped it. Note that `session list` calls
# a conversation whose last message landed in the last half hour `active`
# whatever its record says — being live is the safety-relevant fact — so the
# record, not the row, is what says a session was distilled.
session_distilled() {
  session_recorded "$1" || return 1
  grep -q '^distilled_at:' "$(session_record_path "$1")" 2>/dev/null
}

# Adopted rather than read: the distilled line moved, no completion stamped it.
session_adopted() {
  session_recorded "$1" || return 1
  [ "$(mem_watermark "$1")" -gt 0 ] || return 1
  ! grep -q '^distilled_at:' "$(session_record_path "$1")" 2>/dev/null
}

session_untouched() {
  [ ! -f "$(session_record_path "$1")" ]
}

# The whole store, unchanged: nothing written, nothing distilled. This is what
# an unattended run has to leave behind.
store_is_untouched() {
  [ "$(knowledge_count)" = "0" ] || return 1
  [ "$(session_records)" = "0" ] || return 1
  [ "$(mem_watermark_max)" = "0" ]
}

# The distill flow is a foreground flow: no subagent is spawned at any point.
no_subagent_spawned() {
  ! agent_launched 'distill'
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

# A read window landing mid-line is a boundary, not content: the marker belongs
# in the digest and never in a memory document.
no_truncation_marker_in_memory() {
  ! mem_has_text 'truncated at'
}

# Sessions the run read and kept nothing from — a correct, common outcome: the
# completion stamped the record and appended no capture.
empty_captures() {
  _n=0
  for _id in $(session_record_ids); do
    _r=$(session_record_path "$_id")
    grep -q '^distilled_at:' "$_r" || continue
    grep -q '^captures:' "$_r" && continue
    _n=$((_n + 1))
  done
  printf '%s\n' "$_n"
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

# --- gold sets: what a transcript should and should not produce -----------
#
# A labelled fixture carries fixtures/gold/<fixture>.tsv: one row per item a
# careful reader would keep (`gold`) or a lazy one would keep but must not
# (`decoy`, and `secret` for a credential that leaked into tool output). Each
# row's pattern is an ERE fingerprint that survives paraphrase. Scoring is
# lexical on purpose: no model in the verifier, and findability by identifier
# is what a good document has anyway.

EVAL_TOOLS=${IWE_EVAL_TOOLS:-/opt/iwe-evals}
EVAL_FIXTURES=${IWE_EVAL_FIXTURES:-$EVAL_TOOLS/fixtures}
EVAL_GOLD=${IWE_EVAL_GOLD:-$EVAL_FIXTURES/gold}
EVAL_TAB=$(printf '\t')

gold_file() {
  printf '%s/%s.tsv\n' "$EVAL_GOLD" "$1"
}

# id<TAB>pattern rows of one class. Asking for `decoy` includes the secret rows.
gold_rows() {
  awk -F'\t' -v class="$2" '
    /^[ \t]*#/ || NF < 3 { next }
    $2 == class || (class == "decoy" && $2 == "secret") { printf "%s\t%s\n", $1, $3 }
  ' "$(gold_file "$1")" 2>/dev/null
}

gold_pattern() {
  awk -F'\t' -v id="$2" '!/^[ \t]*#/ && NF >= 3 && $1 == id { print $3; exit }' \
    "$(gold_file "$1")" 2>/dev/null
}

# A unit is one proposal or one document, flattened to a single line so a
# pattern with `.*` can span what the author wrote as separate lines.
gold_unit_write() {
  mkdir -p "$1" 2>/dev/null
  tr '\n' ' ' >"$1/$2.txt"
}

# One unit per heading of a proposals file; text before the first heading is
# preamble and not a proposal. The instruction asks for `## ` headings, but the
# post-tool net normalizes any markdown written under the workspace — a
# gitignored .eval/ file included — and promotes `## ` to `# ` when the file
# has no title above them. So the unit level is whatever the file actually
# uses: the second level when a single title sits above second-level headings,
# the smallest level present otherwise.
gold_split_proposals() {
  rm -rf "$2"
  mkdir -p "$2"
  [ -f "$1" ] || return 0
  _level=$(awk '
    /^#+ / { match($0, /^#+/); l = RLENGTH; count[l] += 1; if (min == 0 || l < min) min = l }
    END { if (count[1] == 1 && count[2] > 0) print 2; else print min + 0 }
  ' "$1")
  [ "${_level:-0}" -gt 0 ] || return 0
  awk -v dir="$2" -v level="$_level" '
    /^#+ / {
      match($0, /^#+/)
      if (RLENGTH == level) { if (out != "") close(out); n += 1; out = sprintf("%s/p%03d.txt", dir, n) }
    }
    out != "" { printf "%s ", $0 >out }
  ' "$1"
}

# One unit per knowledge document in the store.
gold_dump_documents() {
  rm -rf "$1"
  mkdir -p "$1"
  mem_keys "$(knowledge_filter)" | while read -r _key; do
    [ -n "$_key" ] || continue
    mem_iwe retrieve -k "$_key" | gold_unit_write "$1" "$(printf '%s' "$_key" | tr '/' '_')"
  done
}

gold_unit_matches() {
  grep -qiE -- "$1" "$2" 2>/dev/null
}

# gold_eval <fixture> <dir>: count the units in dir against the gold set and
# cache the counts in dir/.stats for gold_stat. A unit is on gold when it
# matches at least one gold pattern; a decoy unit matches a decoy pattern and
# no gold pattern; a secret unit matches a secret pattern whatever else it
# says; a folded unit matches three or more distinct gold patterns.
gold_eval() {
  _fixture=$1
  _dir=$2
  mkdir -p "$_dir" 2>/dev/null
  gold_rows "$_fixture" gold | grep . >"$_dir/.gold"
  gold_rows "$_fixture" decoy | grep . >"$_dir/.decoy"
  gold_rows "$_fixture" secret | grep . >"$_dir/.secret"
  _gold_total=$(grep -c . "$_dir/.gold")
  _gold_hits=0
  while IFS="$EVAL_TAB" read -r _id _pattern; do
    for _u in "$_dir"/*.txt; do
      [ -f "$_u" ] || continue
      if gold_unit_matches "$_pattern" "$_u"; then
        _gold_hits=$((_gold_hits + 1))
        break
      fi
    done
  done <"$_dir/.gold"
  _units=0
  _on_gold=0
  _decoy_units=0
  _secret_units=0
  _folded=0
  for _u in "$_dir"/*.txt; do
    [ -f "$_u" ] || continue
    _units=$((_units + 1))
    _n=0
    while IFS="$EVAL_TAB" read -r _id _pattern; do
      gold_unit_matches "$_pattern" "$_u" && _n=$((_n + 1))
    done <"$_dir/.gold"
    [ "$_n" -eq 0 ] || _on_gold=$((_on_gold + 1))
    [ "$_n" -lt 3 ] || _folded=$((_folded + 1))
    if [ "$_n" -eq 0 ]; then
      while IFS="$EVAL_TAB" read -r _id _pattern; do
        if gold_unit_matches "$_pattern" "$_u"; then
          _decoy_units=$((_decoy_units + 1))
          break
        fi
      done <"$_dir/.decoy"
    fi
    while IFS="$EVAL_TAB" read -r _id _pattern; do
      if gold_unit_matches "$_pattern" "$_u"; then
        _secret_units=$((_secret_units + 1))
        break
      fi
    done <"$_dir/.secret"
  done
  {
    printf 'gold_total %s\n' "$_gold_total"
    printf 'gold_hits %s\n' "$_gold_hits"
    printf 'units %s\n' "$_units"
    printf 'units_on_gold %s\n' "$_on_gold"
    printf 'decoy_units %s\n' "$_decoy_units"
    printf 'secret_units %s\n' "$_secret_units"
    printf 'folded_units %s\n' "$_folded"
  } >"$_dir/.stats"
}

gold_stat() {
  eval_number "$(sed -n "s/^$2 //p" "$1/.stats" 2>/dev/null | head -1)"
  printf '\n'
}

gold_fraction() {
  awk -v n="$1" -v d="$2" 'BEGIN { if (d + 0 > 0) printf "%.4f", n / d; else printf "0" }'
}

# How many units cover one gold row: 1 is a fact written once, 2 is a duplicate.
gold_pattern_units() {
  _p=$(gold_pattern "$2" "$3")
  _c=0
  for _u in "$1"/*.txt; do
    [ -f "$_u" ] || continue
    gold_unit_matches "$_p" "$_u" && _c=$((_c + 1))
  done
  printf '%s\n' "$_c"
}

# The starter policy keys documents by a flat slug of the title.
knowledge_keys_are_flat_slugs() {
  [ "$(knowledge_count)" -gt 0 ] || return 1
  _bad=$(mem_keys "$(knowledge_filter)" | grep -vE '^[a-z0-9][a-z0-9-]*$')
  [ -z "$_bad" ]
}

# Tool calls the agent made, counted off its own transcripts only — the
# stream echoes them, and the model narrates them, so text search overcounts.
tool_calls_matching() {
  eval_number "$(eval_transcript_text | grep '"type":"tool_use"' | grep -c -- "$1" || :)"
  printf '\n'
}

tool_calls() {
  eval_number "$(eval_transcript_text | grep -c '"type":"tool_use"' || :)"
  printf '\n'
}

# --- the question bank ----------------------------------------------------
#
# Every labelled fixture carries fixtures/questions/<fixture>.tsv: one row per
# question — n, class, question, require, forbid, answer. A `gold` row depends
# on one gold item of the fixture, in gold order; a `stale` row is answerable
# from the repository and contradicted by a seeded memory document. `require`
# is a list of ERE patterns separated by `;;` that an answer must all match,
# `forbid` patterns it must not match; both deliberately avoid every word the
# question itself uses. tail-dense's set is the bank recall-bank asks.

bank_question_file() {
  printf '%s/questions/%s.tsv\n' "$EVAL_FIXTURES" "${1:-tail-dense}"
}

# bank_question_count <fixture> [class]
bank_question_count() {
  eval_number "$(awk -F'\t' -v class="${2:-}" '
    /^[ \t]*#/ || NF < 3 { next }
    class == "" || $2 == class { n += 1 }
    END { print n + 0 }' "$(bank_question_file "$1")" 2>/dev/null)"
  printf '\n'
}

# bank_question_field <fixture> <n> <column>
bank_question_field() {
  awk -F'\t' -v n="$2" -v col="$3" '
    /^[ \t]*#/ || NF < 3 { next }
    $1 == n { print $col; exit }' "$(bank_question_file "$1")" 2>/dev/null
}

# One pattern per line out of a `;;`-separated list. The list goes through
# stdin, not `-v`, because awk expands backslash escapes in `-v` assignments
# and a pattern like `\$line` would lose its backslash.
bank_patterns() {
  printf '%s\n' "$1" | awk '{ n = split($0, a, ";;"); for (i = 1; i <= n; i++) if (a[i] != "") print a[i] }'
}

bank_answer_text() {
  _line=$(grep -iE "^[[:space:]]*(\*\*)?(q|question)?[[:space:]]*$2[.):[:space:]]" "$1" 2>/dev/null | head -1)
  if [ -n "$_line" ]; then
    printf '%s\n' "$_line"
  else
    tr '\n' ' ' <"$1" 2>/dev/null
    printf '\n'
  fi
}

bank_text_has() {
  printf '%s' "$_bank_text" | grep -qiE -- "$1"
}

# bank_answer_ok <answers> <n> [fixture]: the answer to question n matches
# every required pattern and no forbidden one.
bank_answer_ok() {
  _fixture=${3:-tail-dense}
  _require=$(bank_question_field "$_fixture" "$2" 4)
  [ -n "$_require" ] || return 1
  _bank_text=$(bank_answer_text "$1" "$2")
  bank_patterns "$_require" | {
    while IFS= read -r _p; do
      bank_text_has "$_p" || exit 1
    done
  } || return 1
  bank_patterns "$(bank_question_field "$_fixture" "$2" 5)" | {
    while IFS= read -r _p; do
      ! bank_text_has "$_p" || exit 1
    done
  }
}

# bank_forbidden_hit <answers> <n> [fixture]: the answer says the thing the
# question's forbid patterns name.
bank_forbidden_hit() {
  _fixture=${3:-tail-dense}
  _forbid=$(bank_question_field "$_fixture" "$2" 5)
  [ -n "$_forbid" ] || return 1
  _bank_text=$(bank_answer_text "$1" "$2")
  bank_patterns "$_forbid" | {
    while IFS= read -r _p; do
      bank_text_has "$_p" && exit 0
    done
    exit 1
  }
}

# bank_hits <answers> <count> [fixture]: how many of questions 1..count are
# answered correctly.
bank_hits() {
  _h=0
  _i=1
  while [ "$_i" -le "$2" ]; do
    bank_answer_ok "$1" "$_i" "${3:-tail-dense}" && _h=$((_h + 1))
    _i=$((_i + 1))
  done
  printf '%s\n' "$_h"
}

# The stale document says 7; the script says 3. Repeating 7 is trusting memory
# over the repository in front of it.
bank_stale_repeated() {
  bank_forbidden_hit "$1" 9 tail-dense
}

# Documents whose *title* matches a pattern. A duplicate of a fact the store
# already held almost always names the same subject in its title, where a
# related document mentions it in passing in the body.
knowledge_titles_matching() {
  eval_number "$(mem_iwe find --filter "$(knowledge_filter)" --project 'title=$title' -f json --limit 0 |
    jq -r '.[].title // empty' 2>/dev/null | grep -ciE -- "$1" || :)"
  printf '\n'
}
