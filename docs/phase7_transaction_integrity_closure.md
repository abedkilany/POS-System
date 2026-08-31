# Production Phase 7 — Transaction Integrity Closure

Status: implemented on top of the P0–P6 production baseline.

> Note: this production-roadmap Phase 7 is separate from the older internal
> `cash_phase7_*` migration naming already present in Ventio.

## Goal

A critical business operation must not leave Ventio in a partially committed
state. Financial, cash, inventory and document artifacts that represent one
business action must either commit together or roll back together.

## Closure work completed

### 1. Account-payment compatibility path

`AppStore.addOrUpdateAccountTransaction` and `deleteAccountTransaction` now use
one authoritative SQLite transaction for the compatibility account row and its
accounting effects.

For an edit, the previous payment journal is reversed and the replacement is
posted in the same transaction. For a delete, journal reversal and the deleted
row commit together. RAM/UI state changes happen only after the SQLite commit.

`AccountingService.recordAccountPayment` is now transaction-aware and can join
an existing transaction. When called standalone, it owns a transaction around
the journal and cash-location balance mutation.

### 2. Journal-entry post-conditions and idempotency

`AccountingService.createPostedEntry` now performs its duplicate-reference
check inside the owning write transaction. Entry-number generation is also
inside that transaction.

Before commit it re-reads the persisted entry and verifies:

- status is `posted`;
- persisted line count equals the draft line count;
- persisted debit and credit totals still balance.

Failure of any post-condition throws and rolls the complete transaction back.

### 3. Stock operation completion metadata

`StockTransactionService.recordMovementsAtomically` now marks its
`stock_operations` idempotency row as `completed` inside the same transaction
that persists the stock movements and inventory balance effects.

This closes the crash window where stock could previously commit while the
operation record remained `pending`.

### 4. Fixed-asset acquisition

The fixed-asset row, acquisition journal and accounting audit entry are now
committed in one SQLite transaction. Failure to create the journal aborts the
asset creation.

### 5. Fixed-asset depreciation

Each depreciation period now owns one transaction containing both:

- the depreciation journal entry; and
- the `fixed_asset_depreciation` row.

The duplicate-period check is performed inside the transaction and the old
`INSERT OR IGNORE` pattern (which could allow an orphan journal) was removed.

### 6. SQLite commit durability

The production connection remains in WAL mode but now uses:

`PRAGMA synchronous = FULL`

instead of `NORMAL`, plus a 5-second busy timeout. This favors durability of
committed accounting/inventory transactions across abrupt shutdown or power
loss.

## Existing critical paths reviewed

The production baseline already had transaction ownership around the principal
sale, sale return/cancel, purchase receive/return/cancel, inventory count,
manufacturing completion/reversal, warehouse transfer, voucher, cash reversal,
and batch inventory paths. Phase 7 preserved these paths and focused changes on
the remaining split-commit gaps rather than rewriting already atomic flows.

## Validation policy for this build

Per project decision, full `flutter analyze` and the full Flutter test suite are
deferred until the final testing stage. This phase adds a source-contract test
and a lightweight static verifier, but successful final production acceptance
still requires the deferred analyze/full-test gates.
