# Posted Document Edit — Batch Phase 2

This batch extends the shared posted-document edit contract beyond received
purchases and posted sales.

## Completed in this batch

- Receipt vouchers: safe posted edit with version lock, append-only allocation
  reversal/reallocation, cash-ledger rebuild, accounting repost, and integrity
  verification.
- Payment vouchers: same contract for suppliers/AP.
- Posted expenses: safe edit for cash and credit expenses, versioned accounting
  reference (`expense_edit:vN`), downstream settlement/refund guards, and UI edit.
- Completed warehouse transfers: reverse old source/destination batch effects,
  rebuild the transfer under a versioned movement group, and block when a
  destination batch has downstream movement. UI edit is enabled.
- Manual journal entries: direct edit is limited to `manual_journal` entries;
  system-generated journals remain editable only through their source document.
  The active journal entry id is the optimistic lock and edits create
  `manual_edit:vN` journal-family members.

All implementations follow the shared pipeline:

`Load -> Validate -> Reverse -> Apply -> Rebuild -> Repost -> Verify`

and are owned by a SQLite transaction so failures roll back the entire edit.

## Deferred because they require deeper transactional refactors

- Sales returns / credit notes.
- Purchase returns.
- Completed manufacturing orders.
- Approved inventory counts / general posted inventory adjustments.

These flows currently combine document state, batch lineage, inventory costing,
and accounting in large posting/reversal routines. They should not be converted
by chaining existing public reverse/create methods because that would create a
non-atomic gap between reversal and repost.

## Validation status

Full Flutter analyze/tests are intentionally deferred to the final gate. During
this batch, source delimiter checks, translation key verification, and the Phase
12 structural verifier are used as interim guards.
