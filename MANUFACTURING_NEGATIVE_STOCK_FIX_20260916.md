# Ventio — Manufacturing Negative Stock Fix

Date: 2026-09-16
Baseline: the user-supplied archive `f4ffd42d-44a9-491e-8a82-e1b03ee161e2.zip` only. Older source archives were not used as the patch baseline.

## Behavior
- Manufacturing now respects `StoreProfile.allowNegativeStock`.
- If disabled, manufacturing still requires physical Unified Batch stock.
- If enabled, real batches are consumed first; only the shortage becomes a tracked `inventory_stock_deficits` allocation.
- The deficit uses a provisional unit cost resolved from the latest real Batch, then current `product_costs` average/last cost, then Product reference cost.
- A missing/zero reference cost blocks completion with a clear localized error instead of reaching the generic `Manufacturing cost snapshot is invalid` guard.
- Later incoming stock settles the deficit through the existing deficit settlement path. For manufacturing/non-sale deficits, actual-vs-provisional differences remain auditable through `inventory_deficit_cost_variance`.
- Sync accepts deficit lineage for `manufacturing_consume` and its reversal, while transfers and manufacturing outputs are still forbidden from using virtual deficit batches.

## Regression coverage added
- A Phase 5 test completes manufacturing with zero physical raw stock, negative stock enabled, and a valid reference cost; it verifies negative warehouse quantity, open deficit, provisional cost, finished output, and deficit batch movement identity.

## Safety note
This intentionally uses a provisional-cost + later variance policy. It does not silently rewrite historical finished-goods batch cost when the later purchase cost differs.
