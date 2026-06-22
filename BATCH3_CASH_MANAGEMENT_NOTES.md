# Batch 3 - Cash Management Reports & Finalization

Implemented on top of Batch 2.

## Added service-level reports

- `AccountingService.listCashBalancesReport()`
  - Shows every cash location with current balance, account, parent, branch/device hints, and negative-balance policy.
- `AccountingService.listOpenCashDrawersReport()`
  - Shows currently open drawer sessions with opening balance, expected/current balance, opening time, user and branch.
- `AccountingService.listCashDrawerVarianceReport()`
  - Shows closed drawer sessions ordered by largest variance, with expected cash, counted cash, and difference.
- `AccountingService.listCashTransferAuditReport()`
  - Shows recent cash transfers with from/to locations, amount, status, creator/approver and linked journal entry.

## Added UI sections

Inside Advanced Accounting:

- Cash Monitoring
- Open Cash Drawers
- Cash Drawer Variance
- Cash Transfer Audit

These sit above the raw cash locations/transfers/session lists so managers get an operational dashboard before inspecting raw records.

## Added localization keys

Arabic and English keys were added for:

- cash_monitoring
- open_cash_drawers_report
- cash_drawer_variance_report
- cash_transfer_audit_report
- main_vault
- branch_vault
- overage
- shortage
- balanced

## Scope note

This batch focuses on reports, monitoring and final operational visibility. It does not redesign the sales UI or add new permission entities beyond reusing the existing accounting management permission gate already used by the advanced accounting controls.

## Validation note

The sandbox used for this change does not include Dart/Flutter, so `dart analyze` / `flutter analyze` could not be executed here. Please run locally after extracting:

```bash
flutter pub get
flutter analyze
flutter test
```
