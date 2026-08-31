# P11 Test Fix 3

- Updated the remaining Phase 2 VAT schema contract from schema 29 to schema 31.
- Replaced the brittle global `_saveDirty(accountTransactions: true, sync: true)` occurrence-count assertion with semantic assertions that both sale and purchase settlement paths refresh SQLite account transactions and flush account-transaction/sync state.
- No production logic was changed in this fix.
