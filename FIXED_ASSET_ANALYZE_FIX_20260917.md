# Fixed Asset Analyze Fix — 2026-09-17

## Issue
`flutter analyze` reported one `use_build_context_synchronously` info in `lib/features/accounting/accounting_page.dart` after the fixed-asset creation dialog.

## Fix
Added an immediate `if (!mounted) return;` guard after the dialog completes and before the first subsequent use of `context`.

## Scope
No accounting, cash drawer, fixed asset, journal, or database logic was changed by this follow-up patch.
