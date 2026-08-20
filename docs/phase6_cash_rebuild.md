# Ventio Cash Module — Phase 6

Implemented on the Phase 5 baseline.

## Completed scope

- Atomic cash-drawer opening and closing.
- Expected cash derived from the current shift Cash Ledger.
- Counted cash, shortage/overage reconciliation, and closing transfer support.
- Immutable Cash Ledger reversals linked by `reversal_of_id`.
- Journal-entry reversal without double-moving the cash-location balance.
- Receipt-voucher reversal with preserved audit metadata.
- Payment-voucher reversal with preserved audit metadata.
- Allocation reversal without deleting historical allocation rows.
- Rebuild of invoice/purchase `paid_amount` and `payment_status` from active posted allocations.
- Cash-transfer reversal uses the schema-valid `void` status.
- Sale/purchase cash refunds remain idempotent and reversed refunds become refundable again.
- Cash History exposes reversal for vouchers and cash refunds to accounting-authorized users.
- Legacy cash-voucher ledger backfill is used before reversing older cash vouchers when necessary.

## Phase 6 regression coverage

`test/cash_phase6_test.dart` includes focused Phase 6 scenarios, including expected cash, shortage/overage, true reversal, refund idempotency, voucher reversal, transfer reversal, and funded-shift rollback.

## Local validation note

The delivery environment used to patch this archive does not contain the Flutter/Dart SDK, so `flutter analyze` and `flutter test` could not be executed here. The modified Dart files were subjected to structural delimiter checks and targeted source review. Run the normal Flutter quality gate on the development machine before release.

## Final Phase 6 acceptance fix — cancellation/refund separation

Phase 6 now treats invoice cancellation/return and physical cash movement as separate business events.

- `cancelSale()` reverses the sale/accounting/stock effects but never posts a cash refund automatically.
- `cancelPurchase()` reverses the purchase/accounting/stock effects but never posts a supplier cash refund automatically.
- `returnSale()` creates the return/credit-note effect without automatically moving cash; the credit note is recorded as customer balance until an explicit refund is posted.
- Explicit `AppStore.refundSaleCash()` and `AppStore.refundPurchaseCash()` APIs post the actual cash movement only when cash is physically returned/received.
- Existing receipt/payment vouchers and active allocations remain preserved, so after the invoice journal is reversed their financial effect remains visible as the customer/supplier balance rather than being erased.
- Regression coverage was added to `test/app_store_workflow_test.dart` for both sale and purchase cancellation, proving that cancellation does not change cash and that the later explicit refund does.


## Final return-accounting hardening

- Sale returns now post a dedicated `sale_return` journal entry for only the returned value, including sales/tax reversal and COGS/inventory reversal.
- Full purchase returns reverse the original `purchase` journal entry with cash-balance adjustment disabled, because payment/refund cash is handled independently by vouchers/refunds.
- Sale cash refunds are capped by the return/cancellation entitlement. A $100 cash receipt with a $20 partial return can refund at most $20 until additional return entitlement exists.

## Final acceptance hardening — cumulative returns, FEFO/FIFO, and reversal audit

- Partial sale returns are now cumulative across issued credit notes. The original sale lines remain intact, `Partially Returned` is persisted consistently, and a later return is limited to the remaining quantity per product.
- Repeated partial returns support the same product safely; attempting to return more than the original sold quantity is rejected before stock/accounting mutation.
- Return items preserve the exact returned slice of `batchAllocations` and `costLayerConsumptions`, so FEFO batch restoration and FIFO COGS reversal follow the units actually being returned rather than falling back to the whole sale line or average cost.
- Sale-return stock movements are unique per return operation while retaining `source_movement_id` / `reversal_of_movement_id` links to the original sale movements, allowing multiple partial returns without idempotency collisions.
- Cash-operation and cash-transfer reversals now persist `reversed_at`, `reversal_reason`, `reversed_by`, and `reversed_by_user_id`. Migration guards add these columns for databases upgraded from Phase 5, not only fresh databases.
- Cash History now passes the active user's real name and user id to the reversal service instead of using the role label as the actor.
- Cash Ledger reference reversal is fully idempotent: retrying an already reversed cash reference returns no new reversal and does not overwrite the original audit metadata.
- Regression coverage now includes cumulative partial-return overrun prevention, preservation of FEFO/FIFO slices across consecutive partial returns, reversal audit metadata, and idempotent cash-reversal retry behavior.
