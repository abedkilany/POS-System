import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/utils/currency_utils.dart';
import '../../data/app_store.dart';
import '../../widgets/report_card.dart';

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final totalExpenses = store.totalExpensesAmount;
    final estimatedProfit = store.estimateProfit();
    final activeSales = store.sales.where((sale) => !sale.isCancelled).toList();
    final today = DateTime.now();
    final todaySales = activeSales.where((sale) => sale.date.year == today.year && sale.date.month == today.month && sale.date.day == today.day).fold<double>(0, (sum, sale) => sum + sale.total);
    final monthSales = activeSales.where((sale) => sale.date.year == today.year && sale.date.month == today.month).fold<double>(0, (sum, sale) => sum + sale.total);
    final monthPurchases = store.purchases.where((purchase) => !purchase.isCancelled && purchase.date.year == today.year && purchase.date.month == today.month).fold<double>(0, (sum, purchase) => sum + purchase.subtotal);
    final movementIn = store.stockMovements.where((item) => item.quantity > 0).fold<int>(0, (sum, item) => sum + item.quantity);
    final movementOut = store.stockMovements.where((item) => item.quantity < 0).fold<int>(0, (sum, item) => sum + item.quantity.abs());
    final topProducts = <String, int>{};
    for (final sale in activeSales) {
      for (final item in sale.items) {
        topProducts[item.productName] = (topProducts[item.productName] ?? 0) + item.quantity;
      }
    }
    final topProductLines = topProducts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final lowStock = store.products.where((product) => product.stock <= product.lowStockThreshold).toList();
    final currency = store.storeProfile.currency;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: MediaQuery.of(context).size.width < 600 ? 2.4 : 2.0,
            crossAxisCount: MediaQuery.of(context).size.width > 1200 ? 3 : MediaQuery.of(context).size.width > 700 ? 2 : 1,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            children: [
              ReportCard(title: tr.text('daily_sales_report'), subtitle: '${tr.text('current_total_sales')}: ${formatCurrency(todaySales, currency: currency)}'),
              ReportCard(title: tr.text('monthly_sales'), subtitle: formatCurrency(monthSales, currency: currency)),
              ReportCard(title: tr.text('monthly_purchases'), subtitle: formatCurrency(monthPurchases, currency: currency)),
              ReportCard(title: tr.text('profit_report'), subtitle: '${tr.text('estimated_profit')}: ${formatCurrency(estimatedProfit, currency: currency)}'),
              ReportCard(title: tr.text('expenses_report'), subtitle: '${tr.text('expenses')}: ${formatCurrency(totalExpenses, currency: currency)}'),
              ReportCard(title: tr.text('inventory_value_report'), subtitle: '${tr.text('inventory_value')}: ${formatCurrency(store.inventoryRetailValue, currency: currency)}'),
              ReportCard(title: tr.text('inventory_health_report'), subtitle: '${tr.text('products_below_limit')}: ${store.lowStockCount}'),
              ReportCard(title: tr.text('stock_movement_report'), subtitle: '${tr.text('stock_in')}: $movementIn • ${tr.text('stock_out')}: $movementOut'),
            ],
          ),
          const SizedBox(height: 16),
          _ReportSection(
            title: tr.text('top_selling_products'),
            empty: tr.text('no_product_sales_yet'),
            children: topProductLines.take(8).map((entry) => ListTile(dense: true, leading: const Icon(Icons.trending_up), title: Text(entry.key), trailing: Text('${entry.value} ${tr.text('units')}'))).toList(),
          ),
          const SizedBox(height: 16),
          _ReportSection(
            title: tr.text('stock_alerts'),
            empty: tr.text('no_low_stock_products'),
            children: lowStock.map((product) => ListTile(dense: true, leading: const Icon(Icons.warning_amber_outlined), title: Text(product.name), subtitle: Text(product.code), trailing: Text('${product.stock}'))).toList(),
          ),
          const SizedBox(height: 16),
          _ReportSection(
            title: tr.text('recent_stock_movements'),
            empty: tr.text('no_stock_movements'),
            children: store.stockMovements.take(8).map((movement) => ListTile(dense: true, leading: Icon(movement.quantity >= 0 ? Icons.add_circle_outline : Icons.remove_circle_outline), title: Text(movement.productName), subtitle: Text('${movement.type} • ${movement.referenceNo}'), trailing: Text(movement.quantity > 0 ? '+${movement.quantity}' : '${movement.quantity}'))).toList(),
          ),
        ],
      ),
    );
  }
}

class _ReportSection extends StatelessWidget {
  const _ReportSection({required this.title, required this.empty, required this.children});
  final String title, empty;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (children.isEmpty) Text(empty) else ...children,
          ]),
        ),
      );
}
