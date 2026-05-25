import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/utils/currency_utils.dart';
import '../../data/app_store.dart';
import '../../widgets/summary_card.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final sales = store.sales;
    final todaySales = sales.where((sale) {
      final now = DateTime.now();
      return sale.date.year == now.year && sale.date.month == now.month && sale.date.day == now.day;
    }).toList();
    final todayTotal = todaySales.fold<double>(0, (sum, sale) => sum + sale.total);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SummaryCard(title: tr.text('today_sales'), value: formatCurrency(todayTotal, currency: store.storeProfile.currency), icon: Icons.payments_outlined),
            SummaryCard(title: tr.text('today_invoices'), value: '${todaySales.length}', icon: Icons.receipt_long_outlined),
            SummaryCard(title: tr.text('expenses'), value: formatCurrency(store.totalExpensesAmount, currency: store.storeProfile.currency), icon: Icons.money_off_csred_outlined),
            SummaryCard(title: tr.text('net_profit'), value: formatCurrency(store.estimateProfit(), currency: store.storeProfile.currency), icon: Icons.trending_up_outlined),
            SummaryCard(title: tr.text('product_count'), value: '${store.products.length}', icon: Icons.inventory_2_outlined),
            SummaryCard(title: tr.text('low_stock_alerts'), value: '${store.lowStockCount}', icon: Icons.warning_amber_rounded),
          ],
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 900;
            final salesPanel = Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr.text('latest_sales'), style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    if (sales.isEmpty)
                      Text(tr.text('no_sales_desc'))
                    else
                      ...sales.take(6).map((sale) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const CircleAvatar(child: Icon(Icons.receipt_long)),
                            title: Text(sale.invoiceNo),
                            subtitle: Text('${sale.customerName} • ${sale.date.toLocal()}'.split('.').first),
                            trailing: Text(formatCurrency(sale.total, currency: store.storeProfile.currency)),
                          )),
                  ],
                ),
              ),
            );
            final snapshotPanel = Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr.text('business_snapshot'), style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    _Line(title: tr.text('inventory_value'), value: formatCurrency(store.inventoryRetailValue, currency: store.storeProfile.currency)),
                    _Line(title: tr.text('inventory_cost_value'), value: formatCurrency(store.inventoryCostValue, currency: store.storeProfile.currency)),
                    _Line(title: tr.text('suppliers'), value: '${store.suppliers.length}'),
                    _Line(title: tr.text('customers'), value: '${store.customers.length}'),
                    _Line(title: tr.text('expenses_count'), value: '${store.expenses.length}'),
                  ],
                ),
              ),
            );
            if (isNarrow) {
              return Column(children: [salesPanel, const SizedBox(height: 16), snapshotPanel]);
            }
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: salesPanel), const SizedBox(width: 16), Expanded(child: snapshotPanel)]);
          },
        ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(title), Text(value, style: Theme.of(context).textTheme.titleMedium)],
      ),
    );
  }
}
