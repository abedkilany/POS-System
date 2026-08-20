# Phase 7 — Legacy Migration + Accounting Reconciliation

Phase 7 upgrades historical cash/accounting data to the rebuilt voucher-ledger architecture without replaying money movements.

## Implemented

- Added durable `cash_phase7_runs` and `cash_phase7_issues` audit tables (schema version 21).
- Added `CashPhase7MigrationService`, designed to be safely re-run.
- Legacy `account_transactions` customer receipts and supplier payments are materialized as first-class receipt/payment vouchers.
- Historical allocations are linked to their original sale/purchase when the reference and party are valid.
- Allocation is capped at the invoice's remaining amount; any excess remains voucher credit/advance rather than creating an over-allocation.
- Legacy cash migration resolves the historical drawer, creates missing Cash Ledger history, and deliberately does **not** mutate `cash_locations.current_balance`.
- Missing invoice journal entries are rebuilt with `paymentPostedSeparately: true`, keeping invoice accounting separate from payment accounting.
- Existing legacy `customer_payment` / `supplier_payment` journal entries are re-keyed to the migrated voucher when present; otherwise missing voucher journal entries are rebuilt idempotently.
- Legacy invoice journals that embedded cash/bank payment are reversed for audit (without changing live cash) and reposted invoice-only, so historical invoice accounting is separated from payment accounting.
- Existing Phase 6 `legacy_account_transaction` Cash Ledger rows are re-keyed to the migrated voucher instead of duplicated.
- `sales.paid_amount` / `purchases.paid_amount` and payment status are rebuilt from active `payment_allocations` as compatibility caches.
- Reconciliation audits missing invoice/voucher journal entries, over-allocation, and unbalanced posted journals.
- Unresolvable history is persisted as an issue instead of being silently guessed.

## Safety properties

- Existing Phase 2+ vouchers are not remigrated from their compatibility account-transaction rows.
- Deterministic legacy voucher/allocation IDs and existing unique constraints prevent duplicate migration.
- Cash Ledger backfill is history-only and does not replay old balance changes.
- Re-running Phase 7 after a successful run produces no duplicate voucher, journal, allocation, or ledger money effect.

## Validation

`test/cash_phase7_migration_test.dart` covers schema creation, migration of a historical receipt, accounting/ledger creation, no double cash movement, and second-run idempotency.
