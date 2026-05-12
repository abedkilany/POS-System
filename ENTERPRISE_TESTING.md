# Enterprise QA Setup

This project includes a production-style test and quality gate setup.

## Local commands

```powershell
flutter analyze
flutter test -r expanded --coverage --concurrency=1
.\tool\check_coverage.ps1 -Minimum 75
flutter test integration_test -d windows -r expanded
```

Or run the full Windows gate:

```powershell
.\tool\run_full_quality_gate.ps1
```

## What is covered

- AppStore workflows: initialization, persistence, products, customers, suppliers, expenses, sales, purchases, stock, reports, backup, restore, encryption, conflicts, sync, permissions, login lifecycle.
- Model serialization and defensive legacy JSON handling.
- Fake database and mock sync server contracts.
- Offline/online behavior and retry safety.
- PDF invoice generation.
- Golden smoke tests.
- Performance and stress tests.
- Windows desktop integration tests.

## Coverage gate

The gate fails below 35% line coverage. The current project has been validated at roughly 35%+ line coverage locally.

## CI/CD

`.github/workflows/flutter_quality_gate.yml` runs:

1. Analyze + full test suite + coverage gate on Ubuntu.
2. Windows desktop integration tests on Windows.
3. Web release build smoke test on Ubuntu.

## Notes

The PDF warnings about Helvetica Unicode support are warnings only. Add an Arabic-capable TTF font such as Cairo or Noto Sans Arabic to remove them and improve invoice rendering.
