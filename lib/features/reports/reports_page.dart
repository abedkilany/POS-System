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
    final totalSales = store.totalSalesAmount;
    final totalExpenses = store.totalExpensesAmount;
    final estimatedProfit = store.estimateProfit();
    final activeSales = store.sales.where((sale) => !sale.isCancelled).toList();
    final today = DateTime.now();
    final todaySales = activeSales
        .where((sale) => sale.date.year == today.year && sale.date.month == today.month && sale.date.day == today.day)
        .fold<double>(0, (sum, sale) => sum + sale.total);
    final monthSales = activeSales
        .where((sale) => sale.date.year == today.year && sale.date.month == today.month)
        .fold<double>(0, (sum, sale) => sum + sale.total);
    final topProducts = <String, int>{};
    for (final sale in activeSales) {
      for (final item in sale.items) {
        topProducts[item.productName] = (topProducts[item.productName] ?? 0) + item.quantity;
      }
    }
    final topProductLines = topProducts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final lowStock = store.products.where((product) => product.stock <= 5).toList();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: MediaQuery.of(context).size.width > 1200
                ? 3
                : MediaQuery.of(context).size.width > 700
                    ? 2
                    : 1,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            children: [
              ReportCard(title: tr.text('daily_sales_report'), subtitle: '${tr.text('current_total_sales')}: ${formatCurrency(todaySales, currency: store.storeProfile.currency)}'),
              ReportCard(title: 'Monthly sales', subtitle: formatCurrency(monthSales, currency: store.storeProfile.currency)),
              ReportCard(title: tr.text('profit_report'), subtitle: '${tr.text('estimated_profit')}: ${formatCurrency(estimatedProfit, currency: store.storeProfile.currency)}'),
              ReportCard(title: tr.text('expenses_report'), subtitle: '${tr.text('expenses')}: ${formatCurrency(totalExpenses, currency: store.storeProfile.currency)}'),
              ReportCard(title: tr.text('inventory_value_report'), subtitle: '${tr.text('inventory_value')}: ${formatCurrency(store.inventoryRetailValue, currency: store.storeProfile.currency)}'),
              ReportCard(title: tr.text('inventory_health_report'), subtitle: '${tr.text('products_below_limit')}: ${store.lowStockCount}'),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Top selling products', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  if (topProductLines.isEmpty)
                    const Text('No product sales yet.')
                  else
                    ...topProductLines.take(8).map((entry) => ListTile(
                          dense: true,
                          leading: const Icon(Icons.trending_up),
                          title: Text(entry.key),
                          trailing: Text('${entry.value} units'),
                        )),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Stock alerts', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  if (lowStock.isEmpty)
                    const Text('No low stock products.')
                  else
                    ...lowStock.map((product) => ListTile(
                          dense: true,
                          leading: const Icon(Icons.warning_amber_outlined),
                          title: Text(product.name),
                          subtitle: Text(product.code),
                          trailing: Text('${product.stock}'),
                        )),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
