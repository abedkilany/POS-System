import '../../models/customer.dart';
import '../../models/expense.dart';
import '../../models/purchase.dart';
import '../../models/sale.dart';
import '../../models/supplier.dart';

/// Read-only commerce list projections used by the data adapter and typed port.
class CommerceReadService {
  const CommerceReadService();

  List<Customer> activeCustomers(Iterable<Customer> customers) =>
      List<Customer>.unmodifiable(customers.where((item) => !item.isDeleted));

  List<Supplier> activeSuppliers(Iterable<Supplier> suppliers) =>
      List<Supplier>.unmodifiable(suppliers.where((item) => !item.isDeleted));

  List<Sale> activeSalesNewestFirst(Iterable<Sale> sales) =>
      List<Sale>.unmodifiable(
        sales.where((item) => !item.isDeleted).toList(growable: false).reversed,
      );

  List<Purchase> activePurchasesNewestFirst(Iterable<Purchase> purchases) =>
      List<Purchase>.unmodifiable(
        purchases
            .where((item) => !item.isDeleted)
            .toList(growable: false)
            .reversed,
      );

  List<Expense> activeExpensesNewestFirst(Iterable<Expense> expenses) =>
      List<Expense>.unmodifiable(
        expenses
            .where((item) => !item.isDeleted)
            .toList(growable: false)
            .reversed,
      );
}
