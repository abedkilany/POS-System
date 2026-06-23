# Temporary Sale Debug Dialog

Implemented a temporary diagnostic dialog in `lib/features/sales/sales_page.dart`.

## Behavior

When the cashier presses **Confirm Payment** and `createSale()` throws an exception, the app now shows a dialog instead of only a generic snackbar.

The dialog includes:

- User-facing error message
- Timestamp
- Screen/action
- Error type and error text
- Stack trace
- Device ID
- Payment method/status/currency
- Invoice totals
- Selected customer
- Cart item details including stock and auto-correction flags

The dialog has a **Copy** button to copy the full diagnostic text.

## Scope

This is intentionally temporary and does not implement the full audit/debug subsystem yet.
