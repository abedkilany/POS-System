# Sale save error message fix

## Problem
When a cash sale failed because the current device had no linked/open cash drawer shift, the POS page caught the exception with `catch (_)` and always showed the generic stock/quantity/discount validation message.

This made it look like automatic stock correction was broken, even though `AppStore.createSale()` already contains the auto-correction flow for zero stock.

## Fix
Updated `lib/features/sales/sales_page.dart`:

- Replaced the generic sale-save `catch (_)` with `catch (error)`.
- Added `_saleSaveFailureMessage(...)` to distinguish drawer/device/shift errors from real validation errors.
- Drawer/device/shift errors now show the real message from `AppStore.createSale()`.
- Generic validation errors still show `sale_validation_failed`.

## Result
If the sale fails because no cash drawer shift is open for the current device, the user now sees the correct reason instead of the misleading stock message.

Example:

> لا توجد وردية نقدية مفتوحة لهذا الجهاز. افتح وردية قبل قبول الدفع النقدي.

