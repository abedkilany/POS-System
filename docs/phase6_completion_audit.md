# Phase 6 completion audit

This build closes the remaining Phase 6 acceptance gaps identified in the final review.

## Closed gaps

- Cumulative partial sale returns are validated against prior active credit notes, preventing the same sold quantity from being returned more than once.
- The original sale lines remain intact after a partial return; the sale persists `Partially Returned` consistently while credit notes hold immutable returned quantities.
- Partial-return items preserve the exact FEFO batch allocation slice and FIFO cost-layer consumption slice for the returned units.
- Repeated partial returns use unique stock movement operation/idempotency keys while retaining links to the original sale movement.
- Cash-operation and cash-transfer reversals persist reversal timestamp, reason, actor name, and actor user id.
- Cash History passes the actual active user identity to the reversal service rather than only the current role.
- Upgrade migrations add the Phase 6 reversal-audit columns to existing Phase 5 databases.
- Cash reference reversal retries are idempotent and do not overwrite the first reversal audit metadata.
- Credit-note return history is loaded from the persisted SQLite scalar mirror so cumulative-return validation survives application restart.

## Regression coverage added

- Repeated partial returns cannot exceed the original sold quantity.
- `Partially Returned` remains persisted while original invoice line quantities remain intact.
- Consecutive partial returns preserve FEFO batch slices and FIFO cost-layer slices.
- Cash-operation and cash-transfer reversal audit fields are asserted.
- Repeating a reversal produces no second reversal and preserves the first audit metadata.

## Validation environment

The work environment does not provide the Flutter or Dart SDK, so `flutter analyze` and `flutter test` could not be executed here. Structural checks and archive integrity checks were performed; the Flutter quality gate must still be run in a Flutter-enabled environment.
