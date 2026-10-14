# Ventio

Ventio is an offline-first sales, inventory, accounting, synchronization, and backup application.
Business operations are stored locally in SQLite and shared between authorized devices through LAN or Direct synchronization.

## Documentation policy

`README.md` is the canonical project-level documentation for the current Ventio architecture, operating rules, and release gates. Do not add phase-completion, fix-report, audit-report, or temporary implementation Markdown files in the project root or a separate `docs/` folder. Historical implementation detail belongs in version control; durable behavior belongs here and in executable tests.

## Pure DB-First Contract

SQLite is the only source of truth for business, accounting, inventory, and manufacturing state. SharedPreferences may contain presentation preferences or connection settings only; it is not a business datastore. legacy JSON blobs are compatibility input and are never used as the runtime source of truth.

Application startup hydrates state from SQLite, and all business mutations are written transactionally before in-memory caches are refreshed.

## Runtime architecture

- SQLite is authoritative for operational business state on each device.
- The Host is authoritative for shared business data within a store.
- LAN is used for peer communication inside the local network.
- Direct uses the VPS for pairing, signaling, ICE configuration, device authorization, and Host status.
- The VPS is a control-plane service and is not a business-data store.
- Business payloads move between Host and Client through LAN or the Direct peer channel.
- Retired transport endpoints return `LEGACY_SYNC_REMOVED` and cannot move business data.

### AppStore domain boundary

`AppStore` is a thin application-session facade rather than a business-logic god object. SQLite remains authoritative. Runtime caches and short-lived mutable state are partitioned into Catalog, Commerce, Inventory, Accounting, Security, Sync, and Runtime state objects. Cross-domain lifecycle coordination lives in a dedicated orchestration layer, while existing split business modules remain the implementation owners for their workflows.

New code should prefer the typed domain ports exposed by `store.catalog`, `store.commerce`, `store.accounting`, `store.inventory`, `store.security`, `store.sync`, and `store.recovery`. The legacy AppStore method surface is retained only as a compatibility layer so existing screens can migrate incrementally without a behavior-changing flag-day rewrite. The compatibility layer owns no mutable state.

## Inventory architecture

Ventio uses Unified Batch inventory for stock-tracked products.

- Every stock-tracked outbound movement is allocated from persisted inventory batches.
- Products with expiry tracking use FEFO allocation.
- Products without expiry tracking use the oldest received batch first.
- Batch allocations carry their actual unit cost and are used to derive COGS.
- Expiry-tracked stock requires valid expiry data according to the product configuration.
- Negative anonymous batch slices are not created when stock is insufficient.
- `warehouse_inventory` is the aggregate warehouse quantity and must reconcile with the sum of `inventory_batch_balances` for the same store, warehouse, and product.
- Stock movement and batch-balance changes are performed inside the same SQLite transaction.
- Sale returns restore the exact batch slice originally consumed by the returned quantity.

### Inventory counts

- Shortage: debit the inventory-count loss role and credit inventory.
- Overage: debit inventory and credit the inventory-count gain role.
- Approval is blocked if the counted product moved in the warehouse after it was counted; the product must be recounted.
- Count approval, stock movements, journal posting, audit metadata, and count lines commit atomically.
- A failed accounting post rolls back the stock adjustment and leaves the count open.
- Approved counts are reversed by opposite linked stock movements and a linked journal reversal; the original audit history is preserved.

## Accounting architecture

Ventio uses a seeded Chart of Accounts plus semantic Account Roles stored in `accounting_settings` under `role_*_account_id` keys.
Operational workflows resolve accounts through roles rather than relying on hard-coded chart codes.

Account-role resolution requires the target account to exist, be active, and be postable. System grouping accounts are non-postable, protected system accounts cannot be removed, and accounts referenced by journals or active configuration are protected from unsafe deletion.

### Core posting rules

- Sale without discount: Accounts Receivable/cash -> Sales Revenue + Sales Tax; COGS -> Inventory.
- Sale with discount: Accounts Receivable/cash + Sales Discounts -> gross Sales Revenue + net Sales Tax; COGS -> Inventory.
- A fully discounted sale still posts Sales Discounts against Sales Revenue and still posts COGS against Inventory.
- Sale return: Sales Returns -> Accounts Receivable; Inventory -> COGS.
- Purchase: Inventory/Purchase Tax -> Accounts Payable/cash.
- Receipt voucher: cash/bank -> Accounts Receivable.
- Payment voucher: Accounts Payable -> cash/bank.
- Cash shortage: Cash Short -> cash.
- Cash overage: cash -> Cash Over.
- Cash transfer: destination cash account -> source cash account.
- Expense: the configured semantic expense role -> cash or Accounts Payable.

