import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/utils/currency_utils.dart';
import '../../data/app_store.dart';
import '../../widgets/report_card.dart';
import '../../core/utils/responsive.dart';
import 'reports_snapshot_service.dart';

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key, required this.store});

  final AppStore store;

  static const ReportsSnapshotService _service = ReportsSnapshotService();

  String _movementTypeLabel(AppLocalizations tr, String type) {
    switch (type) {
      case 'auto_correction':
        return tr.text('auto_correction');
      case 'purchase_receive':
        return tr.text('purchase_received');
      case 'purchase_return':
        return tr.text('purchase_return');
      case 'purchase_cancel':
        return tr.text('purchase_cancel');
      case 'sale':
        return tr.text('sale_invoice');
      case 'sale_return':
        return tr.text('return_sale');
      case 'sale_restore':
        return tr.text('sale_restore');
      case 'sale_cancel':
        return tr.text('sale_cancel');
      case 'paymentReceived':
        return tr.text('payment_received');
      case 'paymentPaid':
        return tr.text('payment_paid');
      case 'paymentReversal':
        return tr.text('payment_reversal');
      case 'warehouse_transfer_in':
        return tr.text('warehouse_transfer_in');
      case 'warehouse_transfer_out':
        return tr.text('warehouse_transfer_out');
      case 'count_adjustment':
        return tr.text('count_adjustment');
      case 'manufacturing_consume':
        return tr.text('manufacturing_consume');
      case 'manufacturing_output':
        return tr.text('manufacturing_output');
      default:
        return type.replaceAll('_', ' ');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final tr = AppLocalizations.of(context);
        if (!store.canViewReports) {
          return const _AccessDeniedScaffold(
            title: 'Reports',
            message: 'You do not have access to reports.',
          );
        }
        if (!store.isCoreDataLoaded || !store.isLedgerDataLoaded) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }
        final reference = DateTime.now().toLocal();
        final cachedSummary = _service.peekSummary(store, now: reference);
        if (cachedSummary != null) {
          return _buildContent(
              context, tr, _ReportsPageData.fromSummary(cachedSummary));
        }

        return FutureBuilder<Map<String, Object?>>(
          future: _service.summaryFor(store, now: reference),
          builder: (context, snapshot) {
            final summary = snapshot.data;
            if (summary == null) {
              if (snapshot.hasError) {
                return _buildContent(
                  context,
                  tr,
                  _ReportsPageData.fromStore(store, reference),
                );
              }
              return const Center(child: CircularProgressIndicator.adaptive());
            }
            return _buildContent(
              context,
              tr,
              _ReportsPageData.fromSummary(summary),
            );
          },
        );
      },
    );
  }

  Widget _buildContent(
    BuildContext context,
    AppLocalizations tr,
    _ReportsPageData data,
  ) {
    final totalExpenses = data.totalExpenses;
    final estimatedProfit = data.estimatedProfit;
    final todaySales = data.todaySales;
    final monthSales = data.monthSales;
    final monthPurchases = data.monthPurchases;
    final movementIn = data.movementIn;
    final movementOut = data.movementOut;
    final autoCorrections = data.autoCorrections;
    final lowStock = data.lowStock;
    final inventoryRetailValue = data.inventoryRetailValue;
    final lowStockCount = data.lowStockCount;
    final stockMovements = data.stockMovements;
    final customerReceivables = data.customerReceivables;
    final supplierPayables = data.supplierPayables;
    final todayCashIn = data.todayCashIn;
    final todayCashOut = data.todayCashOut;
    final todayCashInByMethod = data.todayCashInByMethod;
    final todayCashOutByMethod = data.todayCashOutByMethod;
    final topProductLines = data.topProductLines;
    final topCustomerDebts = data.topCustomerDebts;
    final topSupplierDebts = data.topSupplierDebts;

    return Padding(
      padding: VentioResponsive.pageInsets(context),
      child: ListView(
        children: [
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio:
                MediaQuery.of(context).size.width < 600 ? 2.4 : 2.0,
            crossAxisCount: MediaQuery.of(context).size.width > 1200
                ? 3
                : MediaQuery.of(context).size.width > 700
                    ? 2
                    : 1,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            children: [
              ReportCard(
                  title: tr.text('daily_sales_report'),
                  subtitle:
                      '${tr.text('current_total_sales')}: ${formatUsdReferenceAmount(todaySales, store.storeProfile)}'),
              ReportCard(
                  title: tr.text('monthly_sales'),
                  subtitle:
                      formatUsdReferenceAmount(monthSales, store.storeProfile)),
              ReportCard(
                  title: tr.text('monthly_purchases'),
                  subtitle: formatUsdReferenceAmount(
                      monthPurchases, store.storeProfile)),
              ReportCard(
                  title: tr.text('profit_report'),
                  subtitle:
                      '${tr.text('estimated_profit')}: ${formatUsdReferenceAmount(estimatedProfit, store.storeProfile)}'),
              ReportCard(
                  title: tr.text('expenses_report'),
                  subtitle:
                      '${tr.text('expenses')}: ${formatUsdReferenceAmount(totalExpenses, store.storeProfile)}'),
              ReportCard(
                  title: tr.text('inventory_value_report'),
                  subtitle:
                      '${tr.text('inventory_value')}: ${formatUsdReferenceAmount(inventoryRetailValue, store.storeProfile)}'),
              ReportCard(
                  title: tr.text('inventory_health_report'),
                  subtitle:
                      '${tr.text('products_below_limit')}: $lowStockCount'),
              ReportCard(
                  title: tr.text('stock_movement_report'),
                  subtitle:
                      '${tr.text('stock_in')}: $movementIn • ${tr.text('stock_out')}: $movementOut'),
              ReportCard(
                  title: tr.text('auto_inventory_corrections'),
                  subtitle: '${autoCorrections.length}'),
              ReportCard(
                  title: tr.text('customer_receivables'),
                  subtitle: formatUsdReferenceAmount(
                      customerReceivables, store.storeProfile)),
              ReportCard(
                  title: tr.text('supplier_payables'),
                  subtitle: formatUsdReferenceAmount(
                      supplierPayables, store.storeProfile)),
              ReportCard(
                  title: tr.text('today_cash_movement'),
                  subtitle:
                      '${tr.text('cash_in')}: ${formatUsdReferenceAmount(todayCashIn, store.storeProfile)} • ${tr.text('cash_out')}: ${formatUsdReferenceAmount(todayCashOut, store.storeProfile)}'),
            ],
          ),
          const SizedBox(height: 16),
          _ReportSection(
            title: tr.text('cash_movement_by_method'),
            empty: tr.text('no_cash_movement_today'),
            children: {
              ...todayCashInByMethod.keys,
              ...todayCashOutByMethod.keys
            }
                .map((method) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.payments_outlined),
                    title: Text(method == 'not_specified'
                        ? tr.text('not_specified')
                        : method),
                    subtitle: Text(
                        '${tr.text('cash_in')}: ${formatUsdReferenceAmount(todayCashInByMethod[method] ?? 0, store.storeProfile)}'),
                    trailing: Text(
                        '${tr.text('cash_out')}: ${formatUsdReferenceAmount(todayCashOutByMethod[method] ?? 0, store.storeProfile)}')))
                .toList(),
          ),
          const SizedBox(height: 16),
          _ReportSection(
            title: tr.text('customer_debts'),
            empty: tr.text('no_customer_debts'),
            children: topCustomerDebts
                .take(8)
                .map((entry) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.person_outline),
                    title: Text(entry.key),
                    trailing: Text(formatUsdReferenceAmount(
                        entry.value, store.storeProfile))))
                .toList(),
          ),
          const SizedBox(height: 16),
          _ReportSection(
            title: tr.text('supplier_payables'),
            empty: tr.text('no_supplier_payables'),
            children: topSupplierDebts
                .take(8)
                .map((entry) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.local_shipping_outlined),
                    title: Text(entry.key),
                    trailing: Text(formatUsdReferenceAmount(
                        entry.value.abs(), store.storeProfile))))
                .toList(),
          ),
          const SizedBox(height: 16),
          _ReportSection(
            title: tr.text('top_selling_products'),
            empty: tr.text('no_product_sales_yet'),
            children: topProductLines
                .take(8)
                .map((entry) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.trending_up),
                    title: Text(entry.key),
                    trailing: Text('${entry.value} ${tr.text('units')}')))
                .toList(),
          ),
          const SizedBox(height: 16),
          _ReportSection(
            title: tr.text('stock_alerts'),
            empty: tr.text('no_low_stock_products'),
            children: lowStock
                .map((product) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.warning_amber_outlined),
                    title: Text(product.name),
                    subtitle: Text(product.code),
                    trailing: Text('${product.stock}')))
                .toList(),
          ),
          const SizedBox(height: 16),
          _ReportSection(
            title: tr.text('auto_inventory_corrections'),
            empty: tr.text('no_auto_inventory_corrections'),
            children: autoCorrections
                .take(12)
                .map((movement) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.warning_amber_outlined),
                    title: Text(movement.productName),
                    subtitle: Text(
                        '${movement.referenceNo} • ${movement.date.toLocal()}'
                            .split('.')
                            .first),
                    trailing: Text('+${movement.quantity}')))
                .toList(),
          ),
          const SizedBox(height: 16),
          _ReportSection(
            title: tr.text('recent_stock_movements'),
            empty: tr.text('no_stock_movements'),
            children: stockMovements
                .take(8)
                .map((movement) => ListTile(
                    dense: true,
                    leading: Icon(movement.quantity >= 0
                        ? Icons.add_circle_outline
                        : Icons.remove_circle_outline),
                    title: Text(movement.productName),
                    subtitle: Text(
                        '${_movementTypeLabel(tr, movement.type)} • ${movement.referenceNo}'),
                    trailing: Text(movement.quantity > 0
                        ? '+${movement.quantity}'
                        : '${movement.quantity}')))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _ReportsPageData {
  const _ReportsPageData({
    required this.totalExpenses,
    required this.estimatedProfit,
    required this.todaySales,
    required this.monthSales,
    required this.monthPurchases,
    required this.movementIn,
    required this.movementOut,
    required this.autoCorrections,
    required this.lowStock,
    required this.stockMovements,
    required this.customerReceivables,
    required this.supplierPayables,
    required this.inventoryRetailValue,
    required this.lowStockCount,
    required this.todayCashIn,
    required this.todayCashOut,
    required this.todayCashInByMethod,
    required this.todayCashOutByMethod,
    required this.topProductLines,
    required this.topCustomerDebts,
    required this.topSupplierDebts,
  });

  final double totalExpenses;
  final double estimatedProfit;
  final double todaySales;
  final double monthSales;
  final double monthPurchases;
  final double movementIn;
  final double movementOut;
  final List<dynamic> autoCorrections;
  final List<dynamic> lowStock;
  final List<dynamic> stockMovements;
  final double customerReceivables;
  final double supplierPayables;
  final double inventoryRetailValue;
  final int lowStockCount;
  final double todayCashIn;
  final double todayCashOut;
  final Map<String, double> todayCashInByMethod;
  final Map<String, double> todayCashOutByMethod;
  final List<MapEntry<String, double>> topProductLines;
  final List<MapEntry<String, double>> topCustomerDebts;
  final List<MapEntry<String, double>> topSupplierDebts;

  factory _ReportsPageData.fromSummary(Map<String, Object?> summary) {
    return _ReportsPageData(
      totalExpenses: _doubleValue(summary['totalExpenses']),
      estimatedProfit: _doubleValue(summary['estimatedProfit']),
      todaySales: _doubleValue(summary['todaySales']),
      monthSales: _doubleValue(summary['monthSales']),
      monthPurchases: _doubleValue(summary['monthPurchases']),
      movementIn: _doubleValue(summary['movementIn']),
      movementOut: _doubleValue(summary['movementOut']),
      autoCorrections: _reportMovementsFromSummary(summary['autoCorrections']),
      lowStock: _reportProductsFromSummary(summary['lowStock']),
      stockMovements: _reportMovementsFromSummary(summary['stockMovements']),
      customerReceivables: _doubleValue(summary['customerReceivables']),
      supplierPayables: _doubleValue(summary['supplierPayables']),
      inventoryRetailValue: _doubleValue(summary['inventoryRetailValue']),
      lowStockCount: _intValue(summary['lowStockCount']),
      todayCashIn: _doubleValue(summary['todayCashIn']),
      todayCashOut: _doubleValue(summary['todayCashOut']),
      todayCashInByMethod: _doubleMap(summary['todayCashInByMethod']),
      todayCashOutByMethod: _doubleMap(summary['todayCashOutByMethod']),
      topProductLines: _entryList(summary['topProductLines']),
      topCustomerDebts: _entryList(summary['topCustomerDebts']),
      topSupplierDebts: _entryList(summary['topSupplierDebts']),
    );
  }

  factory _ReportsPageData.fromStore(AppStore store, DateTime today) {
    return _ReportsPageData.fromSummary(const <String, Object?>{});
  }
}

class _ReportProductAlert {
  const _ReportProductAlert({
    required this.name,
    required this.code,
    required this.stock,
  });

  final String name;
  final String code;
  final double stock;
}

class _ReportMovementItem {
  const _ReportMovementItem({
    required this.type,
    required this.productName,
    required this.referenceNo,
    required this.quantity,
    required this.date,
  });

  final String type;
  final String productName;
  final String referenceNo;
  final double quantity;
  final DateTime date;
}

double _doubleValue(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

int _intValue(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

Map<String, double> _doubleMap(Object? value) {
  if (value is! Map) return <String, double>{};
  return value
      .map(
        (key, item) => MapEntry(key.toString(), _doubleValue(item)),
      )
      .cast<String, double>();
}

List<MapEntry<String, double>> _entryList(Object? raw) {
  final rows = raw as List<dynamic>? ?? const <dynamic>[];
  return rows
      .map((item) {
        final map =
            item is Map ? item.cast<String, Object?>() : <String, Object?>{};
        return MapEntry(
          map['key']?.toString() ?? '',
          _doubleValue(map['value']),
        );
      })
      .where((entry) => entry.key.isNotEmpty)
      .toList(growable: false);
}

List<_ReportProductAlert> _reportProductsFromSummary(Object? raw) {
  final rows = raw as List<dynamic>? ?? const <dynamic>[];
  return rows
      .map((item) {
        final map =
            item is Map ? item.cast<String, Object?>() : <String, Object?>{};
        return _ReportProductAlert(
          name: map['name']?.toString() ?? '',
          code: map['code']?.toString() ?? '',
          stock: _doubleValue(map['stock']),
        );
      })
      .where((entry) => entry.name.isNotEmpty)
      .toList(growable: false);
}

List<_ReportMovementItem> _reportMovementsFromSummary(Object? raw) {
  final rows = raw as List<dynamic>? ?? const <dynamic>[];
  return rows
      .map((item) {
        final map =
            item is Map ? item.cast<String, Object?>() : <String, Object?>{};
        return _ReportMovementItem(
          type: map['type']?.toString() ?? '',
          productName: map['productName']?.toString() ?? '',
          referenceNo: map['referenceNo']?.toString() ?? '',
          quantity: _doubleValue(map['quantity']),
          date: DateTime.tryParse(map['date']?.toString() ?? '') ??
              DateTime.now(),
        );
      })
      .where((entry) =>
          entry.productName.isNotEmpty || entry.referenceNo.isNotEmpty)
      .toList(growable: false);
}

class _AccessDeniedScaffold extends StatelessWidget {
  const _AccessDeniedScaffold({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 42),
                  const SizedBox(height: 12),
                  Text(title,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(message, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReportSection extends StatelessWidget {
  const _ReportSection(
      {required this.title, required this.empty, required this.children});
  final String title, empty;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: VentioResponsive.pageInsets(context),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (children.isEmpty) Text(empty) else ...children,
          ]),
        ),
      );
}
