import 'package:flutter_test/flutter_test.dart';

import 'package:ventio/models/product.dart';
import 'package:ventio/models/sale.dart';
import 'package:ventio/models/sale_item.dart';
import 'package:ventio/models/purchase.dart';
import 'package:ventio/models/purchase_item.dart';
import 'package:ventio/models/expense.dart';
import 'package:ventio/models/customer.dart';
import 'package:ventio/models/supplier.dart';
import 'package:ventio/models/stock_movement.dart';
import 'package:ventio/models/catalog_item.dart';
import 'package:ventio/models/store_profile.dart';
import 'package:ventio/core/utils/currency_utils.dart';

void main() {
  group('Product calculations and stock flags', () {
    test('calculates profit, margin, and inventory values', () {
      final product = Product(id: 'p1', name: 'Coffee', code: 'C001', price: 10, cost: 6, stock: 4, category: 'Drinks');

      expect(product.profit, 4);
      expect(product.marginPercent, 40);
      expect(product.stockCostValue, 24);
      expect(product.stockRetailValue, 40);
    });

    test('uses zero margin when price is zero', () {
      final product = Product(id: 'p1', name: 'Free sample', code: 'FREE', price: 0, cost: 4, stock: 2, category: 'Promo');
      expect(product.marginPercent, 0);
    });

    test('detects low stock only when stock tracking is enabled', () {
      final tracked = Product(id: 'p1', name: 'Tea', code: 'T001', price: 5, cost: 2, stock: 3, category: 'Drinks', lowStockThreshold: 3);
      final untracked = tracked.copyWith(trackStock: false);

      expect(tracked.isLowStock, isTrue);
      expect(untracked.isLowStock, isFalse);
    });

    test('keeps deleted state until explicitly cleared', () {
      final deletedAt = DateTime(2026, 1, 1);
      final product = Product(id: 'p1', name: 'Tea', code: 'T001', price: 5, cost: 2, stock: 3, category: 'Drinks', deletedAt: deletedAt);

      expect(product.copyWith(name: 'Green Tea').isDeleted, isTrue);
      expect(product.copyWith(clearDeletedAt: true).isDeleted, isFalse);
    });
  });

  group('Sale and sale item calculations', () {
    test('calculates sale item totals, costs, and profit', () {
      const item = SaleItem(productId: 'p1', productName: 'Coffee', unitPrice: 12.5, quantity: 3, unitCost: 7.5);

      expect(item.lineTotal, 37.5);
      expect(item.lineCost, 22.5);
      expect(item.lineProfit, 15);
    });

    test('calculates subtotal, total, and gross profit after discount', () {
      final sale = Sale(
        id: 's1',
        invoiceNo: 'INV-001',
        customerName: 'Walk-in Customer',
        date: DateTime(2026, 1, 2),
        status: 'Paid',
        discount: 5,
        items: const [
          SaleItem(productId: 'p1', productName: 'Coffee', unitPrice: 10, quantity: 2, unitCost: 4),
          SaleItem(productId: 'p2', productName: 'Tea', unitPrice: 5, quantity: 3, unitCost: 2),
        ],
      );

      expect(sale.subtotal, 35);
      expect(sale.total, 30);
      expect(sale.grossProfit, 16);
    });

    test('clamps sale total to zero when discount exceeds subtotal', () {
      final sale = Sale(id: 's1', invoiceNo: 'INV-001', customerName: 'A', date: DateTime(2026), status: 'Paid', items: const [SaleItem(productId: 'p1', productName: 'Item', unitPrice: 10, quantity: 1)], discount: 15);
      expect(sale.total, 0);
    });

    test('cancelled and returned sales contribute zero totals', () {
      final cancelled = Sale(id: 's1', invoiceNo: 'INV-001', customerName: 'A', date: DateTime(2026), status: 'Cancelled', items: const [SaleItem(productId: 'p1', productName: 'Item', unitPrice: 10, quantity: 1, unitCost: 4)], discount: 0);
      final returned = cancelled.copyWith(status: 'Returned');

      expect(cancelled.isCancelled, isTrue);
      expect(cancelled.total, 0);
      expect(cancelled.grossProfit, 0);
      expect(returned.isCancelled, isTrue);
    });

    test('deserializes legacy sale item cost aliases', () {
      final legacy = SaleItem.fromJson({'productId': 'p1', 'productName': 'Legacy', 'unitPrice': 9, 'quantity': 2, 'costPrice': 3});
      final snakeCase = SaleItem.fromJson({'productId': 'p2', 'productName': 'Legacy 2', 'unitPrice': 9, 'quantity': 2, 'unit_cost': 4});

      expect(legacy.unitCost, 3);
      expect(snakeCase.unitCost, 4);
    });
  });

  group('Purchase calculations', () {
    test('calculates purchase line total', () {
      const item = PurchaseItem(productId: 'p1', productName: 'Coffee Beans', quantity: 5, unitCost: 8);
      expect(item.lineTotal, 40);
    });

    test('calculates purchase subtotal and unit count', () {
      final purchase = Purchase(
        id: 'po1',
        purchaseNo: 'PO-001',
        supplierId: 'sup1',
        supplierName: 'Supplier',
        date: DateTime(2026, 1, 1),
        status: 'Draft',
        items: const [
          PurchaseItem(productId: 'p1', productName: 'Beans', quantity: 5, unitCost: 8),
          PurchaseItem(productId: 'p2', productName: 'Milk', quantity: 3, unitCost: 2),
        ],
      );

      expect(purchase.subtotal, 46);
      expect(purchase.totalUnits, 8);
      expect(purchase.isReceived, isFalse);
      expect(purchase.copyWith(status: 'Received').isReceived, isTrue);
      expect(purchase.copyWith(status: 'Cancelled').isCancelled, isTrue);
      expect(purchase.copyWith(status: 'Returned').isReturned, isTrue);
      expect(purchase.copyWith(status: 'Returned').subtotal, 0);
    });
  });

  group('Stock movement value', () {
    test('uses absolute quantity for stock value', () {
      final saleMovement = StockMovement(id: 'm1', productId: 'p1', productName: 'Coffee', type: 'sale', quantity: -3, date: DateTime(2026), unitCost: 4);
      final receiveMovement = saleMovement.copyWith(type: 'purchase_receive', quantity: 3);

      expect(saleMovement.value, 12);
      expect(receiveMovement.value, 12);
    });

    test('falls back to generated stock movement id for old payloads', () {
      final movement = StockMovement.fromJson({'productId': 'p1', 'type': 'sale', 'referenceId': 's1', 'quantity': -2});
      expect(movement.id, 's1-p1-sale');
    });
  });

  group('Catalog and profile helpers', () {
    test('chooses Arabic display name with English fallback', () {
      final item = CatalogItem(id: 'cat1', nameEn: 'Beverages', nameAr: 'مشروبات');
      final fallback = CatalogItem(id: 'cat2', nameEn: 'Snacks', nameAr: '');

      expect(item.displayName('ar'), 'مشروبات');
      expect(item.displayName('en'), 'Beverages');
      expect(fallback.displayName('ar'), 'Snacks');
    });

    test('loads default store profile values from partial json', () {
      final profile = StoreProfile.fromJson({});
      expect(profile.name, 'Ventio');
      expect(profile.currency, 'USD');
      expect(profile.footerNote, isNotEmpty);
    });

    test('formats supported and custom currencies consistently', () {
      expect(formatCurrency(12.5, currency: 'USD'), r'$12.50');
      expect(formatCurrency(12.5, currency: 'LBP'), 'LBP 12.50');
      expect(formatCurrency(12.5, currency: 'jpy'), 'JPY 12.50');
    });
  });

  group('Simple entity deletion flags', () {
    test('customer copyWith can clear soft delete marker', () {
      final customer = Customer(id: 'c1', name: 'Customer', phone: '1', address: 'A', deletedAt: DateTime(2026));
      expect(customer.isDeleted, isTrue);
      expect(customer.copyWith(clearDeletedAt: true).isDeleted, isFalse);
    });

    test('supplier copyWith can clear soft delete marker', () {
      final supplier = Supplier(id: 's1', name: 'Supplier', phone: '1', address: 'A', notes: '', deletedAt: DateTime(2026));
      expect(supplier.isDeleted, isTrue);
      expect(supplier.copyWith(clearDeletedAt: true).isDeleted, isFalse);
    });

    test('expense copyWith can clear soft delete marker', () {
      final expense = Expense(id: 'e1', title: 'Rent', category: 'Fixed', amount: 100, date: DateTime(2026), notes: '', deletedAt: DateTime(2026));
      expect(expense.isDeleted, isTrue);
      expect(expense.copyWith(clearDeletedAt: true).isDeleted, isFalse);
    });
  });
}
