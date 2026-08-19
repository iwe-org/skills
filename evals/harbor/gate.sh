#!/bin/sh
set -u

HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
jobs=${1:-}
floors=${2:-$HERE/floors.txt}

if [ -z "$jobs" ] || [ ! -d "$jobs" ]; then
  printf 'gate: usage: gate.sh <harbor-jobs-dir> [floors-file]\n' >&2
  exit 2
fi
[ -f "$floors" ] || {
  printf 'gate: %s is missing\n' "$floors" >&2
  exit 2
}

entries=$(grep -v '^[ \t]*#' "$floors" | grep -c '[^ \t]')
if [ "$entries" -eq 0 ]; then
  printf 'gate: no floors configured yet, nothing to enforce\n'
  printf 'gate: set them in %s after a week of stable runs, never from one run\n' "$floors"
  exit 0
fi

breached=0

while read -r task floor; do
  case ${task:-} in
    ''|'#'*) continue ;;
  esac
  trials=$(find "$jobs" -name 'reward.json' -path "*$task*" 2>/dev/null |
    while read -r file; do
      reward=$(sed -n 's/.*"reward":[ ]*\([0-9.]*\).*/\1/p' "$file")
      [ -n "$reward" ] || continue
      poisoned=$(sed -n 's/.*"agent_api_error":[ ]*\([0-9]*\).*/\1/p' "$file")
      printf '%s %s\n' "${poisoned:-0}" "$reward"
    done)
  skipped=$(printf '%s\n' "$trials" | grep -c '^1 ')
  rewards=$(printf '%s\n' "$trials" | sed -n 's/^0 //p')
  if [ -z "$rewards" ]; then
    if [ "$skipped" -gt 0 ]; then
      printf 'FAIL %-24s no usable results, all %s trial(s) hit agent api errors\n' "$task" "$skipped"
    else
      printf 'FAIL %-24s no results under %s\n' "$task" "$jobs"
    fi
    breached=$((breached + 1))
    continue
  fi
  mean=$(printf '%s\n' "$rewards" | awk '{ sum += $1; n += 1 } END { printf "%.4f", sum / n }')
  verdict=$(awk -v m="$mean" -v f="$floor" 'BEGIN { print (m + 0 >= f + 0) ? "ok" : "FAIL" }')
  count=$(printf '%s\n' "$rewards" | grep -c .)
  suffix=''
  [ "$skipped" -eq 0 ] || suffix=$(printf ', %s poisoned trial(s) skipped' "$skipped")
  printf '%-4s %-24s mean %s over %s trial(s), floor %s%s\n' "$verdict" "$task" "$mean" "$count" "$floor" "$suffix"
  [ "$verdict" = "ok" ] || breached=$((breached + 1))
done <"$floors"

[ "$breached" -eq 0 ] || printf '\ngate: %s task(s) under their floor\n' "$breached"
[ "$breached" -eq 0 ]
