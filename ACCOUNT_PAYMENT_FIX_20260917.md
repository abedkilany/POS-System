# Ventio account payment / Cash Ledger fix — 2026-09-17

## Root cause
Modern receipt/payment vouchers create compatibility account movements such as:
- `*-customer-account-payment`
- `*-supplier-account-payment`

`PaymentVoucherService.backfillLegacyCashLedger()` previously recognized only
`*-customer-payment` / `*-supplier-payment` as modern voucher-backed movements.
As a result, an account-level cash receipt could later be mistaken for a legacy
account transaction and copied into Cash Ledger a second time.

## Fixes
1. `backfillLegacyCashLedger()` now excludes both invoice-allocated and
   account-level voucher compatibility movements, including suffixed edit forms.
2. The backfill contains a self-heal step that soft-deletes only stale derived
   `legacy_account_payment_*` duplicates when an authoritative receipt/payment
   voucher already exists. The original voucher Cash Ledger row remains active.
3. Account-ledger receipt printing now resolves both `*-payment` and
   `*-account-payment` compatibility movements back to the original voucher.
4. Customer account payment UI can now:
   - select one open invoice;
   - select multiple open invoices;
   - select all open invoices;
   - allocate by oldest-first;
   - keep a payment unallocated as "Payment on account" when intentionally needed.
5. `settleAccountPayment()` now accepts `PaymentAllocationDraft` entries and passes
   them to the authoritative receipt/payment voucher service.
6. Arabic, English, and French strings were added for the new allocation UI.
7. Regression coverage was added for the account-level duplicate/backfill repair.

## Validation against the provided database
The repair predicate matched exactly two active derived duplicates:
- 231.00 USD — السيد اياد (سوبر ماركة البركة)
- 25.65 USD — السيد احمد بدر

Total duplicate amount: 256.65 USD.
On a copied database, applying the same self-heal logic changed the active Cash
Ledger balance from 245.14 USD to -11.51 USD while leaving the authoritative
`receipt_voucher` Cash Ledger movements active.

## Tooling note
The execution environment used for this patch does not contain the Flutter SDK,
so `flutter analyze` / Flutter tests could not be executed here. Run locally:

```powershell
flutter analyze
flutter test test/payment_voucher_phase2_test.dart
```
