# Ventio — Accounting compact layout fix — 2026-09-17

## Scope
UI-only cleanup of the Accounting page. No accounting logic, posting logic, balances, reports, database schema, or calculations were changed.

## Changes
- Removed the accounting summary/KPI strip from the top of the Accounting page.
- Reduced desktop Accounting page margins from the generic 24 px to 16 px horizontal / 10 px vertical.
- Compacted the Accounting page header and refresh control.
- Rebuilt the five main Accounting tabs as compact horizontal icon + label tabs.
  - Height: 40 px.
  - Label font: 12 px.
  - Reduced label padding.
- Compacted all second-level Accounting group tabs (accounts, operations, cash, reports, administration).
  - Height: 38 px.
  - Label font: 11.5 px.
  - Icon + label shown on one row.
- Reduced padding/font footprint of the report-period bar.

## Expected result
On desktop screens such as 1366x768, substantially more vertical space is available for the actual accounting tables and reports (trial balance, income statement, balance sheet, etc.).

## Validation
- Delimiter/bracket structural check passed for the modified Dart source.
- Flutter/Dart SDK is not installed in the execution environment, so run `flutter analyze` locally before build/release.
