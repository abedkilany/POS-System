#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]

def read_library_source(relative_path: str) -> str:
    """Read a Dart library plus all sources included through its `part` list."""
    visited: set[Path] = set()

    def read(path: Path) -> str:
        path = path.resolve()
        if path in visited:
            return ''
        visited.add(path)
        source = path.read_text(encoding='utf-8-sig')
        parts = re.findall(r"^\s*part\s+['\"]([^'\"]+)['\"]\s*;", source, re.M)
        return source + '\n' + '\n'.join(read(path.parent / part) for part in parts)

    return read(ROOT / relative_path)


APP = (ROOT / 'lib/data/app_store.dart').read_text(encoding='utf-8-sig')
APP_LIBRARY = read_library_source('lib/data/app_store.dart')
STATE = read_library_source('lib/data/app_store_state.dart')
DOMAINS = read_library_source('lib/data/app_store_domains.dart')
COMPAT = '\n'.join(
    path.read_text(encoding='utf-8-sig')
    for path in sorted((ROOT / 'lib/data').glob('app_store_forwarding_api*.dart'))
)
ORCH = read_library_source('lib/data/app_store_orchestration.dart')
DATABASE = read_library_source('lib/core/storage/sqlite/ventio_drift_database.dart')
SETTINGS = read_library_source('lib/features/settings/settings_page.dart')
ACCOUNTING = read_library_source('lib/features/accounting/accounting_page.dart')
DASHBOARD = read_library_source('lib/features/dashboard/dashboard_snapshot_service.dart')
PURCHASES_UI = read_library_source('lib/features/purchases/purchases_page.dart')
PURCHASE_WORKSTATION_UI = read_library_source('lib/features/purchases/purchase_workstation_page.dart')
INVENTORY_UI = read_library_source('lib/features/inventory/inventory_page.dart')
MANUFACTURING_UI = read_library_source('lib/features/inventory/manufacturing_page.dart')
TRANSFER_UI = read_library_source('lib/features/inventory/warehouse_transfer_page.dart')
ACCOUNTING_ADVANCED_UI = read_library_source('lib/features/accounting/accounting_page.dart')
ACCOUNTING_SETTINGS_UI = read_library_source('lib/features/accounting/accounting_page_settings.dart')
ACCOUNT_LEDGER_UI = read_library_source('lib/features/accounts/account_ledger_widgets.dart')
ACCOUNT_STATEMENT_UI = read_library_source('lib/features/accounts/account_statement_actions.dart')
CASH_UI = read_library_source('lib/features/cash/cash_page.dart')
CASH_HISTORY_UI = read_library_source('lib/features/cash/cash_history_panel.dart')
SYNC_CORE = (ROOT / 'lib/core/services/unified_sync_core_service.dart').read_text(encoding='utf-8-sig')
EXPENSES_UI = read_library_source('lib/features/expenses/expenses_page.dart')
SALES_UI = read_library_source('lib/features/sales/sales_page.dart')
PURCHASE_DRAFT_SERVICE = (ROOT / 'lib/core/services/purchase_draft_service.dart').read_text(encoding='utf-8-sig')
PURCHASE_RECEIPT_SERVICE = (ROOT / 'lib/core/services/purchase_receipt_service.dart').read_text(encoding='utf-8-sig')
SALE_WORKFLOW_SERVICE = (ROOT / 'lib/core/services/sale_workflow_service.dart').read_text(encoding='utf-8-sig')
GUARD = read_library_source('lib/features/security/sensitive_action_guard.dart')
README = (ROOT / 'README.md').read_text(encoding='utf-8')
APP_SHELL = (ROOT / 'lib/app_split_01.dart').read_text(encoding='utf-8-sig')
TEST = (ROOT / 'test/production_phase12_structural_refactor_contract_test.dart').read_text(encoding='utf-8')

checks: list[tuple[str, bool]] = []

def check(name: str, condition: bool) -> None:
    checks.append((name, bool(condition)))

class_start = APP.find('class AppStore extends ChangeNotifier')
concrete = APP[class_start:] if class_start >= 0 else APP

