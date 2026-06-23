# Cash Rounding Update

Implemented professional per-currency cash rounding settings.

## What changed

- Each currency now supports:
  - cash rounding enabled/disabled (enabled when increment > 0)
  - cash rounding increment, e.g. `1000` for LBP
  - cash rounding method:
    - `nearest`
    - `up`
    - `down`

## Accounting behavior

The currency keeps its accounting decimals separately from cash rounding.
Cash rounding is applied only through cash-normalization helpers, not as the only stored accounting value.

## Files changed

- `lib/models/store_profile.dart`
- `lib/core/utils/currency_utils.dart`
- `lib/core/services/invoice_pdf_service.dart`
- `lib/features/settings/settings_page.dart`
- `assets/translations/ar.json`
- `assets/translations/en.json`

## Example for LBP

For Lebanese Pound:

- Accounting decimals: `0`
- Cash decimals: `0`
- Enable cash rounding: `true`
- Increment: `1000`
- Method: `nearest`

Examples:

- `89,123` → `89,000` using nearest 1,000
- `89,123` → `90,000` using up 1,000
- `89,123` → `89,000` using down 1,000
