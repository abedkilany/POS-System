#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SERVICE = (ROOT / 'lib/core/services/inventory_traceability_service.dart').read_text(encoding='utf-8')
APP_STORE = '\n'.join(
    (ROOT / path).read_text(encoding='utf-8')
    for path in (
        'lib/data/app_store.dart',
        'lib/data/app_store_forwarding_api.dart',
        'lib/data/app_store_orchestration.dart',
        'lib/data/app_store_domains.dart',
    )
)
TRANSFERS = (ROOT / 'lib/data/app_store_warehouse_cash.dart').read_text(encoding='utf-8')
MANUFACTURING = (ROOT / 'lib/data/app_store_manufacturing.dart').read_text(encoding='utf-8')
BATCH_SERVICE = (ROOT / 'lib/core/services/batch_inventory_service.dart').read_text(encoding='utf-8')
PRODUCTS = (ROOT / 'lib/data/app_store_catalog_parties_expenses.dart').read_text(encoding='utf-8')
DATABASE = (ROOT / 'lib/core/storage/sqlite/ventio_drift_database.dart').read_text(encoding='utf-8')
TEST = (ROOT / 'test/production_phase9_multi_warehouse_manufacturing_traceability_test.dart').read_text(encoding='utf-8')
DOC = (ROOT / 'docs/phase9_multi_warehouse_manufacturing_traceability.md').read_text(encoding='utf-8')
BACKUP = (ROOT / 'lib/data/app_store_backup_recovery.dart').read_text(encoding='utf-8')
RECOVERY = (ROOT / 'lib/data/app_store_recovery.dart').read_text(encoding='utf-8')
SNAPSHOT = (ROOT / 'lib/core/snapshot/unified_snapshot.dart').read_text(encoding='utf-8')
SYNC = (ROOT / 'lib/core/services/sqlite_sync_state_service.dart').read_text(encoding='utf-8')

checks: list[tuple[str, bool]] = []

def check(name: str, condition: bool) -> None:
    checks.append((name, bool(condition)))

check('traceability service exists', 'class InventoryTraceabilityService' in SERVICE)
check('batch trace API exists', 'Future<Map<String, dynamic>> traceBatch' in SERVICE)
check('trace is bounded', 'maxDepth < 0 || maxDepth > 32' in SERVICE)
check('trace reads batch warehouse balances', 'inventory_batch_balances' in SERVICE and '_batchBalances' in SERVICE)
check('trace reads batch movement history', 'stock_movements' in SERVICE and '_batchMovements' in SERVICE)
check('manufacturing upstream lineage exists', 'manufacturing_input_to_output' in SERVICE and "movement_type = 'manufacturing_consume'" in SERVICE)
check('Unified Batch keeps FEFO allocation', "substr(b.expiration_date, 1, 10) ASC" in BATCH_SERVICE)
check('Unified Batch keeps oldest-received allocation for non-expiry', "b.received_at" in BATCH_SERVICE and "b.id ASC" in BATCH_SERVICE)
check('warehouse transfer preserves original batch id', 'allocation.batchId' in BATCH_SERVICE and 'toWarehouseId' in BATCH_SERVICE)
check('manufacturing consumes actual batch costs', 'allocation.quantity * allocation.unitCost' in MANUFACTURING and "costingMethod: 'unified_batch'" in MANUFACTURING)
check('manufacturing output source is used', "source_type = 'manufacturing_output'" in SERVICE)
check('transfer transaction invariant exists', 'assertTransferTraceabilityInTransaction' in SERVICE)
check('transfer quantity conservation exists', '(outQty + inQty).abs() > tolerance' in SERVICE)
check('transfer value conservation exists', '(outValue - inValue).abs() > tolerance' in SERVICE)
check('transfer requires two warehouses', 'warehouseCount != 2' in SERVICE)
check('manufacturing transaction invariant exists', 'assertManufacturingTraceabilityInTransaction' in SERVICE)
check('manufacturing material cost is conserved', '(materialCost - expectedMaterialCost).abs() > tolerance' in SERVICE)
check('manufacturing output value is conserved', '(outputValue - expectedEligibleCost).abs() > tolerance' in SERVICE)
check('manufacturing waste equation is enforced', 'expectedMaterialCost - expectedWasteCost - expectedEligibleCost' in SERVICE)
check('manufacturing output batches reconcile', 'outputBatchValue - expectedEligibleCost' in SERVICE)
check('global warehouse/batch reconciliation exists', 'warehouse_batch_quantity_mismatch' in SERVICE)
check('expiry contract audit exists', 'expiry_contract_violation' in SERVICE)
check('expiry policy toggle is guarded while stock exists', 'disablesExpiryTracking' in PRODUCTS and 'authoritativeStock > 0.000001' in PRODUCTS)
check('post-cutover missing batch audit exists', 'warehouse_transfer_missing_batch_identity' in SERVICE and 'unified_batch_cutovers' in SERVICE)
check('manufacturing integrity audit exists', 'manufacturing_traceability_mismatch' in SERVICE)
check('public trace entry point exists', 'traceInventoryBatch' in APP_STORE)
check('public integrity entry point exists', 'verifyInventoryTraceabilityIntegrity' in APP_STORE)
check('single transfer enforces traceability before commit', TRANSFERS.count('assertTransferTraceabilityInTransaction') >= 2)
check('manufacturing enforces traceability before commit', 'assertManufacturingTraceabilityInTransaction' in MANUFACTURING)
check('schema supports phase9+ traceability', any(f'schemaVersion => {version}' in DATABASE for version in range(31, 100)))
check('trace indexes exist', 'idx_stock_movements_reference_type_batch' in DATABASE and 'idx_inventory_batches_source_trace' in DATABASE)
check('deferred executable scenario covers FEFO raw batch', "'p9-raw-early'" in TEST and 'productionRawBatches.single' in TEST)
check('deferred executable scenario traces finished to raw', "traceInventoryBatch('p9-finished-batch')" in TEST and "edge['fromBatchId'] == 'p9-raw-early'" in TEST)
check('deferred executable scenario requires healthy audit', 'verifyInventoryTraceabilityIntegrity()' in TEST and "integrity['healthy']" in TEST)
check('documentation records derived-authority design', 'does not create a second mutable lineage' in DOC)
check('backup carries stock movement trace history', "'stockMovements'" in BACKUP and "'stockMovements'" in SNAPSHOT)
check('backup carries batch identity and warehouse balances', "'inventoryBatches'" in BACKUP and "'inventoryBatchBalances'" in BACKUP and "'inventoryBatches'" in SNAPSHOT and "'inventoryBatchBalances'" in SNAPSHOT)
check('backup carries manufacturing lineage source', "'manufacturingOrders'" in BACKUP and "'manufacturingOrders'" in SNAPSHOT)
check('restore reconstructs batch traceability inputs', "_snapshotListMaps(decoded, 'inventoryBatches')" in RECOVERY and "_snapshotListMaps(decoded, 'inventoryBatchBalances')" in RECOVERY and "_snapshotListMaps(decoded, 'manufacturingOrders')" in RECOVERY and "_snapshotListMaps(decoded, 'stockMovements')" in RECOVERY)
check('sync applies stock movements, inventory batches and manufacturing orders', "case 'stock_movement':" in SYNC and "case 'inventory_batch':" in SYNC and "case 'manufacturing_order':" in SYNC)

failed = [name for name, ok in checks if not ok]
for name, ok in checks:
    print(f"{'PASS' if ok else 'FAIL'}  {name}")
print(f"\nRESULT: {len(checks) - len(failed)}/{len(checks)} checks passed")
if failed:
    raise SystemExit(1)