check('AppStore concrete facade exists', class_start >= 0)
check('AppStore concrete facade is thin', len(concrete.splitlines()) < 220)
check('state partition has seven domain states', all(
    f'class {name}' in STATE for name in (
        '_CatalogState', '_CommerceState', '_InventoryState',
        '_AccountingState', '_SecurityState', '_SyncState', '_RuntimeState')))
accessors = re.findall(r'^\s{2}.+\sget\s+(_[A-Za-z][A-Za-z0-9_]*)\s*=>', STATE, re.M)
check('state compatibility accessors are unique', len(accessors) == len(set(accessors)))
check('all 140 P11 state fields are represented', len(accessors) == 140)
check('AppStore no longer owns product list', 'final List<Product> _products' not in concrete)
check('AppStore no longer owns sale list', 'final List<Sale> _sales' not in concrete)
check('AppStore no longer owns purchase list', 'final List<Purchase> _purchases' not in concrete)
check('AppStore no longer owns accounting ledger list', 'final List<AccountTransaction> _accountTransactions' not in concrete)
check('compatibility layer owns no AppStore state object', '_appStoreState =' not in COMPAT)
check('cross-domain orchestration is separated', 'mixin _AppStoreOrchestration' in ORCH)
check('compatibility API is separated', 'mixin _AppStoreForwardingApi' in COMPAT)
check('typed domain ports exist', all(
    f'abstract class {name}' in DOMAINS for name in (
        'AppRuntimeDomainPort', 'CatalogDomainPort', 'CommerceDomainPort', 'AccountingDomainPort',
        'InventoryDomainPort', 'SecurityDomainPort', 'SyncDomainPort',
        'RecoveryDomainPort')))
check('purchase draft lifecycle rules live in a domain service', all(token in APP_LIBRARY for token in ('PurchaseDraftService().validateItems(', 'draftService.createPurchase(', 'draftService.updateDraft(', 'PurchaseDraftService().softDeleteDraft(')) and all(token in PURCHASE_DRAFT_SERVICE for token in ('Purchase createPurchase(', 'Purchase updateDraft(', 'Purchase softDeleteDraft(')))
check('purchase receipt planning lives in a domain service', 'PurchaseReceiptService().prepare(' in APP_LIBRARY and 'class PurchaseReceiptService' in PURCHASE_RECEIPT_SERVICE)
check('sale create preparation rules live in a domain service', all(token in APP_LIBRARY for token in ('saleWorkflow.validateCreate(', 'saleWorkflow.prepareItems(', 'saleWorkflow.prepareInitialPayment(')) and 'class SaleWorkflowService' in SALE_WORKFLOW_SERVICE)
check('AppStore exposes typed domains', all(
    f'late final {name}' in APP for name in (
        'AppRuntimeDomainPort', 'CatalogDomainPort', 'CommerceDomainPort', 'AccountingDomainPort',
        'InventoryDomainPort', 'SecurityDomainPort', 'SyncDomainPort',
        'RecoveryDomainPort')))
check('app lifecycle and preference consumers use the runtime port', all(
    f'_store.runtime.{operation}' in APP_SHELL for operation in (
        'initialize(', 'prepareForShutdown(', 'loadLocale(', 'saveLocale(',
        'loadThemeMode(', 'saveThemeMode(')) and not any(
            f'_store.{operation}' in APP_SHELL for operation in (
                'initialize(', 'prepareForShutdown(', 'loadLocale(',
                'saveLocale(', 'loadThemeMode(', 'saveThemeMode(')))
check('Settings restore uses recovery domain', bool(re.search(
    r'store\s*\.\s*recovery\s*\.\s*importBackupJson\s*\(', SETTINGS)))
check('typed recovery import uses recovery service',
      'AppStoreRecoveryService(_store).importBackupJson(' in DOMAINS)
check('Sensitive action guard uses security domain', 'store.security.authorizeSensitiveAction(' in GUARD)
check('Accounting UI uses accounting domain', bool(re.search(
    r'store\s*\.\s*accounting\s*\.\s*accountBalance\s*\(', ACCOUNTING))
    and bool(re.search(r'store\s*\.\s*accounting\s*\.\s*transactions\b', ACCOUNTING)))
