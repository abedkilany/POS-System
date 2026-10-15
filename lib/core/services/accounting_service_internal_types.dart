part of 'accounting_service_impl.dart';

class _InventoryAmount {
  const _InventoryAmount(this.productId, this.amount);
  final String productId;
  final double amount;
}

class _CashLocationSnapshot {
  const _CashLocationSnapshot(
      {required this.id,
      required this.name,
      required this.type,
      required this.accountId});
  final String id;
  final String name;
  final String type;
  final String accountId;
}

class _FrozenAccountingTax {
  const _FrozenAccountingTax(
      {required this.netAmount,
      required this.taxAmount,
      required this.grossNetBeforeDiscount});
  final double netAmount;
  final double taxAmount;
  final double grossNetBeforeDiscount;
}

class _TaxBreakdown {
  const _TaxBreakdown(
      {required this.netAmount,
      required this.taxAmount,
      required this.grossAmount,
      required this.ratePercent});
  final double netAmount;
  final double taxAmount;
  final double grossAmount;
  final double ratePercent;
}
