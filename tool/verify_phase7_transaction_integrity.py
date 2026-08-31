from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

checks = []

def check(name: str, condition: bool) -> None:
    checks.append((name, bool(condition)))

accounting = (ROOT / 'lib/core/services/accounting_service.dart').read_text(encoding='utf-8')
store = (ROOT / 'lib/data/app_store_persistence_sync_core.dart').read_text(encoding='utf-8')
stock = (ROOT / 'lib/core/services/stock_transaction_service.dart').read_text(encoding='utf-8')
db = (ROOT / 'lib/core/storage/sqlite/ventio_drift_database.dart').read_text(encoding='utf-8')

check('SQLite WAL enabled', 'PRAGMA journal_mode = WAL;' in db)
check('SQLite FULL synchronous durability', 'PRAGMA synchronous = FULL;' in db)
check('SQLite NORMAL durability removed', 'PRAGMA synchronous = NORMAL;' not in db)
check('SQLite busy timeout configured', 'PRAGMA busy_timeout = 5000;' in db)
check('Journal duplicate check is transaction-local', 'Future<bool> persistEntry() async {' in accounting and '_hasActiveEntryForReference(' in accounting)
check('Journal persistence post-condition exists', 'Journal entry failed its Phase 7 persistence post-condition.' in accounting)
check('Account payment supports existing transaction', 'bool withinExistingTransaction = false' in accounting and 'await db.transaction(persistPayment)' in accounting)
check('Account transaction update is atomic', 'Account payment edited' in store and 'await sqliteDb.transaction(() async {' in store)
check('Account transaction delete is atomic', 'Account payment deleted' in store and '_persistAccountTransactionInExistingTransaction(' in store)
check('Stock operation completion inside transaction', stock.find('await _markOperationCompleted(') > stock.find('await db.transaction(() async {'))
check('Fixed asset journal failure rolls back asset', 'Fixed asset journal entry was not persisted.' in accounting)
check('Fixed asset audit is transaction-owned', "action: 'create_fixed_asset'" in accounting and '_writeAuditLogInTransaction(' in accounting)
check('Depreciation no longer uses INSERT OR IGNORE', 'INSERT OR IGNORE INTO fixed_asset_depreciation' not in accounting)
check('Depreciation has period transaction', 'final inserted = await _db.transaction(() async {' in accounting)

failed = [name for name, ok in checks if not ok]
for name, ok in checks:
    print(f"{'PASS' if ok else 'FAIL'} - {name}")
print(f"\nPhase 7 static verification: {len(checks) - len(failed)}/{len(checks)} PASS")
if failed:
    raise SystemExit(1)
