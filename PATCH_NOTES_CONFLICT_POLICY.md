# Conflict Policy Patch

This patch changes conflict handling to match the requested behavior:

## Core rule
- Record `id` remains the only real identity.
- Sync never merges, deletes, hides, or auto-renames records just because names/codes match.
- Local entry still blocks obvious duplicates on the same device.
- Duplicates created offline on different devices are preserved after sync and reported as data conflicts.

## Changed behavior

### Customers
- Removed name-based de-duplication from `_normalizeCustomers()`.
- `Manal / phone 1`, `Manal / phone 2`, and `Manal / phone 3` stay as separate records if they have different IDs.
- Local add/update blocks another active customer with the same name on the same device.
- After sync, duplicate customer names appear in Settings → Data conflicts.

### Suppliers
- Added local duplicate-name prevention.
- Duplicate supplier names arriving from sync are preserved and reported.

### Products
- Product ID remains the identity.
- Existing local code/barcode validation remains.
- Removed silent auto-renumbering of duplicate product codes in migration logic.
- Duplicate product code/barcode after sync is reported as a blocking conflict.
- Barcode/code lookup returns no product when the code/barcode is ambiguous, preventing accidental sale of the wrong product.

### Catalog: categories, brands, units
- Existing local duplicate-name prevention remains.
- Duplicate names arriving from sync are preserved and reported.

### Users and roles
- Existing local duplicate username/role checks remain.
- Duplicate usernames/roles from sync are reported as blocking conflicts.
- Login refuses ambiguous duplicated active usernames instead of guessing which account to use.

### Sales / invoices
- Invoices are never merged.
- Duplicate invoice numbers after sync are reported as blocking conflicts.

## UI
- Added Settings → Data conflicts card.
- Shows total conflicts, blocking conflicts, affected keys, and record IDs.
- The app does not auto-resolve conflicts; users must edit/rename the relevant records manually.
