# Ventio testing guide

## Current layers

This project now has a production-oriented Flutter testing setup:

- Unit/model business logic tests
- JSON serialization and defensive parsing tests
- Fake local database contract tests
- Mock cloud sync server tests
- Offline/online recovery tests
- Invoice PDF generation tests
- Performance smoke tests
- Widget smoke tests
- Optional golden visual regression smoke tests
- Integration navigation tests for wide and compact layouts
- CI quality gate for analyze, unit/widget tests, coverage, and integration tests

## Local commands

```powershell
flutter pub get
flutter analyze
flutter test -r expanded --coverage --concurrency=1
flutter test integration_test -r expanded
```

Or run the full Windows gate:

```powershell
.\tool\run_full_quality_gate.ps1
```

On macOS/Linux:

```bash
./tool/run_full_quality_gate.sh
```

## Optional golden tests

Golden tests are disabled by default so normal `flutter test` stays stable on every machine.
To create or update baselines:

```powershell
flutter test test/golden_smoke_test.dart --dart-define=RUN_GOLDENS=true --update-goldens
```

Then review the generated files under `test/goldens/` and commit them.
After baselines exist, run:

```powershell
flutter test test/golden_smoke_test.dart --dart-define=RUN_GOLDENS=true
```

## CI

The GitHub Actions workflow is located at:

```text
.github/workflows/flutter_quality_gate.yml
```

It runs:

1. `flutter pub get`
2. `flutter analyze`
3. `flutter test -r expanded --coverage --concurrency=1`
4. `flutter test integration_test -r expanded`
5. Uploads `coverage/lcov.info` as an artifact

## What is intentionally not mocked

The tests avoid hitting real cloud or LAN infrastructure. Network behavior is represented with mock/fake boundaries so the suite is deterministic and fast.
