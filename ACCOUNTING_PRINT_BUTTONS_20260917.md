# Ventio 44 - Accounting print buttons
Date: 2026-09-17

## Scope
Added a compact print action to every nested page/report inside Accounting without changing accounting calculations or report queries.

Covered views (19):
- Customers
- Suppliers
- Aging reports
- Recent transactions
- Journal entries
- General ledger
- Chart of accounts
- Cash movements
- Cash control
- Cash & bank
- Trial balance
- Income statement
- Balance sheet
- Cash-flow statement
- Tax report
- Inventory/manufacturing report
- Accounting administration
- Account mapping
- Accounting settings

## UI behavior
- A small tonal print icon is overlaid in the top-end corner of each active page.
- It does not consume an additional toolbar row, preserving the compact accounting layout.
- The print icon itself is excluded from the captured printable area.

## Printing behavior
- Captures the currently rendered accounting page/report and sends it to the existing system print/PDF dialog.
- Uses A4 landscape for wide content and A4 portrait for taller content.
- No accounting data, posting, balances, or report calculations were changed.

## Validation note
The working environment does not provide Flutter/Dart SDK, so run `flutter analyze` locally after extraction.
