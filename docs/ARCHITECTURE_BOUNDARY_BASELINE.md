# Architecture Boundary Baseline

Measured on 2026-10-15 before moving domain implementations. This is the phase-one inventory for AppStore migration and feature-import boundaries. Source code remains authoritative; the checked-in JSON is the machine-readable guard baseline.

## Phase-one repository snapshot

| Measure | Phase-one result |
| --- | --- |
| Git branch before this phase-one work | `main`; working tree clean |
| `lib/data/app_store*.dart` files | 76 total, 75 `part` files |
| Dart files in `lib/` at 800–1000 lines | 33; none exceed 1000 lines |
| Typed AppStore domain ports | 7; ports are implemented by focused adapters, projections, and workflow services |
| Public AppStore facade members | 433 candidates: 280 in the forwarding API parts and 153 in orchestration |
| Used AppStore facade selectors | 208 member names, 978 selector occurrences across 89 production files |
| AppStore source mentions | 326 occurrences across 110 production files |
| Explicitly deprecated aliases | 2 (`setCurrentRole`, `deleteSale`); no production uses outside their compatibility implementations |
| Cross-feature imports | 31 import statements across 27 directed feature-area pairs |
| `flutter analyze` | Passed with no issues |
| Unit/widget test suite | 563 passed, 2 skipped |
| Coverage | Phase-one: 43.52% (26,442 / 60,754 included lines); pre-phase-three: 44.26% (27,214 / 61,487), minimum then 35%, target 75% |
| Windows integration suite | 4 passed |
| Pull-request CI | No quality workflow currently runs on pull requests; `deploy-vps.yml` builds/deploys from `main` |

The original snapshot used `flutter test -r expanded --coverage --concurrency=1`; coverage was checked with `dart tool/check_coverage.dart`. The Windows flow was `flutter test integration_test -d windows -r expanded`. The threshold was later raised from 35% to 40% after the measured 44.26% result; the 75% target is unchanged. The coverage result is available in the ignored local `coverage/lcov.info`; no retained `quality_baseline/` capture exists in this checkout.

## Typed ports and their current implementation

Eight typed ports now cover runtime, catalog, commerce, accounting, inventory,
security, sync, and recovery, including app-shell lifecycle and preferences.
Focused services own purchase draft rules, receipt preparation, sale
validation/payment normalization, read projections, permission evaluation,
recovery-file handling, and sync queue recovery. The data layer composes their
SQLite, accounting, ledger, cache, and sync effects.

| Port | Current contract | Current adapter |
| --- | --- | --- |
| `AppRuntimeDomainPort` | App initialization and shutdown, presentation preferences, runtime identity/profile/readiness, app-shell refresh operations | `AppStore` composes startup, shutdown, preference, and runtime-state adapters behind one app-shell boundary |
| `CatalogDomainPort` | Products, stock-tracked products, categories, brands, units, product lookup, catalog loading | `CatalogReadService` owns filtering, sorting, and product lookup; AppStore retains cache hydration and loading |
| `CommerceDomainPort` | Customers, suppliers, sales, purchases, expenses, sales/purchases loading, selected sale and purchase commands including payment settlement and cash refunds | `CommerceReadService` owns active-row filtering; `PurchaseDraftService`, `PurchaseReceiptService`, and `SaleWorkflowService` own selected lifecycle rules; transaction adapters preserve atomic stock/accounting commits |
| `AccountingDomainPort` | Transactions, revisions, account balance/ledger queries, SQLite refresh, account payment settlement, and tax configuration | `AccountLedgerReadService` owns ledger projections and index construction; typed commands enter the existing voucher and tax persistence workflows directly |
| `InventoryDomainPort` | Warehouses, movements, correction projections, revision, loading, stock-by-warehouse reads and selection, inventory-count state, adjustments, counts, transfer history/orders, BOM and manufacturing-order lifecycle, and batch tracing/integrity | `InventoryReadService` owns warehouse/correction filtering, movement ordering, and movement-to-stock cache projection; SQLite balance queries and warehouse resolution use focused AppStore data adapters; typed commands enter the existing transaction workflows directly, and tracing calls the existing traceability service |
| `SecurityDomainPort` | Active user/role, permission checks, sensitive-action authorization | `PermissionService` computes grants and denials; `_SecurityDomain` reads identity and permissions through focused adapter methods. Sensitive-action authorization remains in the audited session workflow |
| `SyncDomainPort` | Changes, queue, sequence, pending/submitted target reads, push/ack/reject transitions, authoritative apply, retry, submitted-item recovery, and stale-work recovery | Typed reads use focused internal snapshots; `UnifiedSyncCoreService` consumes typed operations while focused AppStore adapters retain persistence and notification orchestration; `SyncQueueRecoveryService` handles retry and stale-work state transitions |
| `RecoveryDomainPort` | Backup export/import and recovery-file parse/export | Recovery-file parse/export use `RecoveryFileService`; backup export/import use `AppStoreRecoveryService`, with SQLite-authoritative restore where supported and a legacy adapter for non-SQLite storage |

