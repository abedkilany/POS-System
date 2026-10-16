class ProductCostSnapshot {
  const ProductCostSnapshot({
    required this.productId,
    required this.currentInventoryUnitCost,
    required this.inventoryQuantity,
    required this.batchCount,
    required this.referenceUnitCost,
    this.lastPurchaseUnitCost,
    this.warehouseId = '',
  });

  final String productId;
  final double currentInventoryUnitCost;
  final double inventoryQuantity;
  final int batchCount;
  final double? lastPurchaseUnitCost;
  final double referenceUnitCost;
  final String warehouseId;

  bool get hasInventory => inventoryQuantity > 0.000001;
  bool get hasCurrentInventoryCost =>
      hasInventory && currentInventoryUnitCost >= 0;
}
