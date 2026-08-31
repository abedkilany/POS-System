#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
APP = (ROOT / 'lib/data/app_store.dart').read_text(encoding='utf-8')
STATE = (ROOT / 'lib/data/app_store_state.dart').read_text(encoding='utf-8')
DOMAINS = (ROOT / 'lib/data/app_store_domains.dart').read_text(encoding='utf-8')
COMPAT = (ROOT / 'lib/data/app_store_forwarding_api.dart').read_text(encoding='utf-8')
ORCH = (ROOT / 'lib/data/app_store_orchestration.dart').read_text(encoding='utf-8')
DATABASE = (ROOT / 'lib/core/storage/sqlite/ventio_drift_database.dart').read_text(encoding='utf-8')
STRESS = (ROOT / 'lib/features/dev_tools/stress_lab_page.dart').read_text(encoding='utf-8')
SETTINGS = (ROOT / 'lib/features/settings/settings_page_backup.dart').read_text(encoding='utf-8')
ACCOUNTING = (ROOT / 'lib/features/accounting/accounting_page.dart').read_text(encoding='utf-8')
DASHBOARD = (ROOT / 'lib/features/dashboard/dashboard_snapshot_service.dart').read_text(encoding='utf-8')
PURCHASES_UI = (ROOT / 'lib/features/purchases/purchases_page.dart').read_text(encoding='utf-8')
SALES_UI = (ROOT / 'lib/features/sales/sales_page.dart').read_text(encoding='utf-8')
GUARD = (ROOT / 'lib/features/security/sensitive_action_guard.dart').read_text(encoding='utf-8')
README = (ROOT / 'README.md').read_text(encoding='utf-8')
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
        'CatalogDomainPort', 'CommerceDomainPort', 'AccountingDomainPort',
        'InventoryDomainPort', 'SecurityDomainPort', 'SyncDomainPort',
        'RecoveryDomainPort')))
check('AppStore exposes typed domains', all(
    f'late final {name}' in APP for name in (
        'CatalogDomainPort', 'CommerceDomainPort', 'AccountingDomainPort',
        'InventoryDomainPort', 'SecurityDomainPort', 'SyncDomainPort',
        'RecoveryDomainPort')))
check('Stress Lab uses security domain', 'store.security.authorizeSensitiveAction(' in STRESS)
check('Stress Lab uses recovery domain', 'store.recovery.exportBackupJson()' in STRESS)
check('Settings restore uses recovery domain', 'store.recovery.importBackupJson(' in SETTINGS)
check('Sensitive action guard uses security domain', 'store.security.authorizeSensitiveAction(' in GUARD)
check('Accounting UI uses accounting domain', 'store.accounting.accountBalance(' in ACCOUNTING and 'store.accounting.transactions' in ACCOUNTING)
check('Dashboard consumes catalog/commerce/inventory/accounting/sync ports', all(token in DASHBOARD for token in ('store.catalog.products', 'store.commerce.sales', 'store.commerce.purchases', 'store.commerce.expenses', 'store.inventory.stockMovements', 'store.accounting.transactions', 'store.sync.queue')))
check('Sales UI uses commerce loader port', 'widget.store.commerce.ensureSalesLoaded()' in SALES_UI)
check('Purchases UI uses commerce loader port', 'widget.store.commerce.ensurePurchasesLoaded()' in PURCHASES_UI)
check('P9 trace API remains compatible', 'traceInventoryBatch(' in COMPAT and 'verifyInventoryTraceabilityIntegrity()' in COMPAT)
check('sensitive action compatibility remains present', 'Future<bool> authorizeSensitiveAction' in COMPAT)
check('backup compatibility remains present', 'Future<String> exportBackupJson()' in COMPAT and 'Future<void> importBackupJson' in COMPAT)
check('sync compatibility remains present', 'applyRemoteSyncChanges(' in COMPAT)
check('production schema remains 31', 'schemaVersion => 31' in DATABASE)
check('P9 indexes remain in schema', 'idx_stock_movements_reference_type_batch' in DATABASE and 'idx_inventory_batches_source_trace' in DATABASE)
check('README documents domain boundary', '### AppStore domain boundary' in README and '`store.accounting`' in README)
check('P12 contract test exists', 'Phase 12 keeps AppStore as a thin facade' in TEST)
check('translation debt moved to keys', "tr.text('unified_batch')" in (ROOT / 'lib/features/settings/settings_page.dart').read_text(encoding='utf-8'))

failed = [name for name, ok in checks if not ok]
for name, ok in checks:
    print(f"{'PASS' if ok else 'FAIL'}  {name}")
print(f"\nPhase 12 static verification: {len(checks) - len(failed)}/{len(checks)} PASS")
if failed:
    raise SystemExit(1)
