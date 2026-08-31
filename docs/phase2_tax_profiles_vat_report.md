# Ventio Phase 2 — Tax Profiles & VAT

## Status
Implementation complete in code and ready for release verification with `flutter analyze` and the Flutter test suite.

## Tax model
- Added store-level `TaxProfile` definitions with explicit treatments:
  - standard-rated VAT,
  - zero-rated,
  - exempt,
  - out-of-scope.
- The standard VAT rate remains configurable.
- Product master data now carries `taxProfileId` and validates that an explicitly assigned profile is active.
- Products without an explicit assignment use the store default tax profile.
- A tax profile that is still referenced by an active product cannot be removed or deactivated silently.
- Existing legacy stores remain compatible with the former `default_vat_rate_percent` setting until tax configuration is explicitly migrated.

## Pricing and calculation policy
- Ventio keeps its existing tax-inclusive retail/catalog pricing policy.
- VAT is extracted from the amount actually charged, after document discount allocation.
- Document discounts are distributed proportionally across lines at currency precision.
- Standard VAT lines freeze taxable base and VAT amount.
- Zero-rated/exempt/out-of-scope lines freeze their legal treatment with zero tax.
- Mixed-tax invoices and purchases are supported line-by-line.

## Posted-document immutability
- Posted snapshot schema is now v2 for tax facts.
- Every posted line freezes:
  - tax profile id,
  - tax code,
  - tax treatment/mode,
  - tax rate,
  - line discount,
  - taxable base,
  - tax amount.
- Posted totals freeze total VAT.
- Changing the current VAT rate or product profile later does not change old invoices or their accounting meaning.
- Legacy backfill remains conservative: it never invents missing historical VAT facts and is marked with `legacyBackfill` / `taxMode = none`.

## Sales accounting
- Output VAT is posted from the frozen posted snapshot when available.
- Sales revenue and sales discounts are derived from the same frozen line-level tax facts.
- Legacy documents without v2 tax facts retain the previous global-rate fallback only for compatibility.

## Purchase accounting
- Input VAT is posted from the frozen purchase snapshot.
- Inventory is debited at the line-level net-of-recoverable-VAT amount for taxed lines.
- Exempt/zero-rated lines retain their correct line carrying amount.
- Mixed taxed/exempt purchase invoices are therefore not allocated using one blended invoice VAT rate.

## Returns and reversals
- Sale returns reuse the original posted line tax facts whenever the original line can be resolved.
- A later change to the VAT rate does not change the VAT reversed by a return.
- Partial returns preserve original VAT proportion and derive the returned taxable base from returned gross minus VAT, preventing one-minor-unit journal imbalances caused by independent rounding.
- Purchase cancellations/returns continue to reverse the original posted journal, which reverses the exact frozen input VAT previously posted.

## Persistence and migration
- SQLite schema version is 29.
- `products.tax_profile_id` is added idempotently.
- Product SQLite read/write paths persist the tax profile id.
- Store-profile JSON/sync/backup data includes tax profiles, default profile id, and tax configuration version.

## UI and legal document rendering
- Accounting settings expose the configured tax profiles, standard VAT rate, and default tax profile.
- Product editing exposes tax-profile assignment.
- Sale and purchase PDFs show seller VAT/tax registration identity when configured.
- Posted PDFs show line tax treatment, net-before-VAT, and VAT totals using frozen snapshot values.
- Thermal sale output shows the same frozen VAT summary and tax registration identity.
- Arabic, English, and French strings were added for the new tax-profile UI.

## Regression coverage added
`test/phase2_tax_profiles_vat_test.dart` covers:
- inclusive VAT calculation,
- zero-rated and exempt behavior,
- mixed-tax sales,
- discount allocation precision,
- accounting immutability after VAT-rate changes,
- mixed-tax purchase/input VAT posting,
- return VAT based on the original posted invoice,
- conservative legacy backfill,
- StoreProfile/Product JSON round-trip,
- SQLite product tax-profile round-trip,
- schema 29 tax column.

## Release verification required
Run on the project workstation:

```powershell
flutter analyze 2>&1 | Tee-Object -FilePath analyze_phase2.txt
flutter test -r expanded 2>&1 | Tee-Object -FilePath test_phase2.txt
```

Phase 2 should be marked **CLOSED** only after these commands pass, consistent with the verification policy used for the previous phases.
