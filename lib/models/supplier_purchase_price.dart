class SupplierPurchasePrice {
  const SupplierPurchasePrice({
    required this.productId,
    required this.productName,
    required this.supplierId,
    required this.supplierName,
    required this.unitCost,
    required this.quantity,
    required this.purchaseId,
    required this.purchaseNo,
    required this.date,
  });

  final String productId;
  final String productName;
  final String supplierId;
  final String supplierName;
  final double unitCost;
  final double quantity;
  final String purchaseId;
  final String purchaseNo;
  final DateTime date;
}