Sales Discounts and Sales Returns are debit-normal contra-revenue accounts and reduce reported revenue by debit/credit effect rather than by absolute balance.

### Atomicity and reversals

Document state, stock effects, payment compatibility rows, Cash Ledger effects, and accounting journals participate in the authoritative SQLite transaction where the workflow owns one.
Reversals preserve the original journal and create linked opposite entries instead of deleting accounting history.

The production accounting integrity audit is read-only and is considered clean only when it reports zero critical issues. It checks journal balance/linkage, duplicate or missing authoritative postings, document/reversal linkage, stock/accounting linkage, voucher identity, Cash Ledger consistency, AR/AP party balances, cash-location vs General Ledger balances, and inventory valuation consistency.

## AI assistant data contract

The provider-neutral local read-tool layer, provider adapters, consent gate, device-local key storage, provider settings, and ephemeral assistant chat screen are implemented under `lib/features/assistant/` and integrated into Ventio navigation.

### Data and provider boundary

- SQLite remains the only source of business data. Ventio reads requested data on the authorized device and sends the provider the question and the minimum required context: bounded query results for analysis, or relevant excerpts from the approved code index for workflow help. The model never receives a database file, database credentials, or permission to submit SQL.
- Assistant data access is an allowlist of named, typed, parameterized read operations. The app checks the signed-in user's Ventio permissions and reads from the current device's local Ventio database. No create, update, delete, posting, or database-editor operation is exposed to the assistant.
- On native Ventio clients, the adapters send requests directly to the selected provider; the Ventio VPS is not in that request path. OpenAI uses the Responses API with response storage disabled, Gemini uses the stateless Interactions API, and Groq uses its OpenAI-compatible Chat Completions API. Tool results are executed locally and returned to the provider only as part of the active request. Ventio Web blocks provider key entry and requests until a secure gateway is configured.
- The user chooses OpenAI, Google Gemini, or Groq, supplies their own provider API key, and sees the data-use disclosure before choosing whether to send business data. Consent is off by default, scoped by signed-in Ventio user, store, and provider, and checked again before each local report read. The disclosure explains that the provider receives the question, recent active-chat messages, and required read-only results; provider account terms govern retention and possible use, and API use may be billed to the user's provider account. Provider keys are stored with the device secure-storage plugin on native clients. Never package a Ventio-owned key in the client.
- Direct BYOK calls leave a client-side key available to the running native app. Do not enable direct key entry or provider requests in the web client. The next web integration requires a Ventio VPS gateway and a separate review of its key handling, retention, logging, and user disclosure.
- Assistant messages and recent conversation history are held only in memory while the chat page is open. Ventio does not persist or log them. Provider data handling is governed by the selected provider's current terms and account settings.
- Source-code knowledge is separate from store data. A read-only index may retrieve relevant Ventio source and help content from the approved GitHub repository. Do not give the model repository credentials or index business records as source-code material.
- A tool result should include its report name, date range or as-of date, store timezone, currency, filters, and data freshness when available. The answer should identify the report and period it used and say when the requested number cannot be derived from an authoritative report.

### Read-only data catalog

