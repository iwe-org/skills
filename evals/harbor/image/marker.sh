#!/bin/sh
set -u

dir=${IWE_EVAL_MARKER_DIR:-${IWE_EVAL_APP:-/app}/.eval/hooks}
event=${1:-unknown}

mkdir -p "$dir" 2>/dev/null || exit 0
cat >"$dir/$event-$$.json" 2>/dev/null
exit 0