check('Accounting payment, tax configuration, and party reads use typed domains', all(token in source for source, token in ((ACCOUNTING_SETTINGS_UI, 'widget.store.accounting.updateTaxConfiguration('), (ACCOUNTING_SETTINGS_UI, 'widget.store.accounting.updateDefaultTaxRatePercent('), (ACCOUNT_LEDGER_UI, 'store.accounting.settleAccountPayment('), (ACCOUNT_LEDGER_UI, 'store.commerce.sales'), (ACCOUNT_STATEMENT_UI, 'store.commerce.expenses'), (ACCOUNTING, 'store.commerce.customers'), (ACCOUNTING, 'store.commerce.suppliers'))))
check('financial screens use security permission port', all(token in source for source, token in ((ACCOUNTING_ADVANCED_UI, 'widget.store.security.requirePermission('), (CASH_UI, 'widget.store.security.requireAllPermissions('), (EXPENSES_UI, 'widget.store.security.hasAnyPermission('))))
check('accounting and cash screens read session identity through security port', all(token in source for source in (ACCOUNTING_ADVANCED_UI, CASH_UI) for token in ('widget.store.security.activeUser', 'widget.store.security.currentRole')))
check('cash ledger refresh uses accounting port',
      'widget.store.accounting.refreshFromSqlite(' in CASH_HISTORY_UI)
