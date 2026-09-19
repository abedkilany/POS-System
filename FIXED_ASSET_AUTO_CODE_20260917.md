# Ventio 1.0.44+44 — Fixed Asset Automatic Code

Date: 2026-09-17

## Change
- Removed the manual `code` field from the fixed asset creation dialog.
- The UI now passes an empty code intentionally.
- `AccountingService.createFixedAsset` automatically generates a unique internal code when none is supplied.
- Automatic code generation now uses UTC microseconds (`FA-<microseconds>`) to reduce collision risk.
- No accounting, cash drawer, journal-entry, depreciation, or asset-payment behavior was changed by this patch.

## User flow
The user only enters the asset name, category, purchase value, useful life, acquisition date, fixed-asset account, payment method, and notes. The asset code requires no user input.
