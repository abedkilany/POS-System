#!/usr/bin/env bash
set -euo pipefail

MINIMUM="${1:-}"
LCOV_PATH="${2:-coverage/lcov.info}"
ARGS=(--lcov "$LCOV_PATH" --config tool/quality_gate_config.json)
if [[ -n "$MINIMUM" ]]; then
  ARGS+=(--minimum "$MINIMUM")
fi

dart run tool/check_coverage.dart "${ARGS[@]}"