check('Unified sync core uses typed sync port for queue and apply operations', all(token in SYNC_CORE for token in ('store.sync.pendingChangesForTarget(', 'store.sync.markPushInProgress(', 'store.sync.markAcknowledged(', 'store.sync.applyRemoteChanges(')) and not any(token in SYNC_CORE for token in ('store.applyRemoteSyncChanges(', 'store.markSyncChangesSyncedByIds(', 'store.pendingSyncChangesForTarget(')))
check('Dashboard consumes catalog/commerce/inventory/accounting/sync ports', all(token in DASHBOARD for token in ('store.catalog.products', 'store.commerce.sales', 'store.commerce.purchases', 'store.commerce.expenses', 'store.inventory.stockMovements', 'store.accounting.transactions', 'store.sync.queue')))
check('Sales UI uses commerce loader port', 'widget.store.commerce.ensureSalesLoaded()' in SALES_UI)
check('Purchases UI uses commerce loader port', 'widget.store.commerce.ensurePurchasesLoaded()' in PURCHASES_UI)
check('Sales create/return actions use commerce commands', all(token in SALES_UI for token in ('widget.store.commerce.createSale(', 'widget.store.commerce.returnSale(')))
check('Purchase create/return actions use commerce commands', all(token in PURCHASES_UI + PURCHASE_WORKSTATION_UI for token in ('widget.store.commerce.createPurchase(', 'widget.store.commerce.returnPurchase(', 'widget.store.commerce.createPurchaseReturn(')))
check('Cash sale/purchase settlement and refund paths use commerce commands', all(re.search(r'widget\.store\.commerce\s*\.\s*' + re.escape(method) + r'\s*\(', CASH_UI) for method in ('settleSalePayment', 'settlePurchasePayment', 'refundableSaleCashAmount', 'refundablePurchaseCashAmount', 'refundablePurchaseReturnCashAmount', 'refundSaleCash', 'refundPurchaseCash', 'refundPurchaseReturnCash', 'normalizeRefundAllocations')))
check('Inventory adjustment/count/transfer actions use inventory commands', all(token in INVENTORY_UI + TRANSFER_UI for token in ('widget.store.inventory.adjustStock(', 'widget.store.inventory.createInventoryCountSession(', 'widget.store.inventory.createWarehouseTransferOrder(')))
check('Manufacturing start/reversal actions use inventory commands', all(token in MANUFACTURING_UI for token in ('widget.store.inventory.startManufacturingOrder(', 'widget.store.inventory.reverseManufacturingOrder(')))
check('Manufacturing recipes and order lifecycle use inventory commands', all(re.search(r'widget\.store\.inventory\s*\.\s*' + re.escape(method) + r'\s*\(', MANUFACTURING_UI) for method in ('createBillOfMaterials', 'updateBillOfMaterials', 'deleteBillOfMaterials', 'estimateBillOfMaterialsSnapshot', 'estimateBillOfMaterialsUnitCost', 'deleteManufacturingOrder', 'updateManufacturingOrder', 'finishManufacturingOrder', 'editCompletedManufacturingOrder')) and all(token in MANUFACTURING_UI for token in ('widget.store.inventory.billsOfMaterials', 'widget.store.inventory.manufacturingOrders')))
check('warehouse stock reads use inventory port', all(token in INVENTORY_UI + TRANSFER_UI + MANUFACTURING_UI + SALES_UI + PURCHASES_UI for token in ('inventory.stockForWarehouse(', 'inventory.warehouseStockFromSqlite(', 'inventory.warehouseStockBalancesFromSqlite(', 'inventory.resolveWarehouseForSale(', 'inventory.resolveWarehouseForPurchase(')))
check('remaining inventory screen actions use inventory port', all(re.search(pattern, INVENTORY_UI) for pattern in (r'widget\.store\s*\.inventory\s*\.createWarehouse\(', r'widget\.store\s*\.inventory\s*\.reviewAutoCorrection\(', r'widget\.store\s*\.inventory\s*\.setExpiryBatchStatus\(', r'widget\.store\s*\.inventory\s*\.adjustExpiryBatchStock\(', r'widget\.store\s*\.inventory\s*\.manualStockAdjustmentVersion\(', r'widget\.store\s*\.inventory\s*\.editStockAdjustment\(', r'store\s*\.inventory\s*\.recordWasteLoss\(', r'store\s*\.inventory\s*\.deleteWasteLoss\(')))
check('Inventory reads and permission checks use typed domains', all(token in INVENTORY_UI + MANUFACTURING_UI + TRANSFER_UI for token in ('catalog.stockTrackedProducts', 'inventory.autoCorrectionMovements', 'inventory.pendingAutoCorrectionMovements', 'inventory.inventoryCountSessions', 'security.hasPermission(', 'security.hasAnyPermission(')) and 'widget.store.inventory.recentTransferOrders(' in TRANSFER_UI and not any(token in INVENTORY_UI + MANUFACTURING_UI + TRANSFER_UI for token in ('store.stockTrackedProducts', 'store.stockMovementsRevision', 'store.hasPermission(', 'store.hasAnyPermission(', 'store.recentWarehouseTransferOrders(')))
check('P9 trace API remains compatible', 'traceInventoryBatch(' in COMPAT and 'verifyInventoryTraceabilityIntegrity()' in COMPAT)
check('sensitive action compatibility remains present', 'Future<bool> authorizeSensitiveAction' in COMPAT)
check('backup compatibility remains present', 'Future<String> exportBackupJson()' in COMPAT and 'Future<void> importBackupJson' in COMPAT)
check('sync compatibility remains present', 'applyRemoteSyncChanges(' in COMPAT)
check('production schema supports phase12+', any(f'schemaVersion => {version}' in DATABASE for version in range(31, 100)))
check('P9 indexes remain in schema', 'idx_stock_movements_reference_type_batch' in DATABASE and 'idx_inventory_batches_source_trace' in DATABASE)
check('README documents eight typed domains', '### AppStore domain boundary' in README and '`store.runtime`' in README and '`store.accounting`' in README)
check('P12 contract test exists', 'Phase 12 keeps AppStore as a thin facade' in TEST)
check('translation debt moved to keys', "tr.text('unified_batch')" in SETTINGS)

failed = [name for name, ok in checks if not ok]
for name, ok in checks:
    print(f"{'PASS' if ok else 'FAIL'}  {name}")
print(f"\nPhase 12 static verification: {len(checks) - len(failed)}/{len(checks)} PASS")
if failed:
    raise SystemExit(1)
