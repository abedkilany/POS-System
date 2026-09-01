# Posted Sales Edit — Implementation Baseline

This build adds the first shared posted-document edit contract and a safe posted sales invoice edit workflow on top of the existing received-purchase edit baseline.

## Safety contract

`Validate -> Reverse old operational effects -> Reverse old accounting -> Apply changes -> Rebuild operational effects -> Rebuild posted snapshot -> Repost accounting -> Rebuild derived state -> Verify -> Commit`

The shared orchestrator is `lib/core/services/posted_document_edit_framework.dart`. The caller executes it inside the authoritative SQLite transaction; exceptions are intentionally not caught by the pipeline so the outer transaction rolls back all reversed/rebuilt effects.

## Posted sale editing

`AppStore.editPostedSale(...)` now provides:

- `sales.edit` permission enforcement.
- Optimistic version check (`expectedVersion`).
- Blocks cancelled/deleted sales.
- Blocks edits after an active sale return.
- Blocks edits while a delivery note is linked.
- Blocks changing a customer while payments remain allocated.
- Blocks reducing the edited invoice below already allocated payment.
- Blocks moving to unavailable customers/warehouses.
- Verifies original stock movements are still fully reversible.
- Restores old Unified Batch allocations / legacy cost layers.
- Reverses the active sale accounting family.
- Reallocates stock using the current Unified Batch allocator.
- Rebuilds sale COGS from the newly consumed batches.
- Rebuilds the immutable posted snapshot before accounting repost.
- Reposts accounting as `<saleId>:sale_edit:vN`.
- Rebuilds the customer invoice account transaction.
- Verifies snapshot and journal existence before commit.
- Uses the surrounding SQLite transaction as the rollback boundary.

## Edit -> Edit again -> Return / Cancel

Sale stock movement identity is version-aware:

- Version 1 keeps all legacy movement IDs unchanged.
- Edited versions use `sale-edit-vN` movement IDs and `sale_edit:vN` groups/idempotency keys.
- Authoritative return/cancel now resolve the source movement using the sale version.
- Sale accounting reversal recognizes both the original sale reference and all `sale_edit` versions.

This preserves existing documents while allowing later edits, returns, and cancellation to target the actual current posted effects.

## UI

The sales invoice detail UI exposes an Edit action when the user has `sales.edit`. The dialog supports customer, warehouse, discount, product lines, quantities, and unit prices. Existing historical customer/warehouse/product values are preserved where possible instead of silently replacing them during an edit.

## Contract tests added

- `test/posted_document_edit_framework_contract_test.dart`
- `test/sale_edit_journal_repost_contract_test.dart`

## Verification performed in this environment

- Source delimiter/string balance checks: PASS for all modified Dart files.
- Translation JSON validation: PASS.
- `node scripts/check_translations.mjs`: PASS (`2754` keys in en/ar/fr, `1974` literal usages).
- Static safety-contract assertions: PASS.

Flutter/Dart SDK is not installed in this execution environment, so `flutter analyze` and `flutter test` must be run on the development machine before promoting this build.

Recommended gate:

```powershell
flutter analyze 2>&1 | Tee-Object -FilePath analyze.txt
flutter test 2>&1 | Tee-Object -FilePath test.txt
```

Then explicitly exercise:

1. Create sale -> Edit -> Edit again -> Return.
2. Create sale -> Edit -> Edit again -> Cancel.
3. Partial-paid sale -> edit total upward.
4. Partial-paid sale -> attempt total below paid amount (must block).
5. Paid sale -> attempt customer change (must block).
6. Sale with return -> attempt edit (must block).
7. Sale with linked delivery note -> attempt edit (must block).
8. Batch/expiry product -> edit quantity/product/warehouse and verify FEFO/COGS/batch balances.
