#!/usr/bin/env bash
set -euo pipefail

flutter pub get
flutter analyze
flutter test -r expanded --coverage --concurrency=1
bash tool/check_coverage.sh

cat <<'MSG'
Common quality gate passed.
Desktop integration tests remain platform-specific and must also pass on the Windows release machine:
  flutter test integration_test -d windows -r expanded
Optional golden baseline update:
  flutter test test/golden_smoke_test.dart --dart-define=RUN_GOLDENS=true --update-goldens
MSG
