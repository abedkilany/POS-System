# Ventio Test Suite Notes

This test suite is intentionally split into fast model tests and lightweight AppStore business-flow tests.

## Commands

```bash
flutter analyze
flutter test -r expanded
```

## Coverage added

- Product validation, duplicate code/barcode protection, and soft delete sync payloads.
- Sale creation, sale validation, stock deduction, unit-cost capture, cancellation, and idempotent stock restoration.
- Purchase draft/receive/cancel flows, stock increases/reversals, and cost updates.
- Encrypted backup/decryption and wrong-password rejection.
- Backup export/import restoration.
- Remote sync epoch filtering and duplicate remote change id handling.
- Existing sync/inventory tests for totals, gross profit, conflict rules, and serialization.

## Why `widget_test.dart` is a placeholder

The full app widget starts local services/sync loops and can keep Flutter widget tests alive indefinitely. The app startup should be tested later with dependency injection/mocks. Until then, business logic is covered by deterministic unit/integration tests that finish quickly.
