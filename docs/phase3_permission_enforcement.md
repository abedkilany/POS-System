# Phase 3 — Permission Enforcement Audit

Status: **implementation complete in code; runtime/analyze verification pending the deferred post-Phase-3 test gate**.

## Objective

Make permissions authoritative at the mutation boundary. UI visibility is convenience only; sensitive operations must reject unauthorized callers inside `AppStore` or at the direct service boundary.

## Enforcement matrix

| Domain | Mutation permission |
| --- | --- |
| Products | `products.manage` or the dedicated create/edit/delete permission |
| Purchases create/update/receive | `purchases.manage` |
| Purchase return/cancel | `purchases.cancel` |
| Supplier payments/refunds | `suppliers.payment.manage` |
| Expenses create/update | `expenses.manage` |
| Expense post/approve | `expenses.manage` or `expenses.approve` |
| Expense cancel | `expenses.manage` or `expenses.cancel` |
| Expense draft delete | `expenses.manage` or `expenses.delete` |
| Inventory counts | `inventory.counts.manage` |
| Inventory corrections / expiry adjustments | `inventory.corrections.manage` |
| Warehouse create / stock transfer | `inventory.warehouses.manage` |
| Manufacturing | `inventory.manufacturing.manage` |
| Waste operations | `inventory.waste.manage` |
| Quotations | `quotations.manage` |
| Delivery notes | `delivery_notes.manage` |
| Sale create | `sales.create` |
| Sale return/cancel | `sales.cancel` |
| Accounting direct mutations | `accounting.manage` |
| Cash operations / drawer open-close | `cash_box.manage` |
| Sync transport / Host transfer | `sync.manage` |
| Stress Lab developer flag | `maintenance.manage` |
| Sale warehouse setting | `settings.manage` |

## Closed bypasses

- Removed the `adjustStock(... requireProductsEdit: false)` caller-controlled bypass.
- Inventory actions no longer inherit `products.edit` as a substitute for inventory permissions.
- `canManagePurchases` no longer becomes true through `suppliers.manage`.
- `canManageInventory` no longer treats `inventory.movements.view` as a management permission.
- Supplier money movement is separated from supplier master-data management.
- Purchase cancellation is separated from purchase creation/editing.
- Quotation and delivery-note workflows use their dedicated permissions.
- `CashOperationService` now requires a `BusinessSessionContext` and enforces `cash_box.manage` inside the service before any database mutation.
- `AccountingService.openCashDrawer`, `closeCashDrawer`, and `createCashTransfer` now require the same authorization context and enforce `cash_box.manage` at the service boundary; internal transfer calls propagate that context.
- UI guards remain as a convenience layer, but are no longer the sole protection for these cash mutations.
- Host transfer request/activation, pairing/device administration, manual sync actions, and transport switching require `sync.manage` at their mutation boundaries.

## Intentional exceptions

Authentication/bootstrap, password-recovery, replication/apply, startup migration, backup restore internals, and sync-engine protocol methods are system flows rather than ordinary user mutation commands. They remain callable by their controlled workflows and are not converted into interactive role checks in this phase.

## Deferred verification

Per the current project decision, full `flutter analyze` and full test execution are deferred. Focused regression coverage includes a behavioral denial test that calls the cash services directly without `cash_box.manage`, plus the source-level contract at:

`test/phase3_permission_enforcement_contract_test.dart`

It should be executed together with the deferred Phase 1 tests after Phase 3.
