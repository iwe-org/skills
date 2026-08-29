#!/bin/sh
# Draft a gold set from a session the user has distilled by hand: one `gold`
# row per document the session record's captures list, one `decoy` row per
# title the ledger says was turned down, and the transcript scrubbed into
# fixture form.
#
#   sh evals/quality/mint-gold.sh <session-id> [out-dir]
#
# Run from the workspace whose .iwe/claude/sessions/ holds the record. The patterns
# it writes are the titles, regex-escaped: edit them down to fingerprints — an
# identifier, an error string — before the file means anything, and move the
# pair into evals/harbor/image/fixtures/{,gold/} under a name of your own.
set -u

session=${1:-}
out=${2:-${TMPDIR:-/tmp}/iwe-gold}

[ -n "$session" ] || { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
for tool in iwe jq; do
  command -v "$tool" >/dev/null 2>&1 || { printf 'mint-gold: %s is not on PATH\n' "$tool" >&2; exit 2; }
done

record_file=.iwe/claude/sessions/$session.yaml
[ -f "$record_file" ] || {
  printf 'mint-gold: no session record %s here\n' "$record_file" >&2
  exit 1
}
record=$(cat "$record_file")

# The two lists a record carries, in the shape serde_yaml writes them: the keys
# under every capture's `wrote:`, and the titles under `rejected:`.
record_list() {
  printf '%s\n' "$record" | awk -v want="$1" '
    /^[^ -]/ { top = $1; sub(/:$/, "", top); inner = "" }
    /^- / && top == "captures" { inner = "" }
    /^  [^ -]/ && top == "captures" { inner = $1; sub(/:$/, "", inner) }
    want == "rejected" && top == "rejected" && /^- / { item = substr($0, 3) }
    want == "wrote" && top == "captures" && inner == "wrote" && /^  - / { item = substr($0, 5) }
    item != "" { gsub(/^["'"'"']|["'"'"']$/, "", item); print item; item = "" }
  '
}

title_of() {
  iwe find --filter "{ \$key: \"$1\" }" --project 'title=$title' -f json --limit 1 2>/dev/null |
    jq -r '.[0].title // empty' 2>/dev/null
}

transcript=$(printf '%s\n' "$record" | sed -n 's/^transcript: *//p' | head -1)
[ -f "$transcript" ] || {
  printf 'mint-gold: the record names transcript %s, which is not here\n' "${transcript:-<none>}" >&2
  exit 1
}

escape() {
  printf '%s' "$1" | sed 's/[][\\.*^$+?(){}|/]/\\&/g'
}

mkdir -p "$out/gold"
tsv=$out/gold/$session.tsv
{
  printf '# Draft gold set for %s, minted %s. Patterns are titles: edit them down to fingerprints.\n' \
    "$session" "$(date '+%Y-%m-%d')"
  printf '# id\tclass\tpattern\tnote\n'
  n=0
  record_list wrote | while read -r key; do
    [ -n "$key" ] || continue
    n=$((n + 1))
    title=$(title_of "$key")
    printf 'G%s\tgold\t%s\t%s\n' "$n" "$(escape "${title:-$key}")" "$key"
  done
  n=0
  record_list rejected | while read -r title; do
    [ -n "$title" ] || continue
    n=$((n + 1))
    printf 'D%s\tdecoy\t%s\tturned down in the session\n' "$n" "$(escape "$title")"
  done
} >"$tsv"

cwd=$(head -1 "$transcript" | jq -r '.cwd // empty' 2>/dev/null)
fixture=$out/$session.jsonl
if [ -n "$cwd" ]; then
  sed -e "s|$cwd|PROJECT_CWD|g" -e "s|$session|SESSION_ID|g" "$transcript" >"$fixture"
else
  sed -e "s|$session|SESSION_ID|g" "$transcript" >"$fixture"
fi

gold=$(grep -c '	gold	' "$tsv")
decoys=$(grep -c '	decoy	' "$tsv")
printf 'wrote %s (%s gold, %s decoy) and %s (%s lines)\n' "$tsv" "$gold" "$decoys" "$fixture" "$(grep -c . "$fixture")"
printf 'next: replace each title pattern with a fingerprint, read the transcript for secrets and paths the scrub missed,\n'
printf '      then copy the pair under evals/harbor/image/fixtures/ and run: sh evals/quality/propose.sh -f <name> --dry-run\n'
