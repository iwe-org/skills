#!/bin/sh
# Read the numbers out of a Harbor job directory: every reward component of
# every task, mean/min/max over the usable trials, and the delta for each
# task that names a `pair` in its task.toml.
#
#   sh evals/harbor/report.sh <harbor-jobs-dir> [task-filter]
#
# Trials stamped agent_api_error = 1 are dropped, not averaged in.
set -u

HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
jobs=${1:-}
only=${2:-}

if [ -z "$jobs" ] || [ ! -d "$jobs" ]; then
  printf 'report: usage: report.sh <harbor-jobs-dir> [task-filter]\n' >&2
  exit 2
fi
command -v jq >/dev/null 2>&1 || { printf 'report: jq is not on PATH\n' >&2; exit 2; }

work=$(mktemp -d "${TMPDIR:-/tmp}/iwe-report.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT INT TERM

names=$work/names
for dir in "$HERE"/tasks/*; do
  [ -d "$dir" ] && printf '%s\n' "${dir##*/}"
done >"$names"

# task<TAB>component<TAB>value, one row per component of every usable trial.
# A trial belongs to the longest task name its path contains, so recall-bank
# never swallows recall-bank-baseline.
rows=$work/rows
find "$jobs" -name reward.json 2>/dev/null | while read -r file; do
  task=$(awk -v path="$file" 'index(path, $0) && length($0) > length(best) { best = $0 } END { print best }' "$names")
  [ -n "$task" ] || continue
  [ -z "$only" ] || [ "$task" = "$only" ] || continue
  if [ "$(jq -r '.agent_api_error // 0' "$file" 2>/dev/null)" = "1" ]; then
    printf '%s\tagent_api_error_trials\t1\n' "$task"
    continue
  fi
  jq -r --arg task "$task" 'to_entries[] | select(.value | type == "number") | "\($task)\t\(.key)\t\(.value)"' "$file" 2>/dev/null
done | sort >"$rows"

[ -s "$rows" ] || { printf 'report: no reward.json under %s\n' "$jobs"; exit 1; }

printf '%-24s %-28s %8s %8s %8s %4s\n' task component mean min max n
awk -F'\t' '
  {
    key = $1 "\t" $2
    sum[key] += $3; n[key] += 1
    if (!(key in min) || $3 < min[key]) min[key] = $3
    if (!(key in max) || $3 > max[key]) max[key] = $3
    if (!(key in seen)) { order[++k] = key; seen[key] = 1 }
  }
  END {
    for (i = 1; i <= k; i++) {
      key = order[i]; split(key, parts, "\t")
      if (parts[1] != last) { if (last != "") print ""; last = parts[1] }
      printf "%-24s %-28s %8.4f %8.4f %8.4f %4d\n", parts[1], parts[2], sum[key] / n[key], min[key], max[key], n[key]
    }
  }
' "$rows"

pairs=0
for dir in "$HERE"/tasks/*; do
  toml=$dir/task.toml
  [ -f "$toml" ] || continue
  task=${dir##*/}
  pair=$(sed -n 's/^pair = "iwe\/\([^"]*\)".*/\1/p' "$toml" | head -1)
  [ -n "$pair" ] || continue
  [ "$task" \< "$pair" ] || continue
  grep -q "^$task	" "$rows" && grep -q "^$pair	" "$rows" || continue
  [ "$pairs" -gt 0 ] || printf '\n%-24s %-28s %8s %8s %8s\n' pair component "$task" "$pair" delta
  pairs=$((pairs + 1))
  awk -F'\t' -v a="$task" -v b="$pair" '
    $1 == a || $1 == b { sum[$1 "\t" $2] += $3; n[$1 "\t" $2] += 1; comps[$2] = 1 }
    END {
      for (c in comps) {
        ka = a "\t" c; kb = b "\t" c
        if ((ka in n) && (kb in n)) {
          ma = sum[ka] / n[ka]; mb = sum[kb] / n[kb]
          printf "%-24s %-28s %8.4f %8.4f %+8.4f\n", a " vs " b, c, ma, mb, ma - mb
        }
      }
    }
  ' "$rows" | sort
done
[ "$pairs" -gt 0 ] || printf '\nno paired tasks with results on both halves\n'
