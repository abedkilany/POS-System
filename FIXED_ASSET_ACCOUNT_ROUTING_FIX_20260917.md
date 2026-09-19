# Ventio 1.0.44 — Fixed Asset Account Routing Fix

Date: 2026-09-17

## Scope
Application code only. No user database was modified.

## Problem
The fixed-asset creation dialog allowed the posting account `1600 - الأصول الثابتة`, which is the parent/group account. As a result, a vehicle such as a Rapid could be posted to 1600 instead of the detailed `1640 - سيارات` account.

## Fix
- Removed `fixed_assets` (the parent 1600 account) from the asset-type choices.
- Replaced the accounting-account selector with a user-facing **Asset type / نوع الأصل** selector.
- Detailed fixed-asset types now map directly to their posting accounts:
  - 1610 — معدات وآلات
  - 1620 — أثاث وتجهيزات
  - 1630 — أجهزة وحواسيب
  - 1640 — سيارات
  - 1650 — أصول ثابتة أخرى
- The dialog shows the actual destination account as read-only information.
- The asset category stored with the asset is taken from the selected detailed account.
- Added service-level validation so `createFixedAsset` rejects the parent `fixed_assets` account even if a future caller tries to pass it directly.
- Cash-drawer purchase behavior, journal posting, and atomic transaction behavior were not changed.

## Expected example
Creating `رابيد`, selecting `سيارات`, and paying from the current drawer posts:

- Dr 1640 — سيارات
- Cr current cash-drawer account

The parent `1600 - الأصول الثابتة` cannot be selected for the asset posting.

## Validation
Structural assertions were run in the current environment. Flutter/Dart SDK is not installed here, so run `flutter analyze` locally after extraction.