## Current migration status

The phase-one inventory recorded 978 AppStore facade selectors in 89
production files. A follow-up audit found that the original checker did not
join Dart `part` files to their library declarations. The corrected scan found
795 direct production selectors across 61 files. Typed-port migrations moved
all 795 selectors out of production features and services; the current
part-aware scan finds **0 selectors across 0 files** and no adapter calls back
through the AppStore facade. The active baseline now records zero and blocks
regressions. The original phase-one inventory is retained in
[`architecture_boundary_phase1_baseline.json`](../tool/architecture_boundary_phase1_baseline.json).

The final interface reduction removed 300 analyzer-confirmed unused forwarding
wrappers and made the remaining forwarding methods and orchestration operations
library-private while preserving calls between `lib/data` parts. Backup
parsing, validation, encryption, and summary operations now enter through
`store.recovery`; the old AppStore backup extension is private. The
public-member inventory is reduced from 431 forwarding members to the nine
properties/methods required by `BusinessSessionContext`. The boundary checker
rejects additional public AppStore members and records zero external
compatibility selectors.

### Phase-three quality verification before final API reduction (2026-10-16)

The complete local quality gate passed: architecture checker and its two
regression tests, `flutter analyze --no-pub`, **596 tests passed and 2 were
skipped**, coverage **44.21%** (27,267 / 61,672 included lines) against a 40%
minimum, and **4 Windows integration tests passed**. The 75% coverage target
remains aspirational. The local PowerShell gate now checks each external
command's exit code so a failed test or analysis step cannot be reported as a
successful gate. The pull-request workflow runs the architecture checks,
analysis, full test suite, and coverage threshold on Linux; Windows integration
remains in the local Windows gate.

That verification predates the final interface reduction described above. The
GitHub `main` branch now requires the quality workflow's
`Flutter analysis, tests, and coverage` status check; final focused verification
after the reduction is recorded below.

### Phase-three final verification after API reduction (2026-10-16)

The AppStore reduction removed the unused forwarding read getters and ten
catalog/inventory cache fields that had no remaining consumers. The state
contract now verifies all 130 active state fields and rejects those retired
caches. The documentation indexes were regenerated after the source and test
updates.

Final local checks passed:

- `flutter analyze --no-pub`: no issues.
- `python tool/test_architecture_boundary_checker.py`: 3 tests passed.
- `python tool/check_architecture_boundaries.py`: pass; 9 public AppStore
  facade members (baseline 9), zero compatibility selectors, zero adapter
  calls through the facade, and 31 reviewed cross-feature imports.
- `python tool/verify_phase12_structural_refactor.py`: 50/50 checks passed.
- 16 focused Flutter tests passed across the AppStore backup/identity,
  accounting atomicity, accounting audit guards, Phase 12 structure, runtime
  domain, and manufacturing flows.

The full Flutter test suite, full coverage run, Windows integration suite, and
application build were not run locally. The GitHub quality workflow runs
analysis, the full suite, and the 40% coverage threshold on pull requests and
pushes to `main`; its `Flutter analysis, tests, and coverage` status is required
on `main`. Admin enforcement is enabled, while branch-up-to-date and PR review
requirements are disabled. See the [quality workflow](../.github/workflows/quality.yml).

The traceability report and full-snapshot test use `store.inventory` for batch
tracing and integrity audits. Their unused AppStore forwarding methods were
removed; other forwarding implementations are now private to the split data
library.

The AppStore migration guard also continues to preserve the 31 reviewed
cross-feature import statements across 27 directed area pairs. Those imports
were classified in phase one as app composition, shared reuse, or justified
integration; the phase-two port migration introduced no new feature edges.
This count is a boundary guard, not a target to force to zero.

