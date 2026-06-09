import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/utils/currency_utils.dart';
import '../../data/app_store.dart';
import '../../widgets/report_card.dart';
import '../../core/utils/responsive.dart';

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final totalExpenses = store.totalExpensesAmount;
    final estimatedProfit = store.estimateProfit();
    final sales = store.sales;
    final purchases = store.purchases;
    final stockMovements = store.stockMovements;
    final accountTransactions = store.accountTransactions;
    final activeSales = sales.where((sale) => !sale.isCancelled).toList();
    final today = DateTime.now();
    final todaySales = activeSales.where((sale) => sale.date.year == today.year && sale.date.month == today.month && sale.date.day == today.day).fold<double>(0, (sum, sale) => sum + sale.total);
    final monthSales = activeSales.where((sale) => sale.date.year == today.year && sale.date.month == today.month).fold<double>(0, (sum, sale) => sum + sale.total);
    final monthPurchases = purchases.where((purchase) => !purchase.isCancelled && purchase.date.year == today.year && purchase.date.month == today.month).fold<double>(0, (sum, purchase) => sum + purchase.subtotal);
    final movementIn = stockMovements.where((item) => item.quantity > 0).fold<double>(0, (sum, item) => sum + item.quantity);
    final movementOut = stockMovements.where((item) => item.quantity < 0).fold<double>(0, (sum, item) => sum + item.quantity.abs());
    final topProducts = <String, double>{};
    for (final sale in activeSales) {
      for (final item in sale.items) {
        topProducts[item.productName] = (topProducts[item.productName] ?? 0) + item.quantity;
      }
    }
    final topProductLines = topProducts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final lowStock = store.stockTrackedProducts.where((product) => product.stock <= product.lowStockThreshold).toList();
    final autoCorrections = stockMovements.where((movement) => movement.type == 'auto_correction').toList();
    final customerReceivables = store.customers.fold<double>(0, (sum, customer) {
      final balance = store.accountBalance('customer', customer.id);
      return balance > 0 ? sum + balance : sum;
    });
    final supplierPayables = store.suppliers.fold<double>(0, (sum, supplier) {
      final balance = store.accountBalance('supplier', supplier.id);
      return balance < 0 ? sum + balance.abs() : sum;
    });
    final todayPaymentReceived = accountTransactions.where((txn) => txn.type == 'paymentReceived' && txn.date.year == today.year && txn.date.month == today.month && txn.date.day == today.day).fold<double>(0, (sum, txn) => sum + txn.credit);
    final todayPaymentPaid = accountTransactions.where((txn) => txn.type == 'paymentPaid' && txn.date.year == today.year && txn.date.month == today.month && txn.date.day == today.day).fold<double>(0, (sum, txn) => sum + txn.debit);
    final todayPaymentReversalsIn = accountTransactions.where((txn) => txn.type == 'paymentReversal' && txn.accountType == 'supplier' && txn.date.year == today.year && txn.date.month == today.month && txn.date.day == today.day).fold<double>(0, (sum, txn) => sum + txn.credit);
    final todayPaymentReversalsOut = accountTransactions.where((txn) => txn.type == 'paymentReversal' && txn.accountType == 'customer' && txn.date.year == today.year && txn.date.month == today.month && txn.date.day == today.day).fold<double>(0, (sum, txn) => sum + txn.debit);
    final todayCashIn = todayPaymentReceived + todayPaymentReversalsIn;
    final todayCashOut = todayPaymentPaid + todayPaymentReversalsOut;
    final todayCashInByMethod = <String, double>{};
    final todayCashOutByMethod = <String, double>{};
    for (final txn in accountTransactions.where((txn) => txn.date.year == today.year && txn.date.month == today.month && txn.date.day == today.day)) {
      final method = txn.paymentMethod.trim().isEmpty ? tr.text('not_specified') : txn.paymentMethod.trim();
      if (txn.type == 'paymentReceived') todayCashInByMethod[method] = (todayCashInByMethod[method] ?? 0) + txn.credit;
      if (txn.type == 'paymentPaid') todayCashOutByMethod[method] = (todayCashOutByMethod[method] ?? 0) + txn.debit;
      if (txn.type == 'paymentReversal' && txn.accountType == 'supplier') todayCashInByMethod[method] = (todayCashInByMethod[method] ?? 0) + txn.credit;
      if (txn.type == 'paymentReversal' && txn.accountType == 'customer') todayCashOutByMethod[method] = (todayCashOutByMethod[method] ?? 0) + txn.debit;
    }
    final topCustomerDebts = store.customers.map((customer) => MapEntry(customer.name, store.accountBalance('customer', customer.id))).where((entry) => entry.value > 0).toList()..sort((a, b) => b.value.compareTo(a.value));
    final topSupplierDebts = store.suppliers.map((supplier) => MapEntry(supplier.name, store.accountBalance('supplier', supplier.id))).where((entry) => entry.value < 0).toList()..sort((a, b) => a.value.compareTo(b.value));

    return Padding(
      padding: VentioResponsive.pageInsets(context),
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
              ReportCard(title: tr.text('daily_sales_report'), subtitle: '${tr.text('current_total_sales')}: ${formatUsdReferenceAmount(todaySales, store.storeProfile)}'),
              ReportCard(title: tr.text('monthly_sales'), subtitle: formatUsdReferenceAmount(monthSales, store.storeProfile)),
              ReportCard(title: tr.text('monthly_purchases'), subtitle: formatUsdReferenceAmount(monthPurchases, store.storeProfile)),
              ReportCard(title: tr.text('profit_report'), subtitle: '${tr.text('estimated_profit')}: ${formatUsdReferenceAmount(estimatedProfit, store.storeProfile)}'),
              ReportCard(title: tr.text('expenses_report'), subtitle: '${tr.text('expenses')}: ${formatUsdReferenceAmount(totalExpenses, store.storeProfile)}'),
              ReportCard(title: tr.text('inventory_value_report'), subtitle: '${tr.text('inventory_value')}: ${formatUsdReferenceAmount(store.inventoryRetailValue, store.storeProfile)}'),
              ReportCard(title: tr.text('inventory_health_report'), subtitle: '${tr.text('products_below_limit')}: ${store.lowStockCount}'),
              ReportCard(title: tr.text('stock_movement_report'), subtitle: '${tr.text('stock_in')}: $movementIn • ${tr.text('stock_out')}: $movementOut'),
              ReportCard(title: tr.text('auto_inventory_corrections'), subtitle: '${autoCorrections.length}'),
              ReportCard(title: tr.text('customer_receivables'), subtitle: formatUsdReferenceAmount(customerReceivables, store.storeProfile)),
              ReportCard(title: tr.text('supplier_payables'), subtitle: formatUsdReferenceAmount(supplierPayables, store.storeProfile)),
              ReportCard(title: tr.text('today_cash_movement'), subtitle: '${tr.text('cash_in')}: ${formatUsdReferenceAmount(todayCashIn, store.storeProfile)} • ${tr.text('cash_out')}: ${formatUsdReferenceAmount(todayCashOut, store.storeProfile)}'),
            ],
          ),

          const SizedBox(height: 16),
          _ReportSection(
            title: tr.text('cash_movement_by_method'),
            empty: tr.text('no_cash_movement_today'),
            children: {...todayCashInByMethod.keys, ...todayCashOutByMethod.keys}.map((method) => ListTile(dense: true, leading: const Icon(Icons.payments_outlined), title: Text(method), subtitle: Text('${tr.text('cash_in')}: ${formatUsdReferenceAmount(todayCashInByMethod[method] ?? 0, store.storeProfile)}'), trailing: Text('${tr.text('cash_out')}: ${formatUsdReferenceAmount(todayCashOutByMethod[method] ?? 0, store.storeProfile)}'))).toList(),
          ),
          const SizedBox(height: 16),
          _ReportSection(
            title: tr.text('customer_debts'),
            empty: tr.text('no_customer_debts'),
            children: topCustomerDebts.take(8).map((entry) => ListTile(dense: true, leading: const Icon(Icons.person_outline), title: Text(entry.key), trailing: Text(formatUsdReferenceAmount(entry.value, store.storeProfile)))).toList(),
          ),
          const SizedBox(height: 16),
          _ReportSection(
            title: tr.text('supplier_payables'),
            empty: tr.text('no_supplier_payables'),
            children: topSupplierDebts.take(8).map((entry) => ListTile(dense: true, leading: const Icon(Icons.local_shipping_outlined), title: Text(entry.key), trailing: Text(formatUsdReferenceAmount(entry.value.abs(), store.storeProfile)))).toList(),
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
            title: tr.text('auto_inventory_corrections'),
            empty: tr.text('no_auto_inventory_corrections'),
            children: autoCorrections.take(12).map((movement) => ListTile(dense: true, leading: const Icon(Icons.warning_amber_outlined), title: Text(movement.productName), subtitle: Text('${movement.referenceNo} • ${movement.date.toLocal()}'.split('.').first), trailing: Text('+${movement.quantity}'))).toList(),
          ),
          const SizedBox(height: 16),
          _ReportSection(
            title: tr.text('recent_stock_movements'),
            empty: tr.text('no_stock_movements'),
            children: stockMovements.take(8).map((movement) => ListTile(dense: true, leading: Icon(movement.quantity >= 0 ? Icons.add_circle_outline : Icons.remove_circle_outline), title: Text(movement.productName), subtitle: Text('${movement.type} • ${movement.referenceNo}'), trailing: Text(movement.quantity > 0 ? '+${movement.quantity}' : '${movement.quantity}'))).toList(),
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
          padding: VentioResponsive.pageInsets(context),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (children.isEmpty) Text(empty) else ...children,
          ]),
        ),
      );
}
