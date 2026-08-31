# Ventio

Ventio is an offline-first sales, inventory, accounting, synchronization, and backup application.
Business operations are stored locally in SQLite and shared between authorized devices through LAN or Direct synchronization.

## Documentation policy

`README.md` is the canonical project-level documentation for the current Ventio architecture and operating rules.
Do not create phase-completion, fix-report, audit-report, or temporary implementation Markdown files in the project root or in a `docs/` folder. Historical implementation detail belongs in version control; durable behavior belongs here and in executable tests.

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

Phase 0 establishes a reproducible production baseline before posted-document behavior changes. On the Windows release machine, run:

```powershell
.\tool\run_phase0_baseline.ps1
```

The baseline runner writes evidence under `quality_baseline/<UTC timestamp>/`. The shared coverage policy lives in `tool/quality_gate_config.json`, and both PowerShell and Bash use the same Dart coverage evaluator so the same `lcov.info` cannot produce platform-dependent coverage results.

For the normal release gate, run on the appropriate Flutter SDK machine:

```bash
tool/run_full_quality_gate.sh
```

On Windows, use:

```powershell
.\tool\run_full_quality_gate.ps1
```

Windows remains the required environment for the desktop integration suite. Also require API syntax checks, a production-target build, and real-device/network validation appropriate to the release. For accounting-sensitive releases, run `AccountingProductionIntegrityService(database).audit()` against a copy of the production database and require zero critical issues. See `docs/production_baseline.md` for the Phase 0 acceptance rule and recorded static baseline.

## Current release

- Version: `1.0.28+28`
- Primary client: Flutter.
- Local operational database: SQLite.
- Direct control plane: Ventio VPS API.