The recovery slice moves recovery-file encoding and validation into
`lib/core/services/recovery_file_service.dart`. The `store.recovery` port uses
that service, and recovery-file export retains the `backupExport` permission
check. Backup JSON export and import now enter through
`AppStoreRecoveryService`, while the existing internal snapshot serializer
continues to read application state. Restore authorization and
audit recording remain enforced at the service boundary. SQLite-authoritative
restore transactions run in the recovery service; storage backends without
transactional SQLite support retain the existing restore adapter. The backup
forwarding implementation is now private to the data library; production
settings use the typed recovery port.

The catalog read slice moves active-item filtering, product sorting, and
product-by-id lookup into `lib/core/services/catalog_read_service.dart`. The
typed catalog port and internal getters share the same cache/query helpers. The
products, sales, purchases, and dashboard read paths now use `store.catalog`
for product and catalog-item reads. AppStore still coordinates deferred
hydration and owns catalog cache state.

The commerce read slice moves active-row filtering and list ordering for
customers, suppliers, sales, purchases, and expenses into
`lib/core/services/commerce_read_service.dart`. The typed port calls the
focused data-adapter reads directly, while internal getters keep their existing
load triggers and cache behavior. Dashboard, report snapshots, and maintenance
read paths now use `store.commerce` for these lists. Commerce writes and their
sale/purchase transaction flows remain in their existing workflows.

The commerce command boundary now exposes sale creation, returns and
cancellation, sale quotation create/delete, return cancellation, purchase
creation, purchase returns, purchase return posting, sale/purchase payment
settlement, and cash refunds for sales and purchases. Sales, purchases, and
cash screens use `store.commerce` for these actions. The typed adapter invokes
the existing transactional action implementations directly. AppStore's private
forwarding methods remain internal implementation details while SQLite
transaction ownership, accounting posting, and stock behavior stay unchanged.

Purchase draft create/edit/delete rules are implemented in
`PurchaseDraftService`; it validates lines, maintains stable line identities,
checks expected versions, and builds soft-delete metadata. `PurchaseReceiptService`
prepares the received document, initial-payment plan, batch allocations, and
versioned idempotency key before the SQLite transaction. `SaleWorkflowService`
owns sale-line validation/preparation and customer/payment normalization before
stock allocation. The existing transactional workflows remain responsible for
committing stock, journals, supplier/customer ledgers, cache refresh, and sync
changes together. Focused tests cover these rules and the no-posting draft
boundary.

The security permission slice moves effective permission evaluation into
`lib/core/services/permission_service.dart`. The calculation still grants the
built-in admin role during role hydration, combines role and user grants, and
applies user denials last. Login, database, user/role settings, accounting,
cash, and expense screens use `store.security`; sensitive-action
re-authentication and audit recording stay in the existing session workflow.

The accounting read slice moves ledger row projection, account-key
normalization, and index construction into
`lib/core/services/account_ledger_read_service.dart`. Existing cache updates
and SQLite loading remain in the data layer. Accounting and shared account
ledger views use `store.accounting` for transaction, balance, revision, and
SQLite refresh reads; cash history also uses the port to refresh its ledger.
Customer and supplier account lists use `store.commerce`. Account-level receipt
and payment entry, plus tax-configuration updates, now use typed accounting
commands while preserving the existing voucher and persistence workflows.
Journal mutation and reversal flows remain unchanged.

The inventory read slice moves active-warehouse filtering and movement order
into `lib/core/services/inventory_read_service.dart`. That service also owns
the pure movement-to-warehouse stock projection used by AppStore's cache. The
inventory port reads through these focused projections and invokes the existing
SQLite traceability service directly. Inventory screens now use
`store.inventory` for warehouses,
movements, revisions, loading, stock-by-warehouse reads and warehouse
selection, transfer history, correction projections and inventory-count state,
and trace checks;
they use `store.catalog` for stock-tracked products and `store.security` for
permission decisions. Sales and
purchase screens use the same inventory port for warehouse-stock lookups. The
inventory command boundary now also covers warehouse creation, stock and expiry
adjustments, correction review, waste, manual adjustment edits, inventory count
creation/approval/reversal/cancellation, count-line edits, warehouse transfer
orders, and manufacturing start/reversal. Their UI paths use `store.inventory`,
which enters the existing transactional workflows directly; the accounting,
stock, batch, and reversal implementations remain in their current owners.
Manufacturing screens now also use that port for recipe reads, cost estimates,
recipe create/edit/delete, and manufacturing-order update, finish, completed
edit, and deletion. Production inventory consumers use the typed inventory
and catalog ports; internal forwarding methods are private to the data library.

