import '../../models/product_costing.dart';
import '../../models/inventory_cost_layer.dart';
import '../../models/sale_item.dart';

/// Owns validation and normalization rules shared by posted sale workflows.
/// SQLite posting and its stock/accounting transaction remain at the data edge.
class SaleWorkflowService {
  const SaleWorkflowService();

  double validateCreate({
    required List<SaleItem> items,
    required double discount,
    required bool Function(String productId) productExists,
  }) {
    if (items.isEmpty) {
      throw ArgumentError('Sale must contain at least one item.');
    }
    final cleanedDiscount = discount.isFinite ? discount : 0.0;
    if (cleanedDiscount < 0) {
      throw ArgumentError('Discount cannot be negative.');
    }
    final subtotal = items.fold<double>(0, (sum, item) => sum + item.lineTotal);
    if (cleanedDiscount > subtotal) {
      throw ArgumentError('Discount cannot be greater than subtotal.');
    }
    for (final item in items) {
      if (item.quantity <= 0 || item.unitPrice < 0) {
        throw ArgumentError('Invalid sale item values.');
      }
      if (!productExists(item.productId)) {
        throw ArgumentError('Product not found: ${item.productName}');
      }
    }
    return cleanedDiscount;
  }

  List<SaleItem> prepareItems(
    Iterable<SaleItem> items, {
    required InventoryCostingMethod costingMethod,
  }) =>
      items
          .map(
            (item) => SaleItem(
              productId: item.productId,
              productName: item.productName,
              unitPrice: item.unitPrice,
              quantity: item.quantity,
              unitName: item.unitName,
              baseQuantity: item.effectiveBaseQuantity,
              conversionToBase: item.conversionToBase,
              // Cost is finalized inside the authoritative SQLite transaction.
              unitCost: item.unitCost,
              costingMethodAtSale: costingMethod,
              costCurrency: item.costCurrency,
              costExchangeRate: 1,
              costLayerConsumptions: const <InventoryCostLayerConsumption>[],
            ),
          )
          .toList(growable: false);

  SaleInitialPaymentPlan prepareInitialPayment({
    required String customerId,
    required String customerName,
    required String paymentMethod,
    required String paymentStatus,
    required double saleTotalInInvoiceCurrency,
    required double? cashReceivedAmount,
    required String walkInCustomerId,
    required String walkInCustomerName,
  }) {
    final normalizedCustomerId =
        customerId.trim().isEmpty ? walkInCustomerId : customerId.trim();
    final normalizedCustomerName =
        customerName.trim().isEmpty ? walkInCustomerName : customerName.trim();
    final normalizedPaymentMethod =
        paymentMethod.trim().isEmpty ? 'Cash' : paymentMethod.trim();
    final isWalkInSale = normalizedCustomerId == walkInCustomerId ||
        normalizedCustomerName.toLowerCase() ==
            walkInCustomerName.toLowerCase();
    if (isWalkInSale && normalizedPaymentMethod == 'Credit') {
      throw ArgumentError('Walk-in customer sales cannot be credit.');
    }
    final normalizedCashReceived = (cashReceivedAmount ??
            (normalizedPaymentMethod == 'Cash'
                ? saleTotalInInvoiceCurrency
                : 0.0))
        .clamp(0, saleTotalInInvoiceCurrency)
        .toDouble();
    final requestedStatus = paymentStatus.trim().toLowerCase();
    final normalizedPaymentStatus = normalizedPaymentMethod == 'Credit'
        ? (normalizedCashReceived > 0 ? 'partial' : 'credit')
        : (requestedStatus == 'credit'
            ? 'credit'
            : requestedStatus == 'partial'
                ? 'partial'
                : 'paid');
    final normalizedPaidAmount = normalizedPaymentMethod == 'Credit'
        ? normalizedCashReceived
        : saleTotalInInvoiceCurrency;
    final initialPaymentMethod =
        normalizedPaymentMethod == 'Credit' && normalizedCashReceived > 0
            ? 'Cash'
            : normalizedPaymentMethod;
    return SaleInitialPaymentPlan(
      customerId: normalizedCustomerId,
      customerName: normalizedCustomerName,
      paymentMethod: normalizedPaymentMethod,
      paymentStatus: normalizedPaymentStatus,
      cashReceivedAmount: normalizedCashReceived,
      paidAmount: normalizedPaidAmount,
      initialPaymentMethod: initialPaymentMethod,
    );
  }
}

class SaleInitialPaymentPlan {
  const SaleInitialPaymentPlan({
    required this.customerId,
    required this.customerName,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.cashReceivedAmount,
    required this.paidAmount,
    required this.initialPaymentMethod,
  });

  final String customerId;
  final String customerName;
  final String paymentMethod;
  final String paymentStatus;
  final double cashReceivedAmount;
  final double paidAmount;
  final String initialPaymentMethod;
}
