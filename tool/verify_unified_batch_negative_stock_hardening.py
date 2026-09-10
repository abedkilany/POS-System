#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def read(path: str) -> str:
    return (ROOT / path).read_text(encoding='utf-8')

BATCH = read('lib/core/services/batch_inventory_service.dart')
STOCK = read('lib/core/services/stock_transaction_service.dart')
PHASE4 = read('lib/core/services/unified_batch_phase4_closure_service.dart')
STARTUP = read('lib/data/app_store_startup_migrations.dart')
SYNC = read('lib/data/app_store_sync_apply.dart')
SQLITE_SYNC = read('lib/core/services/sqlite_sync_state_service.dart')
MFG = read('lib/data/app_store_manufacturing.dart')
INV = read('lib/data/app_store_inventory.dart')
RETURNS = read('lib/data/app_store_sales_returns.dart')
TRANSFER = read('lib/data/app_store_warehouse_cash.dart')
PURCHASES = read('lib/data/app_store_purchases.dart')
FORWARD = read('lib/data/app_store_forwarding_api.dart')
UI = read('lib/features/inventory/manufacturing_page.dart')
ACCOUNTING = read('lib/core/services/accounting_service.dart')

checks: list[tuple[str, bool]] = []

def check(name: str, condition: bool) -> None:
    checks.append((name, bool(condition)))

check('allocation excludes virtual deficit batches', BATCH.count("b.source_type <> 'inventory_deficit'") >= 3 and BATCH.count("b.id NOT LIKE 'deficit:%'") >= 3)
check('physical stock preflight exists', 'requirePhysicalUnifiedStockInTransaction' in BATCH)
check('allocation preview follows batch ordering', 'previewUnifiedAllocationInTransaction' in BATCH and 'ORDER BY $ordering' in BATCH)
check('warehouse transfer requires physical batches', "operation: 'warehouse transfer'" in BATCH)
check('warehouse transfer disables deficit allocation', 'transferUnifiedInTransaction' in BATCH and 'allowNegativeStock: false' in BATCH)
check('central reverse helper exists', 'reverseUnifiedMovementEffectInTransaction' in BATCH)
check('central reverse restores outbound deficit-aware', 'await restoreUnifiedInTransaction(' in BATCH)
check('central reverse removes inbound safely', 'await removeUnifiedInboundInTransaction(' in BATCH)
check('virtual deficit balances are rejected by invariant', 'virtual_deficit_balance' in BATCH and "b.id LIKE 'deficit:%'" in BATCH)
check('inbound reverse blocks settled deficits', 'error_inbound_batch_settled_deficit' in BATCH and 'inventory_deficit_settlements' in BATCH)
check('manufacturing requires physical raw batches', "operation: 'manufacturing'" in MFG and 'requirePhysicalUnifiedStockInTransaction' in MFG)
check('manufacturing disables deficit allocation', 'allowNegativeStock: false' in MFG)
check('manufacturing reversal uses central batch reverse', 'reverseUnifiedMovementEffectInTransaction' in MFG)
check('inventory reversals use central batch reverse', INV.count('reverseUnifiedMovementEffectInTransaction') >= 3)
check('sale-return edit uses central batch reverse', 'reverseUnifiedMovementEffectInTransaction' in RETURNS)
check('warehouse transfer edit uses central batch reverse', 'reverseUnifiedMovementEffectInTransaction' in TRANSFER)
check('purchase dependency guard includes deficit settlements', '_requirePurchaseBatchesUnusedInTransaction' in PURCHASES and 'inventory_deficit_settlements' in PURCHASES)
check('legacy cutover cost fallback is warehouse scoped', 'bb.warehouse_id = ?' in BATCH and 'WHERE store_id = ? AND product_id = ? AND unit_cost <= 0' in BATCH)
check('phase4 rejects physical balances on virtual deficits', 'virtual negative-stock deficit carrying a physical batch balance' in PHASE4 and "b.id LIKE 'deficit:%'" in PHASE4)
check('phase4 records completed and blocked states', "closureStateMetaKey" in PHASE4 and "'completed'" in PHASE4 and "'blocked'" in PHASE4)
check('startup marks failed phase4 blocked', 'phase4Service.markBlocked' in STARTUP and 'unifiedBatchPhase4Blocked = true' in STARTUP)
check('startup does not force batch inside phase4 catch', "catch (error, stackTrace)" in STARTUP and "do not mark costing as" in STARTUP)
check('stock writes block phase4 blocked state', 'error_unified_batch_phase4_blocked' in STOCK and "phaseState == 'blocked'" in STOCK)
check('sync writes block phase4 blocked state', 'error_unified_batch_phase4_blocked' in SYNC and "phaseState == 'blocked'" in SYNC)
check('sqlite sync rejects deficit transfer/manufacturing batches', 'BatchInventoryService.isDeficitBatchId(movement.batchId)' in SQLITE_SYNC and "normalizedType.startsWith('transfer_')" in SQLITE_SYNC and "normalizedType.startsWith('manufacturing_')" in SQLITE_SYNC)
check('out-of-order synced deficit reversal fails closed', 'A synchronized negative-stock reversal arrived before its source deficit' in BATCH)
check('post-phase4 stock writes require batch identity', "phaseState == 'completed'" in STOCK and 'error_post_cutover_batch_required' in STOCK)
check('blocked phase4 cannot return partial batch valuation', 'error_unified_batch_valuation_blocked' in ACCOUNTING and 'UnifiedBatchPhase4ClosureService.closureStateMetaKey' in ACCOUNTING and 'SELECT value FROM migration_meta WHERE key = ? LIMIT 1' in ACCOUNTING)
check('BOM estimator reads unified batch balances', 'estimateBillOfMaterialsSnapshot' in MFG and 'inventory_batch_balances' in MFG)
check('accounting valuation excludes malformed virtual deficit balances', "b.source_type <> 'inventory_deficit'" in ACCOUNTING and "b.id NOT LIKE 'deficit:%'" in ACCOUNTING)
check('BOM estimator excludes deficit batches', "b.source_type <> 'inventory_deficit'" in MFG and "b.id NOT LIKE 'deficit:%'" in MFG)
check('BOM API is forwarded to UI', 'estimateBillOfMaterialsUnitCost' in FORWARD and 'estimateBillOfMaterialsSnapshot' in FORWARD)
check('BOM screen displays estimated cost', 'FutureBuilder<double>' in UI and 'estimateBillOfMaterialsUnitCost(bom)' in UI)
check('BOM printing uses estimated snapshot', 'estimateBillOfMaterialsSnapshot(bom)' in UI and 'bom: estimatedBom' in UI)

failed = [name for name, ok in checks if not ok]
for name, ok in checks:
    print(f"{'PASS' if ok else 'FAIL'}  {name}")
print(f"\nRESULT: {len(checks) - len(failed)}/{len(checks)} checks passed")
if failed:
    raise SystemExit(1)