The sync recovery slice moves failed-item retry and stale in-progress recovery
transitions into `lib/core/services/sync_queue_recovery_service.dart`. The data
layer still owns loading, persistence, and notifications around those state
changes. Submitted-item recovery remains a sync data-adapter operation because
it preserves the Direct relay's Host-confirmation semantics. The Direct
control-plane orchestrator and crash-recovery test use `store.sync` for the
recovery operations. `UnifiedSyncCoreService` now uses the typed sync port for
pending/submitted reads, Host acceptance validation, queue transitions,
authoritative apply, and acknowledgment; the internal adapter retains current
storage and notification ordering. Transport details and soft-delete cleanup
remain in their existing layers.

The phase-one member-to-file usage map is in [`architecture_boundary_phase1_baseline.json`](../tool/architecture_boundary_phase1_baseline.json). The active [`architecture_boundary_baseline.json`](../tool/architecture_boundary_baseline.json) records the corrected part-aware baseline and rejects new selectors, source mentions, public members, and cross-feature imports.

### Phase-one AppStore selector inventory by area (historical)

The counts below preserve the original phase-one debt inventory. They cover selectors whose receiver name was declared with the `AppStore` type in that file, including straightforward `widget.store`, `this.store`, and local aliases. The historical JSON has the exact file and member breakdown; the active selector count is zero.

| Area | Files | Selectors |
| --- | ---: | ---: |
| Account | 1 | 4 |
| Accounting | 13 | 46 |
| Accounts | 2 | 28 |
| Assistant | 9 | 75 |
| Barcode | 1 | 8 |
| Cash | 2 | 13 |
| Customers | 1 | 23 |
| Dashboard | 5 | 57 |
| Database | 1 | 2 |
| Expenses | 1 | 30 |
| Inventory | 8 | 128 |
| Maintenance | 5 | 79 |
| Products | 2 | 14 |
| Purchases | 2 | 34 |
| Reports | 2 | 41 |
| Sales | 3 | 42 |
| Security | 1 | 10 |
| Settings | 10 | 74 |
| Shared | 2 | 16 |
| Suppliers | 1 | 20 |
| App shell (`lib/app_split_*.dart`) | 2 | 41 |
| Core repositories | 1 | 40 |
| Core services | 10 | 99 |
| Unified sync | 4 | 54 |
| **Total** | **89** | **978** |

The selector inventory is a source-based guard, not a Dart analyzer call graph. It follows declared `AppStore` receiver names and simple aliases. Review the baseline JSON when adding or removing an exception; do not regenerate it just to make a failed check pass.

## Cross-feature import classification

`lib/features/shared/` imports are still counted as cross-feature imports. Of the 31 current imports, 10 are app composition, 18 are candidates for a shared boundary, and 3 are justified integrations to keep. No import was found to be wholly unused.

