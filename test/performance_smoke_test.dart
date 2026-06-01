import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/models/product.dart';
import 'package:ventio/models/sale.dart';
import 'package:ventio/models/sale_item.dart';

void main() {
  group('Performance smoke tests', () {
    test('calculates totals for a large invoice within a small budget', () {
      final items = List<SaleItem>.generate(
        1000,
        (index) => SaleItem(productId: 'p$index', productName: 'Item $index', unitPrice: 3.5, quantity: 2, unitCost: 1.25),
      );
      final sale = Sale(id: 's1', invoiceNo: 'INV-PERF', customerName: 'Customer', date: DateTime(2026), status: 'Paid', discount: 0, items: items);

      final stopwatch = Stopwatch()..start();
      final subtotal = sale.subtotal;
      final total = sale.total;
      final grossProfit = sale.grossProfit;
      stopwatch.stop();

      expect(subtotal, 7000);
      expect(total, 7000);
      expect(grossProfit, 4500);
      expect(stopwatch.elapsedMilliseconds, lessThan(100));
    });

    test('filters low stock products at realistic catalog scale', () {
      final products = List<Product>.generate(
        5000,
        (index) => Product(id: 'p$index', name: 'Product $index', code: 'SKU-$index', price: 10, cost: 6, stock: index % 10, category: 'General', lowStockThreshold: 3),
      );

      final stopwatch = Stopwatch()..start();
      final lowStock = products.where((product) => product.isLowStock).toList();
      stopwatch.stop();

      expect(lowStock.length, 2000);
      expect(stopwatch.elapsedMilliseconds, lessThan(100));
    });
  });
}