| Question area | Existing local read foundation | Assistant work still required |
| --- | --- | --- |
| Financial statements and journals | `AccountingService`: income statement, balance sheet, trial balance, general ledger, cash flow, tax, journal summaries, and journal details. | Read tools are implemented for income statement, balance sheet, trial balance, cash flow, and tax. General ledger and journal detail tools need bounded, paginated results before exposure. |
| Customer and supplier balances | `AccountingAgingService.customerAgingReport` and `supplierAgingReport`; aging allocates later receipts/payments to the oldest open documents and reports standard aging buckets. | Customer receivables and supplier payables aging tools are implemented; each returns totals and at most 100 party rows. |
| Cash and bank | `CashLedgerService.list` and `summary`; accounting cash balances, cash/bank movements, and cash-flow reports. | Current cash/bank balances and date-bounded cash flow are exposed. Cash Ledger movement detail and date-filtered summaries still need tools. |
| Sales and purchases | `BusinessSqliteStore.assistantSalesSummary` groups non-cancelled sales by saved base currency; `assistantPurchaseSummary` groups received purchases and returns by document type using USD reference values. | Operational summaries are implemented. Use the accounting income statement for recognized revenue, returns, and accounting profit; draft and cancelled purchase records are excluded. |
| Expenses | `BusinessSqliteStore.assistantExpenseSummary` groups posted, non-deleted expense amounts and categories by inclusive period, using the model's USD reference amount. | Period totals and up to 50 category totals are implemented; the response preserves the full total when categories are truncated. |
| Products, stock, and valuation | Product queries, stock-movement and waste/loss queries, `StockTransactionService.listBalances`, and `AccountingService.inventoryValuationReport`. | Accounting cost valuation is limited to accounting viewers. Current stock balances and dated movements are exposed to inventory or accounting viewers, with at most 100 product/warehouse detail groups; quantities stay grouped by product, warehouse, and branch. Keep retail estimates separate from accounting cost valuation. |
| Manufacturing and inventory counts | `AccountingService.manufacturingOrderCostReport`, `manufacturingWasteReport`, and `inventoryCountVarianceReport`; local BOM and manufacturing-order reads. | Cost, waste, and count-variance tools are exposed to inventory or accounting viewers, with aggregate totals and at most 100 rows. Date and product filters remain to be added. |
| Ventio workflows and data entry | Ventio source code, localization strings, and approved user documentation. | Retrieve only relevant source/help passages from the read-only code index and cite the screen or workflow in the answer. This path does not require sending store data. |

`AssistantReadToolService.definitionsFor` offers only tools allowed by the active user's page permissions and only while business SQLite is available. `execute` checks permission again, rejects unknown tools and extra arguments, validates calendar dates, uses inclusive local-day ranges, and caps returned detail rows at 100 while preserving full-result totals. Its current implementation only calls read methods. Sales summaries use saved base amounts grouped by currency and flag legacy invoices with no saved base amount; purchase and expense summaries use the models' USD reference values. Financial profit comes from `AccountingService` reports rather than an operational estimate. Current tools do not filter by branch; branch-specific questions must wait for branch-filtered tools. On a Client device, results identify the data as a local copy that may lag behind the Host.

The model may request only a named tool and validated arguments. Ventio runs that read locally and returns a bounded result to the provider through the request flow. Questions outside the catalog should receive a clarification or a clear statement that Ventio cannot currently derive the requested figure; they must not trigger arbitrary SQL or a guessed calculation.

## Cash, vouchers, cancellation, and returns

- Cash-drawer opening and closing are atomic.
- Expected cash is derived from the current shift Cash Ledger.
- Receipt/payment vouchers and cash references use immutable reversal records with audit metadata.
- Reversal retries are idempotent and do not create a second money movement or overwrite the original reversal audit metadata.
- `paid_amount` and payment status are compatibility caches rebuilt from active posted allocations.
- Invoice cancellation/return and physical cash movement are separate business events.
- `cancelSale()` reverses sale/accounting/stock effects and does not automatically refund cash.
- `cancelPurchase()` reverses purchase/accounting/stock effects and does not automatically refund supplier cash.
- Sale returns create the return/credit-note effect without automatically moving cash.
- Physical customer/supplier cash movement is posted only through the explicit refund workflow.
- Cash refunds are capped by the actual cancellation/return entitlement.
- Partial sale returns are cumulative and cannot exceed the remaining quantity from the original invoice.
- Original sale lines remain intact; returned quantities are represented by persisted return/credit-note history.

### Legacy cash migration and reconciliation

The Maintenance area contains the legacy cash migration/reconciliation action (currently exposed in the UI as Phase 7 Migration). It is intentionally manual and safe to re-run.

- Legacy customer receipts and supplier payments can be materialized as first-class vouchers.
- Historical allocations are linked when the party/document relationship is valid; excess value remains unallocated credit rather than over-allocating an invoice.
- Historical Cash Ledger backfill does not replay old money into the live cash balance.
- Missing accounting linkage can be rebuilt idempotently where it can be determined safely.
- Unresolvable history is reported as an issue instead of being guessed.
- A run is not considered reconciled while blocking errors remain.

