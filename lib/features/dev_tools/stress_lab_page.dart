import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/repositories/business_repositories.dart';
import '../../core/services/local_database_service.dart';
import '../../core/utils/currency_utils.dart';
import '../../core/utils/responsive.dart';
import '../../data/app_store.dart';
import '../../widgets/summary_card.dart';

class StressLabPage extends StatefulWidget {
  const StressLabPage({super.key, required this.store});

  final AppStore store;

  @override
  State<StressLabPage> createState() => _StressLabPageState();
}

class _StressLabPageState extends State<StressLabPage> {
  late Future<_StressLabSnapshot> _snapshotFuture;

  @override
  void initState() {
    super.initState();
    _snapshotFuture = _loadSnapshot();
  }

  @override
  void didUpdateWidget(covariant StressLabPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      _snapshotFuture = _loadSnapshot();
    }
  }

  Future<_StressLabSnapshot> _loadSnapshot() async {
    final reference = DateTime.now().toLocal();
    final summary = await LocalDatabaseService.buildDashboardSummaryFromSqlite(
          reference: reference,
        ) ??
        <String, Object?>{};

    final results = await Future.wait<Object?>([
      ProductRepository.queryPage(limit: 1, activeOnly: false, stockTrackedOnly: false),
      CustomerRepository.queryPage(limit: 1, includeWalkIn: true),
      SupplierRepository.queryPage(limit: 1),
      SaleRepository.queryPage(limit: 1),
      PurchaseRepository.queryPage(limit: 1),
      ExpenseRepository.queryPage(limit: 1),
      InventoryRepository.queryStockMovements(limit: 1),
      SaleRepository.queryQuotationsPage(limit: 1),
      SaleRepository.queryDeliveryNotesPage(limit: 1),
      InventoryRepository.getInventoryCounts(),
    ]);

    int totalCountOf(Object? value) {
      if (value == null) return 0;
      final dynamic page = value;
      return (page.totalCount as int?) ?? 0;
    }

    final productCount = totalCountOf(results[0]);
    final customerCount = totalCountOf(results[1]);
    final supplierCount = totalCountOf(results[2]);
    final saleCount = totalCountOf(results[3]);
    final purchaseCount = totalCountOf(results[4]);
    final expenseCount = totalCountOf(results[5]);
    final movementCount = totalCountOf(results[6]);
    final quotationCount = totalCountOf(results[7]);
    final deliveryNoteCount = totalCountOf(results[8]);
    final inventoryCountSessions =
        (results[9] as List?)?.length ?? 0;

    return _StressLabSnapshot(
      generatedAt: reference,
      productCount: productCount,
      customerCount: customerCount,
      supplierCount: supplierCount,
      saleCount: saleCount,
      purchaseCount: purchaseCount,
      expenseCount: expenseCount,
      movementCount: movementCount,
      quotationCount: quotationCount,
      deliveryNoteCount: deliveryNoteCount,
      inventoryCountSessions: inventoryCountSessions,
      todaySalesTotal:
          (summary['todaySalesTotal'] as num?)?.toDouble() ?? 0.0,
      todayProfitTotal:
          (summary['todayProfitTotal'] as num?)?.toDouble() ?? 0.0,
      lowStockCount: (summary['lowStockCount'] as num?)?.toInt() ?? 0,
      pendingSyncCount: (summary['pendingSyncCount'] as num?)?.toInt() ?? 0,
      blockingConflictCount:
          (summary['blockingConflictCount'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr.text('stress_lab')),
        actions: [
          IconButton(
            tooltip: tr.text('refresh'),
            onPressed: () => setState(() => _snapshotFuture = _loadSnapshot()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<_StressLabSnapshot>(
        future: _snapshotFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }
          final data = snapshot.data;
          if (data == null) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }
          return ListView(
            padding: VentioResponsive.pageInsets(context),
            children: [
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  SummaryCard(
                    title: tr.text('products'),
                    value: '${data.productCount}',
                    icon: Icons.inventory_2_outlined,
                  ),
                  SummaryCard(
                    title: tr.text('customers'),
                    value: '${data.customerCount}',
                    icon: Icons.people_outline,
                  ),
                  SummaryCard(
                    title: tr.text('sales'),
                    value: '${data.saleCount}',
                    icon: Icons.point_of_sale_outlined,
                  ),
                  SummaryCard(
                    title: tr.text('purchases'),
                    value: '${data.purchaseCount}',
                    icon: Icons.shopping_cart_outlined,
                  ),
                  SummaryCard(
                    title: tr.text('expenses'),
                    value: '${data.expenseCount}',
                    icon: Icons.receipt_long_outlined,
                  ),
                  SummaryCard(
                    title: tr.text('stock_movements'),
                    value: '${data.movementCount}',
                    icon: Icons.swap_horiz_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr.text('stress_lab'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'SQLite-backed diagnostics only. No AppStore business lists are used here.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _MiniStat(
                            label: tr.text('sales_today'),
                            value: formatUsdReferenceAmount(
                              data.todaySalesTotal,
                              widget.store.storeProfile,
                            ),
                          ),
                          _MiniStat(
                            label: tr.text('profit_today'),
                            value: formatUsdReferenceAmount(
                              data.todayProfitTotal,
                              widget.store.storeProfile,
                            ),
                          ),
                          _MiniStat(
                            label: tr.text('low_stock'),
                            value: '${data.lowStockCount}',
                          ),
                          _MiniStat(
                            label: tr.text('pending_sync'),
                            value: '${data.pendingSyncCount}',
                          ),
                          _MiniStat(
                            label: tr.text('blocking_conflicts'),
                            value: '${data.blockingConflictCount}',
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '${tr.text('active_stock_count')}: ${data.inventoryCountSessions}',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${tr.text('quotations')}: ${data.quotationCount}  •  ${tr.text('delivery_notes')}: ${data.deliveryNoteCount}',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StressLabSnapshot {
  const _StressLabSnapshot({
    required this.generatedAt,
    required this.productCount,
    required this.customerCount,
    required this.supplierCount,
    required this.saleCount,
    required this.purchaseCount,
    required this.expenseCount,
    required this.movementCount,
    required this.quotationCount,
    required this.deliveryNoteCount,
    required this.inventoryCountSessions,
    required this.todaySalesTotal,
    required this.todayProfitTotal,
    required this.lowStockCount,
    required this.pendingSyncCount,
    required this.blockingConflictCount,
  });

  final DateTime generatedAt;
  final int productCount;
  final int customerCount;
  final int supplierCount;
  final int saleCount;
  final int purchaseCount;
  final int expenseCount;
  final int movementCount;
  final int quotationCount;
  final int deliveryNoteCount;
  final int inventoryCountSessions;
  final double todaySalesTotal;
  final double todayProfitTotal;
  final int lowStockCount;
  final int pendingSyncCount;
  final int blockingConflictCount;
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: math.min(220, MediaQuery.of(context).size.width),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Text(
                value,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
