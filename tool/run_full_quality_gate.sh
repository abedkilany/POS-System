#!/usr/bin/env bash
set -euo pipefail

flutter pub get
flutter analyze
flutter test -r expanded --coverage --concurrency=1
bash tool/check_coverage.sh 75

if command -v flutter >/dev/null 2>&1; then
  echo "Desktop integration tests are run on Windows by CI/local PowerShell."
fi

echo "Quality gate passed."
echo "Optional golden baseline update:"
echo "flutter test test/golden_smoke_test.dart --dart-define=RUN_GOLDENS=true --update-goldens"
