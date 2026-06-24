Ventio pricing/costing phase completion review
=============================================

Implemented completion items on top of Ventio_11_pricing_phase3(2):

1. Product pricing / overrides
- ProductPriceOverride is now used by pricing resolution.
- Added productPriceOverrideFor(...) and productPriceAmountForCurrency(...).
- defaultProductUsdPrice(...) now respects a fixed/manual override in the store default sale invoice currency before falling back to base ProductPrice conversion.
- Added setProductPriceOverride(...) and removeProductPriceOverride(...) APIs for managing fixed currency overrides.
- ProductPrice / ProductPriceOverride / PriceList persistence is included in product dirty saves and SQLite hot-path saves.

2. Costing method settings
- Added Inventory Costing Method card in financial settings.
- User can switch between Weighted Average, FIFO, and Last Purchase Cost.
- Changes go through AppStore.setInventoryCostingMethod(...), preserving CostingMethodHistory with effective dates.

3. FIFO / inventory cost layers completion
- Added generic _addInventoryCostLayerFromStockIncrease(...) for non-purchase positive stock sources.
- Positive inventory count adjustments now create InventoryCostLayer entries.
- Manufacturing output now creates InventoryCostLayer entries.
- Purchase return/cancel now prevents FIFO reversal if layers from that purchase were already consumed by sales, avoiding silently corrupting historical COGS/layers.

Notes
- flutter analyze was not run in this environment because Flutter/Dart is not installed here.
- The implementation keeps legacy Product.price/cost fields for UI/backward compatibility, but active pricing/costing now resolves through the new phase 1/2/3 structures.
