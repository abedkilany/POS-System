import '../models/customer.dart';
import '../models/expense.dart';
import '../models/product.dart';
import '../models/sale.dart';
import '../models/sale_item.dart';
import '../models/supplier.dart';

class MockData {
  static final products = [
    Product(id: 'p1', name: 'Mineral Water', code: 'MW-001', price: 1.5, cost: 0.8, stock: 42, category: 'Beverages'),
    Product(id: 'p2', name: 'Potato Chips', code: 'SN-201', price: 2.25, cost: 1.2, stock: 18, category: 'Snacks'),
    Product(id: 'p3', name: 'Chocolate Bar', code: 'SN-305', price: 1.75, cost: 0.95, stock: 9, category: 'Snacks'),
    Product(id: 'p4', name: 'Dish Soap', code: 'HM-101', price: 4.5, cost: 3.0, stock: 6, category: 'Home Care'),
    Product(id: 'p5', name: 'Tissues Pack', code: 'HM-220', price: 3.0, cost: 1.9, stock: 27, category: 'Home Care'),
  ];

  static final customers = [
    Customer(id: 'c1', name: 'Walk-in Customer', phone: '', address: ''),
    Customer(id: 'c2', name: 'Nour Haddad', phone: '+96170000111', address: 'Beirut'),
    Customer(id: 'c3', name: 'Karim Nader', phone: '+96170000222', address: 'Tripoli'),
  ];

  static final suppliers = [
    Supplier(id: 's1', name: 'Fresh Trade Co.', phone: '+96170001010', address: 'Beirut Warehouse', notes: 'Main beverage supplier'),
    Supplier(id: 's2', name: 'Daily Retail Supply', phone: '+96170002020', address: 'Zahle', notes: 'Snacks and grocery items'),
  ];

  static final sales = [
    Sale(
      id: 'sale1',
      invoiceNo: 'INV-0001',
      customerName: 'Walk-in Customer',
      date: DateTime.now().subtract(const Duration(hours: 3)),
      status: 'Paid',
      discount: 0,
      items: const [
        SaleItem(productId: 'p1', productName: 'Mineral Water', unitPrice: 1.5, quantity: 4),
        SaleItem(productId: 'p2', productName: 'Potato Chips', unitPrice: 2.25, quantity: 2),
      ],
    ),
    Sale(
      id: 'sale2',
      invoiceNo: 'INV-0002',
      customerName: 'Nour Haddad',
      date: DateTime.now().subtract(const Duration(days: 1, hours: 2)),
      status: 'Paid',
      discount: 1,
      items: const [
        SaleItem(productId: 'p5', productName: 'Tissues Pack', unitPrice: 3.0, quantity: 3),
      ],
    ),
  ];

  static final expenses = [
    Expense(
      id: 'e1',
      title: 'Electricity Bill',
      category: 'Utilities',
      amount: 55,
      date: DateTime.now().subtract(const Duration(days: 2)),
      notes: 'Monthly payment',
    ),
    Expense(
      id: 'e2',
      title: 'Delivery Fuel',
      category: 'Transport',
      amount: 20,
      date: DateTime.now().subtract(const Duration(days: 1)),
      notes: 'Store pickup run',
    ),
  ];
}
