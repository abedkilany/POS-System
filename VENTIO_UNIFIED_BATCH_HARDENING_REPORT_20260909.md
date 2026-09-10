# Ventio — Unified Batch / Negative Stock Hardening

Date: 2026-09-09
Baseline: latest source supplied as `Ventio_FIXED_UnifiedBatch_Printing_20260908(1).zip`
Scope: application source only. No user database was opened, changed, migrated, repaired, or included in the deliverables.

## Implemented fixes

### 1. Phase 4 cutover is now fail-closed
- Added explicit Phase 4 states: `pending`, `completed`, `blocked`.
- A failed closure is recorded as `blocked` and no longer marks the inventory costing migration as completed.
- New local and synchronized stock writes are rejected while Phase 4 is blocked.
- Once Phase 4 is completed, stock-tracked movements require a batch identity.
- Accounting inventory valuation is blocked while Phase 4 is blocked, preventing a partial Batch valuation from being presented as authoritative.
- Phase 4 now rejects virtual deficit batches that incorrectly carry positive physical batch balances.

### 2. Negative-stock deficit integrity
- Physical allocation queries explicitly exclude both `source_type = inventory_deficit` and `batch_id` values beginning with `deficit:`.
- Unified Batch invariants reject positive physical balances attached to virtual deficit batches.
- Out-of-order synchronized positive deficit reversals fail closed instead of becoming fake physical stock.
- Incoming physical batches that already settled an earlier deficit cannot be reversed as normal inbound stock until the dependency is reversed.

### 3. Reverse/Edit hardening
- Added a central `reverseUnifiedMovementEffectInTransaction` path.
- Negative outbound movements are restored through the deficit-aware restore path.
- Positive inbound movements are removed through the guarded inbound path.
- Inventory count reversal, expiry adjustment reversal, stock adjustment edit, sale-return edit, warehouse-transfer edit, and manufacturing reversal were moved away from direct balance manipulation to the central reverse path.
- For a returned negative-stock deficit, editing is deliberately fail-closed when a safe inverse cannot be proven. This avoids corrupting deficit settlement lineage.

### 4. Warehouse transfers
- Warehouse transfer is treated as physical lineage: source stock must exist in real batches.
- Transfer allocation no longer creates a virtual deficit in the source and then turns it into positive stock at the destination.
- Synchronized old-client transfer movements using deficit batch ids are rejected.

### 5. Manufacturing
- Raw materials must exist in physical Unified Batches before manufacturing can complete.
- Manufacturing no longer converts provisional negative-stock deficit cost into a finished batch as though it were final cost.
- Manufacturing reversal uses the centralized Unified Batch reverse path.
- Synchronized old-client manufacturing movements using deficit batch ids are rejected.

### 6. BOM estimated cost
- BOM estimated material cost now reads Unified Batch carrying costs rather than relying only on Product Master cost.
- When a raw-material warehouse is selected, the estimator previews actual batch ordering used by Unified Batch allocation.
- Deficit batches are excluded from the estimate.
- BOM list display, manufacturing start dialog, and BOM printing use the estimated Batch cost snapshot.

### 7. Legacy cutover cost safety
- Zero-cost legacy batch fallback is now scoped to batches that actually have a balance in the warehouse currently being cut over. This prevents one warehouse's opening cost from being applied blindly to unrelated zero-cost legacy batches in another warehouse.

### 8. User-facing batch errors
- Added Arabic, English, and French translations for previously missing Unified Batch / cutover / negative-stock error keys so the UI does not expose raw keys such as `error_batch_cutover_mismatch`.

## Intentional policy after this hardening

The store-wide `allowNegativeStock` feature remains valid for sales and other deficit-aware outbound flows.

For safety, **warehouse transfer and manufacturing now require physical Batch stock**. Full negative transfer/manufacturing support would require downstream provisional-cost lineage and revaluation propagation. Until that larger feature exists, Ventio fails closed instead of creating incorrect inventory valuation or COGS.

A sale return against a deficit allocation can still restore the original negative-stock sale. However, editing/reversing such a return is blocked when the system cannot prove a safe inverse of the deficit-settlement chain. This is an integrity guard, not silent data mutation.

## Verification performed

- Phase 7 Transaction Integrity: **14/14 PASS**
- Phase 8 Golden Financial: **26/26 PASS**
- Phase 9 Traceability: **40/40 PASS**
- Phase 10 Health / Disaster Recovery: **46/46 PASS**
- Phase 12 Structural Refactor: **31/31 PASS**
- Unified Batch / Negative Stock hardening verifier: **34/34 PASS**
- Translation parity: **2774 keys in EN/AR/FR — PASS**
- `git diff --check` with CRLF-aware whitespace policy: **PASS**
- Database files in source work tree: **0**
- Font files in deliverables: **0**

## Toolchain limitation

Flutter and Dart SDKs are not installed in the execution environment, so `flutter analyze`, `flutter test`, and a Windows EXE build could not be run here. The included verification is static/project-specific validation. A final developer-side gate should run:

1. `flutter pub get`
2. `flutter analyze`
3. `flutter test`
4. Windows build and smoke test
5. Test negative-stock sale -> receipt settlement -> sale return
6. Test transfer with insufficient physical stock is rejected
7. Test manufacturing with insufficient physical raw batch stock is rejected
8. Test BOM cost estimate against a known Batch cost
9. Test a deliberately blocked Phase 4 state cannot post stock or show authoritative inventory valuation

## Database note

No database is included. Use the user's newer database only after building/testing this application source. The application may run its normal schema/startup logic when launched; this package itself does not alter any database file.