## Backup and restore

- Exported backups are JSON.
- Local automatic backups use `.vtb` archives containing `backup.json` and `manifest.json`.
- Restore accepts JSON, local `.vtb` archives, and supported encrypted backup JSON.
- Use the Host device for import and restore operations.

## Connecting devices

Each device has its own local identity. To connect devices to the same store, use the Host pairing code through LAN or Direct. A Client chooses one active transport; a Host may expose both LAN and Direct.

For Direct deployments, configure TURN when relay connectivity is required:

```bash
TURN_SERVER_URLS=turn:your-turn-server.example.com:3478
TURN_SHARED_SECRET=choose-a-long-random-turn-secret
```

`TURN_SERVER_URLS` accepts comma- or space-separated `turn:` URLs. `/api/sync/ice-config` returns short-lived device-scoped ICE credentials. Direct should be validated on same-LAN, independent-router, restrictive/symmetric-NAT, UDP-blocked/TCP-TLS-relay, and connection-loss/recovery scenarios before a production release.

## Production API setup

Configure the VPS deployment with values equivalent to:

```bash
DATABASE_URL=postgresql://...
ACCOUNT_JWT_SECRET=choose-a-long-random-account-secret
ADMIN_JWT_SECRET=choose-a-different-long-random-admin-secret
VENTIO_API_ALLOWED_ORIGINS=https://your-app-domain.com
REQUIRE_DEVICE_TOKEN_AUTH=true
TURN_SERVER_URLS=turn:your-turn-server.example.com:3478
TURN_SHARED_SECRET=choose-a-long-random-turn-secret
```

`ACCOUNT_JWT_SECRET` and `ADMIN_JWT_SECRET` are required and must be different. Changing either secret invalidates existing access tokens and requires users to sign in again.

## Quality and release gate

The Phase 0 baseline process captures a reproducible production baseline before posted-document behavior changes. To create a new baseline capture, run this on the Windows release machine:

```powershell
.\tool\run_phase0_baseline.ps1
```

The baseline runner records the Flutter version, dependency resolution, analysis, tests with coverage, the shared coverage result, Windows integration tests when available, and app/schema/protocol versions. It writes `manifest.json`, `summary.md`, and per-step logs under `quality_baseline/<UTC timestamp>/`. Retain that evidence with the release record. The shared coverage policy lives in `tool/quality_gate_config.json`; PowerShell and Bash use the same Dart coverage evaluator so the same `lcov.info` produces the same result on both platforms.

### Phase 0 historical snapshot

The original Phase 0 review captured source archive version `1.0.26+26`. These values describe that archive and are not the current project inventory:

- 88 unit/widget test files and 2 enabled desktop integration test files.
- The navigation and performance integration tests were disabled at the time: `integration_test/navigation_flow_test.dart.disabled` and `integration_test/performance_flow_test.dart.disabled`.
- Legacy AppStore schema marker 17; Drift schema version 27.
- Direct peer handshake protocol version 1; authenticated peer session protocol version 1; unified snapshot version 1.
- No single authoritative Sync Protocol Version constant was found in that snapshot. This was recorded as a gap at the time; review current protocol ownership before making incompatible sync changes.

The baseline policy set an enforced coverage minimum of 35% and a progressive target of 75%. The 35% minimum preserved the Windows release gate already in use at the time; raising it requires measuring coverage and adding tests rather than silently changing the gate. Coverage exclusions are maintained in `tool/quality_gate_config.json` and evaluated by `tool/check_coverage.dart`.

Phase 0 acceptance required a passing baseline run on the Windows release machine and retention of its generated evidence. The two disabled integration scenarios' then-current navigation and trace coverage was maintained by the desktop integration suite.

For the normal release gate, run on the appropriate Flutter SDK machine:

```bash
tool/run_full_quality_gate.sh
```

On Windows, use:

```powershell
.\tool\run_full_quality_gate.ps1
```

Windows remains the required environment for the desktop integration suite. Also require API syntax checks, a production-target build, and real-device/network validation appropriate to the release. For accounting-sensitive releases, run `AccountingProductionIntegrityService(database).audit()` against a copy of the production database and require zero critical issues.

## Current release

- Version: `1.0.63+63`
- Primary client: Flutter.
- Local operational database: SQLite.
- Direct control plane: Ventio VPS API.
