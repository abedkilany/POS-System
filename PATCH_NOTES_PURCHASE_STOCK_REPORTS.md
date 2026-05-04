# Purchase / Stock Movement / Reports Patch

## Added
- Purchase module screen in the main navigation.
- New purchase models: `Purchase`, `PurchaseItem`.
- Persistent stock movement model: `StockMovement`.
- Purchase workflow:
  - Create draft or received purchase.
  - Receive draft purchase later.
  - Cancel purchase and reverse stock when needed.
- Stock movement system:
  - Sale decrement.
  - Sale restore on invoice cancellation.
  - Purchase receive.
  - Purchase cancellation reversal.
  - Manual stock adjustment from Inventory.
- Inventory page tabs:
  - Overview.
  - Stock movements.
- Reports page additions:
  - Monthly purchases.
  - Stock in/out summary.
  - Recent stock movements.

## Data keys added
- `purchases_v1`
- `stock_movements_v1`
- `purchase_counter_v1`

## Sync/backup additions
- Purchases and stock movements are included in backup/snapshot payloads.
- Purchase and stock movement events are added to the existing sync-change pipeline.

## Notes
- This patch keeps the existing local/LAN/cloud architecture.
- Flutter build was not executed in this environment because Flutter/Dart SDK is unavailable here.
