# Ventio — Manufacturing Zero-Cost Batch Repair

Date: 2026-09-16
Baseline: latest AnalyzeFixed manufacturing-negative-stock source package.
Database used for diagnosis: `ventio(20260916-081553).zip`.

## Production regression reproduced from the supplied database

Raw product: `كاجو مشوي` (`product_1788765641711018`)

- Pending manufacturing order: `MFG-1105619325`
- Output: `ارشيز كاجو مشوي 80 غ`
- Quantity: `6`
- BOM raw requirement: `0.08 kg` per unit
- Total raw requirement: `0.48 kg`
- Physical raw stock in Main Warehouse: `0.50 kg`
- Active physical Batch: `1789461070831077-product_1788765641711018-count-batch`
- Batch source: `inventory_count`
- Batch carrying cost: `0.00`
- Prior outbound movements from that Batch: `0`
- Product Master reference cost after user edit: `11.50 USD/kg`
- Latest positive-cost historical Unified Batch for the same raw product: `12.763596004439512 USD/kg`

The failure therefore was not a negative-stock shortage. The required 0.48 kg existed physically, but the only allocatable physical Batch had a zero unit cost. Manufacturing correctly refused to produce a positive-cost finished good from a zero-cost raw Batch snapshot.

## Root cause

A previous inventory-count overage created a new physical Unified Batch while no usable current cost snapshot was available. The count Batch was therefore persisted at `unit_cost = 0`. Editing Product Master later changes the user-maintained reference cost, but intentionally does not rewrite historical Batch carrying cost. Consequently normal Unified Batch allocation continued to return the zero-cost physical Batch.

## Fix

1. Inventory-count opening/overage costing now also consults the centralized positive reference-cost resolver, including historical positive Unified Batch cost, before it can create another zero-cost count Batch.
2. Manufacturing preflights the exact physical Batches that would be consumed.
3. An untouched zero-cost `inventory_count` Batch can be repaired automatically inside the same SQLite transaction before manufacturing:
   - no historical outbound use is allowed for automatic repair;
   - a positive source-movement cost is preferred when it proves GL was already valued;
   - otherwise reference cost resolution is: latest real positive Batch -> ProductCost average/last -> Product Master `usdCost/cost`;
   - the Batch unit cost is updated atomically;
   - when the original count carried zero value, a dedicated `inventory_batch_revaluation` journal adds the matching inventory asset value against inventory-count gain before manufacturing transfers raw value to finished goods.
4. Zero-cost physical Batches from other source types are still fail-closed instead of being silently revalued, because a genuine zero-cost purchase/free item can be valid and must not be guessed.
5. If a zero-cost count Batch was already consumed historically, automatic repair is blocked because changing only the remaining stock would leave past COGS/manufacturing lineage inconsistent.

## Effect on the supplied `كاجو مشوي` case

The current zero-cost Batch is safe for automatic repair because it has no prior outbound movement. The resolver finds the historical real Batch cost `12.763596004439512 USD/kg` before the editable Product Master fallback. Therefore:

- Revaluation of current 0.50 kg: about `6.381798 USD` (journal rounded by the accounting money profile).
- Manufacturing consumption of 0.48 kg: about `6.126526 USD`.
- Remaining raw stock: 0.02 kg, carrying value about `0.255272 USD`.

The user-entered 11.50 Product Master cost remains a reference cost; it is not used to overwrite a known historical Batch cost. It becomes the fallback when no positive Batch/ProductCost history exists.

## Verification in this environment

Static project verifiers after the change:

- Phase 7 Transaction Integrity: 14/14 PASS
- Phase 8 Golden Financial: 26/26 PASS
- Phase 9 Traceability: 40/40 PASS
- Phase 10 Health / Disaster Recovery: 46/46 PASS
- Phase 12 Structural Refactor: 31/31 PASS
- Unified Batch / Negative Stock hardening: 34/34 PASS
- Cost source unification: 11/11 PASS
- Translation JSON parse/parity: PASS (covered by Phase 10)
- Custom delimiter/string-aware structural scan on modified Dart files: PASS

Flutter/Dart SDK is not installed in this environment, so run `flutter analyze` and the relevant Flutter tests in the normal development environment before production deployment.
