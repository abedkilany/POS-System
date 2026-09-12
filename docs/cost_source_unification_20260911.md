# Ventio Cost Source Unification — 2026-09-11

## Final cost meanings

- **Current inventory cost**: weighted average of the positive physical Unified Batch balances currently on hand. It is derived from `inventory_batch_balances.quantity × inventory_batches.unit_cost` and is read-only.
- **Last purchase cost**: unit cost of the latest still-effective purchase receipt. Fully reversed purchase receipts are ignored.
- **Reference cost**: user-maintained product cost (`Product.cost` / `usdCost` / `originalCost`). It is a fallback/reference only and is no longer overwritten by purchase receipts or manufacturing output.
- **Supplier cost**: remains supplier-specific purchase guidance and is not an inventory valuation source until a purchase is actually received.

## Sales

Posted sales continue to use the exact Unified Batch allocations as authoritative COGS. The payment/profit preview now estimates the same batch allocation for the selected warehouse and requested quantity instead of relying on the product reference cost.

## Manufacturing

Manufacturing consumes the actual raw-material Unified Batches. Output unit cost is derived from the actual consumed material value divided by output quantity and is stored on the produced Unified Batch. Manufacturing no longer overwrites the finished product's user-maintained reference cost.

## Dashboard and products

Inventory value on the dashboard is derived from positive physical batch balances and excludes virtual negative-stock deficit batches. The Products UI exposes Current inventory cost, Last purchase cost, and Reference cost separately.

## Compatibility

Legacy `ProductCost.averageCost` / `lastCost` records remain for compatibility and fallback paths, but Unified Batch is the authority for stock valuation and stock-tracked COGS.
