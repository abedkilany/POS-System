import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/services/commerce_read_service.dart';
import 'package:ventio/models/customer.dart';
import 'package:ventio/models/expense.dart';
import 'package:ventio/models/purchase.dart';
import 'package:ventio/models/sale.dart';
import 'package:ventio/models/supplier.dart';

void main() {
  const service = CommerceReadService();
  final date = DateTime(2026, 1, 1);

  test('keeps active party rows in source order and returns immutable lists',
      () {
    final customers = <Customer>[
      Customer(id: 'c1', name: 'One', phone: '', address: ''),
      Customer(
        id: 'deleted',
        name: 'Deleted',
        phone: '',
        address: '',
        deletedAt: date,
      ),
      Customer(id: 'c2', name: 'Two', phone: '', address: ''),
    ];
    final suppliers = <Supplier>[
      Supplier(id: 's1', name: 'One', phone: '', address: '', notes: ''),
      Supplier(
        id: 'deleted',
        name: 'Deleted',
        phone: '',
        address: '',
        notes: '',
        deletedAt: date,
      ),
      Supplier(id: 's2', name: 'Two', phone: '', address: '', notes: ''),
    ];

    final activeCustomers = service.activeCustomers(customers);
    final activeSuppliers = service.activeSuppliers(suppliers);
    expect(activeCustomers.map((item) => item.id), <String>['c1', 'c2']);
    expect(activeSuppliers.map((item) => item.id), <String>['s1', 's2']);
    expect(() => activeCustomers.add(customers.first), throwsUnsupportedError);
    expect(() => activeSuppliers.add(suppliers.first), throwsUnsupportedError);
  });

  test('filters deleted documents and keeps newest-first ordering', () {
    final sales = <Sale>[
      Sale(
        id: 'sale-1',
        invoiceNo: '1',
        customerName: 'Customer',
        date: date,
        status: 'Posted',
        items: const [],
        discount: 0,
      ),
      Sale(
        id: 'deleted-sale',
        invoiceNo: '2',
        customerName: 'Customer',
        date: date,
        status: 'Posted',
        items: const [],
        discount: 0,
        deletedAt: date,
      ),
      Sale(
        id: 'sale-2',
        invoiceNo: '3',
        customerName: 'Customer',
        date: date,
        status: 'Posted',
        items: const [],
        discount: 0,
      ),
    ];
    final purchases = <Purchase>[
      Purchase(
        id: 'purchase-1',
        purchaseNo: '1',
        supplierId: 'supplier',
        supplierName: 'Supplier',
        date: date,
        status: 'Posted',
        items: const [],
      ),
      Purchase(
        id: 'deleted-purchase',
        purchaseNo: '2',
        supplierId: 'supplier',
        supplierName: 'Supplier',
        date: date,
        status: 'Posted',
        items: const [],
        deletedAt: date,
      ),
      Purchase(
        id: 'purchase-2',
        purchaseNo: '3',
        supplierId: 'supplier',
        supplierName: 'Supplier',
        date: date,
        status: 'Posted',
        items: const [],
      ),
    ];
    final expenses = <Expense>[
      Expense(
        id: 'expense-1',
        title: 'One',
        category: 'Office',
        amount: 1,
        date: date,
        notes: '',
      ),
      Expense(
        id: 'deleted-expense',
        title: 'Deleted',
        category: 'Office',
        amount: 1,
        date: date,
        notes: '',
        deletedAt: date,
      ),
      Expense(
        id: 'expense-2',
        title: 'Two',
        category: 'Office',
        amount: 2,
        date: date,
        notes: '',
      ),
    ];

    expect(
      service.activeSalesNewestFirst(sales).map((item) => item.id),
      <String>['sale-2', 'sale-1'],
    );
    expect(
      service.activePurchasesNewestFirst(purchases).map((item) => item.id),
      <String>['purchase-2', 'purchase-1'],
    );
    expect(
      service.activeExpensesNewestFirst(expenses).map((item) => item.id),
      <String>['expense-2', 'expense-1'],
    );
  });
}
