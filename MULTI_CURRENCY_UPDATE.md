# Multi-Currency Accounting Update

Implemented in this package:

- Historical exchange-rate lookup by document date through `StoreProfile.exchangeRateForDate`.
- Generic `convertCurrency` support for all configured active currencies, not only USD/LBP.
- New helper `toBaseCurrencyAmount` to store functional/base-currency values next to transaction-currency values.
- New helper `exchangeDifferenceAmount` for future settlement logic: positive values are FX gains, negative values are FX losses.
- Store profile now includes configurable exchange gain/loss account IDs.
- Sales now persist:
  - `invoiceCurrency`
  - `paymentCurrency`
  - `baseCurrency`
  - `exchangeRateAtInvoice`
  - `transactionAmount`
  - `baseAmount`
  - `paidBaseAmount`
  - `exchangeDifferenceAmount`
- Sales creation no longer forces invoice/payment/discount currency to USD or LBP only; it accepts any active configured currency.
- Sales payment currency selector now lists all active configured currencies.
- Added `MoneyValue`, a minor-units money type intended for the next migration away from direct `double` storage in accounting paths.

Still recommended next:

- Create actual accounting journal entries for FX gain/loss on settlement.
- Migrate purchase, expense, supplier/customer balances to the same transaction/base currency structure.
- Replace sensitive ledger arithmetic paths with `MoneyValue` or a Decimal package end-to-end.
