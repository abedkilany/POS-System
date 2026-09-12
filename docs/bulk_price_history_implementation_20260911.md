# Ventio — Bulk Price Adjustment + Product Price History

Date: 2026-09-11

## Implemented

- Multi-select products from the Products page, including select/clear displayed rows.
- Bulk price adjustment dialog with:
  - Increase or decrease.
  - Percentage input.
  - Target price: Retail, Wholesale, or Wholesale Bulk.
  - Preview before commit.
  - Missing-price and unchanged-after-rounding counts.
- Atomic SQLite bulk update for product prices and their history rows.
- Retail bulk changes also keep the legacy Product retail-price fields synchronized.
- Product price history stores old/new price, currency, price list, unit, percentage, change type, source, batch id, user, and timestamp.
- Manual price changes through the existing price setters are also recorded in price history.
- Per-product Price History dialog in the Products page.
- Audit entry for every bulk price operation.
- Price history included in SQLite schema, backup/restore, unified snapshots, and client snapshot replacement.

## Database

- Added `product_price_history` typed business table.
- SQLite schema version: 34.

## Validation performed in this environment

- Static delimiter/syntax-structure checks on all modified Dart files.
- Cross-reference review of model/repository/service/storage/UI wiring.
- Archive integrity check is performed when packaging the deliverable.

`flutter analyze` / Flutter tests were not executable in the current container because Flutter/Dart SDK is not installed here. They should be run in the normal Ventio development environment before production release.
