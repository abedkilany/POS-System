# Ventio Inventory Fixes — 2026-09-07

This build applies the inventory corrections identified during the Unified Batch review.

## Changes

- Expiry tracking now has one canonical contract: when expiry tracking is enabled, expiration date entry is always required.
- Legacy product rows with `expiry_tracking_enabled = 1` and `expiry_entry_required = 0` are self-healed during SQLite initialization.
- Product/sync persistence normalizes the same expiry rule to prevent the invalid combination from returning.
- The misleading `Expiry Date Required` toggle was removed from the product editor.
- Batch lifecycle status is refreshed automatically:
  - `active -> depleted` when physical quantity reaches zero across warehouses.
  - `depleted -> active` when stock is restored or moved into another warehouse.
  - blocked/disposed statuses are not overwritten by automatic lifecycle refresh.
  - synthetic negative-stock deficit batches keep their separate lifecycle.
- Synced batch movements also derive the same lifecycle state, keeping devices consistent.
- The inventory batch screen now uses the complete Unified Batch ledger rather than an expiry-only view.
- Non-expiry batches are visible with warehouse, quantity, status, source and received date.
- `depleted` batches are visible/filterable.
- Expiry disposal remains limited to dated batches; batch stock count/correction can operate on any stock-tracked product.
- CSV export now exports the Unified Batch inventory ledger.

## Regression coverage added

- Expiry-tracked products normalize `expiryEntryRequired` to true.
- A fully consumed batch becomes `depleted` and returns to `active` after restoration.
- A full warehouse transfer preserves an `active` batch when stock still exists at the destination.

## Validation notes

- Phase 7 transaction-integrity static verification: 14/14 PASS.
- Phase 9 and Phase 12 static verifiers retain the same pre-existing schema-version expectation failure as the source build (39/40 and 30/31 respectively); this patch does not change the production schema version.
- Flutter/Dart SDK is not installed in the review environment, so the Flutter test suite could not be executed here.
- The supplied source archive does not contain `assets/translations/`, so the Phase 10 verifier cannot run from this archive; this is also a property of the supplied source build.
