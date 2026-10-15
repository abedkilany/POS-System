part of 'business_sqlite_store_impl.dart';

class _SqlFilter {
  const _SqlFilter({required this.whereSql, required this.variables});
  final String whereSql;
  final List<Variable<Object>> variables;
}

class _AccountBalanceSummary {
  const _AccountBalanceSummary(
      {required this.customerReceivables,
      required this.customerCredits,
      required this.supplierPayables,
      required this.supplierAdvances,
      required this.topCustomerDebts,
      required this.topSupplierDebts});
  final double customerReceivables;
  final double customerCredits;
  final double supplierPayables;
  final double supplierAdvances;
  final List<Map<String, Object?>> topCustomerDebts;
  final List<Map<String, Object?>> topSupplierDebts;
}