| From → to | Importing file(s) and imported module(s) | Classification and phase-one disposition |
| --- | --- | --- |
| `account` → `shared` | `store_account_dashboard_page.dart` → `sync_monitoring_section.dart` | Justified common sync UI; keep in shared. |
| `accounting` → `accounts` | `accounting_page.dart` → `account_ledger_widgets.dart` | Reused account UI; move to an explicit shared accounts UI boundary. |
| `customers` → `accounts` | `customers_page.dart` → `account_ledger_widgets.dart`, `account_statement_actions.dart` | Reused ledger/statement UI; move to the same shared accounts boundary. |
| `dashboard` → `accounting`, `expenses`, `products`, `purchases`, `reports`, `sales` | `dashboard_page.dart` → each destination page | App-level route composition; move page ownership/imports to the application shell. |
| `database` → `security` | `database_page.dart` → `sensitive_action_guard.dart` | Shared authorization helper; move to `lib/core/security/`. |
| `expenses` → `accounts` | `expenses_page.dart` → `account_statement_actions.dart` | Reused account statement action; move to the shared accounts boundary. |
| `inventory` → `barcode` | `inventory_page.dart` → `barcode_scanner_page.dart` | Reused scanner UI; move the scanner component behind a shared UI boundary. |
| `maintenance` → `database` | `maintenance_page.dart` → `database_page.dart` | Navigation composition; move the route to the application shell. |
| `products` → `barcode` | `products_page.dart` → `barcode_scanner_page.dart` | Reused scanner UI; move behind the shared UI boundary. |
| `purchases` → `barcode`, `security` | `purchases_page.dart` → `barcode_scanner_page.dart`, `sensitive_action_guard.dart` | Scanner is shared UI; authorization helper belongs in `lib/core/security/`. |
| `sales` → `barcode`, `security` | `sales_page.dart` → `barcode_scanner_page.dart`, `sensitive_action_guard.dart` | Scanner is shared UI; authorization helper belongs in `lib/core/security/`. |
| `security` → `settings`, `account`, `admin` | `login_gate_page.dart` → `sync_setup_page.dart`, `store_account_dashboard_page.dart`, `admin_subscribers_page.dart` | Login routing/app composition; move route selection to the application shell. |
| `settings` → `shared` | `settings_page.dart` → `sync_monitoring_section.dart` | Justified common sync UI; keep in shared. |
| `settings` → `security` | `settings_page.dart`, `users_permissions_page.dart` → `sensitive_action_guard.dart` | Shared authorization helper; move to `lib/core/security/`. |
| `settings` → `maintenance` | `settings_page.dart` → `phase10_health_service.dart` | Shared system-health service; move service ownership to `lib/core/services/`. |
| `settings` → `barcode` | `settings_page.dart`, `sync_setup_page.dart` → `barcode_scanner_page.dart` | Reused scanner UI; move behind the shared UI boundary. |
| `settings` → `assistant` | `settings_page.dart` → `assistant_provider_settings_page.dart` | Explicit settings-to-assistant integration; keep while settings embeds provider configuration. |
| `suppliers` → `accounts` | `suppliers_page.dart` → `account_ledger_widgets.dart`, `account_statement_actions.dart` | Reused account UI; move to the shared accounts boundary. |

The local quality-gate guard records the 31 exact import paths, including repeated imports in different files. The groupings above preserve the distinction between valid composition/reuse and accidental coupling; the goal is to reduce the latter without outlawing legitimate shared UI.

## Focused regression tests for the domain boundaries

These tests were used as the initial regression set for the phase-two moves. Keep using the relevant rows for future boundary changes, and add narrower coverage if a change reaches a workflow not represented here. Run accounting, inventory, and sync tests before changing their transaction or transport boundaries.

| Domain | Focused tests to run before its move |
| --- | --- |
| Catalog | `test/app_store_workflow_test.dart`; `test/product_derived_flush_lifecycle_contract_test.dart` |
| Commerce | `test/app_store_workflow_test.dart`; `test/sale_edit_journal_repost_contract_test.dart`; `test/purchase_edit_journal_repost_contract_test.dart` |
| Accounting | `test/accounting_closure_phase1_atomicity_contract_test.dart`; `test/accounting_phase6_reversal_test.dart`; `test/accounting_production_integrity_service_test.dart` |
| Inventory/manufacturing | `test/phase6_multi_warehouse_e2e_test.dart`; `test/production_phase9_multi_warehouse_manufacturing_traceability_test.dart`; `test/warehouse_inventory_phase1_test.dart` |
| Security | `test/phase3_permission_enforcement_contract_test.dart`; `test/phase4_5_6_security_contract_test.dart` |
| Sync | `test/unified_sync_engine_test.dart`; `test/sync_crash_recovery_test.dart`; `test/sync_and_permissions_test.dart` |
| Recovery/backup | `test/recovery_file_service_test.dart`; `test/backup_validation_test.dart`; `test/audit_recovery_regression_test.dart`; `test/production_phase10_health_disaster_recovery_contract_test.dart` |

## Guard behavior

Run `python tool/check_architecture_boundaries.py` to compare source against the active part-aware baseline. The PowerShell and Bash local quality gates run the checker and its regression tests before analysis and tests. It fails on new AppStore facade members, increased AppStore mentions/selectors in a file, adapter calls to facade members, or added cross-feature import paths. The archived phase-one JSON is historical evidence and is not the active allowance.

`.github/workflows/quality.yml` runs the architecture check, `flutter analyze`,
the full test suite with coverage, and the configured coverage gate for pull
requests and pushes to `main`. `deploy-vps.yml` remains a separate deployment
workflow. Select the quality job in GitHub branch-protection rules to require
it before merge.
