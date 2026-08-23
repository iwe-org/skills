#!/bin/sh
set -eu

src=${1:-}
out=${2:-}

if [ -z "$src" ] || [ -z "$out" ]; then
  printf 'usage: render-settings.sh <hooks.json> <settings.json>\n' >&2
  exit 2
fi
[ -f "$src" ] || {
  printf 'render-settings: %s is missing\n' "$src" >&2
  exit 2
}

mkdir -p "$(dirname -- "$out")"
cp "$src" "$out"
