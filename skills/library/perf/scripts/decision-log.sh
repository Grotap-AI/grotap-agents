#!/usr/bin/env bash
# Origin: pstack v0.15.5 skills/show-me-your-work/scripts/log.sh
# (Lauren Tan, MIT), https://github.com/cursor/plugins/tree/fadd23794c0075468eb8964b0fd93e06e09486ad/pstack
# Adapted for the Grotap perf skill. Append-only TSV. Strips tabs and
# prefixes spreadsheet formulas so evidence cannot become a formula.
# Usage: decision-log.sh <logfile> <phase> <decision> <why> <evidence> <result>
set -euo pipefail

if [[ "$#" -ne 6 ]]; then
  printf 'usage: decision-log.sh <logfile> <phase> <decision> <why> <evidence> <result>\n' >&2
  exit 1
fi

logfile="$1"
shift

logdir="$(dirname "$logfile")"
if [[ -n "$logdir" && "$logdir" != "." && ! -d "$logdir" ]]; then
  mkdir -p "$logdir"
fi

if [[ ! -s "$logfile" ]]; then
  printf 'ts\tphase\tdecision\twhy\tevidence\tresult\n' >> "$logfile"
fi

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
clean() {
  local v
  v="$(printf '%s' "$1" | tr '\t\n\r' '   ')"
  case "$v" in
    =*|+*|-*|@*) printf "'%s" "$v" ;;
    *) printf '%s' "$v" ;;
  esac
}

printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$ts" "$(clean "$1")" "$(clean "$2")" "$(clean "$3")" "$(clean "$4")" "$(clean "$5")" \
  >> "$logfile"
