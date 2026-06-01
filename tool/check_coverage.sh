#!/usr/bin/env bash
set -euo pipefail
MINIMUM="${1:-75}"
LCOV_PATH="${2:-coverage/lcov.info}"

if [[ ! -f "$LCOV_PATH" ]]; then
  echo "Coverage file not found: $LCOV_PATH. Run: flutter test --coverage" >&2
  exit 1
fi

read -r HIT FOUND < <(awk -F: '/^LH:/ {hit += $2} /^LF:/ {found += $2} END {print hit+0, found+0}' "$LCOV_PATH")
if [[ "$FOUND" == "0" ]]; then
  echo "No coverable lines found in $LCOV_PATH" >&2
  exit 1
fi
PERCENT=$(awk -v h="$HIT" -v f="$FOUND" 'BEGIN { printf "%.2f", (h/f)*100 }')
echo "Coverage: ${PERCENT}% (${HIT} / ${FOUND} lines). Minimum: ${MINIMUM}%"
awk -v p="$PERCENT" -v m="$MINIMUM" 'BEGIN { exit !(p+0 >= m+0) }' || {
  echo "Coverage gate failed: ${PERCENT}% is below ${MINIMUM}%" >&2
  exit 1
}
