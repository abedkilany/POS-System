import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/services/cloud_sync_service.dart';
import '../../core/services/marketplace_api_service.dart';
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
        _DashboardMarketplacePublishCard(store: store),
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


class _DashboardMarketplacePublishCard extends StatefulWidget {
  const _DashboardMarketplacePublishCard({required this.store});
  final AppStore store;

  @override
  State<_DashboardMarketplacePublishCard> createState() => _DashboardMarketplacePublishCardState();
}

class _DashboardMarketplacePublishCardState extends State<_DashboardMarketplacePublishCard> {
  bool _busy = false;

  Future<void> _setUrl() async {
    final settings = CloudSyncSettings.load();
    final controller = TextEditingController(text: settings.apiBaseUrl);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('رابط سيرفر الـ Marketplace'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Marketplace API URL',
            hintText: 'https://xxxxx.trycloudflare.com',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (saved == true) {
      await settings.copyWith(apiBaseUrl: controller.text.trim(), enabled: true).save();
      if (mounted) setState(() {});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ رابط السيرفر.')));
    }
    controller.dispose();
  }

  Future<void> _publish() async {
    if (CloudSyncSettings.load().apiBaseUrl.trim().isEmpty) {
      await _setUrl();
      if (CloudSyncSettings.load().apiBaseUrl.trim().isEmpty) return;
    }
    setState(() => _busy = true);
    try {
      final identity = widget.store.appIdentity;
      final storeId = identity.storeId.trim().isEmpty ? 'store_${widget.store.deviceId}' : identity.storeId.trim();
      final branchId = identity.branchId.trim().isEmpty ? 'main' : identity.branchId.trim();
      final products = widget.store.products.where((p) => p.isActive && !p.isDeleted).toList();
      final result = await MarketplaceApiService().publishStore(
        storeId: storeId,
        branchId: branchId,
        store: {
          ...widget.store.storeProfile.toJson(),
          'id': storeId,
          'storeId': storeId,
          'branchId': branchId,
          'description': widget.store.storeProfile.footerNote,
        },
        products: products,
      );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم نشر ${result['publishedProducts'] ?? products.length} منتج على الـ Marketplace.')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل النشر: $error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = CloudSyncSettings.load().apiBaseUrl.trim();
    final productsCount = widget.store.products.where((p) => p.isActive && !p.isDeleted).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(child: Icon(Icons.storefront_outlined)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('نشر المتجر على الـ Marketplace', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Text(url.isEmpty ? 'أدخل رابط السيرفر ثم انشر المنتجات.' : 'السيرفر: $url'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('سيتم نشر بيانات المتجر و $productsCount منتج نشط للزبائن.'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _publish,
                  icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.cloud_upload_outlined),
                  label: const Text('Publish / نشر الآن'),
                ),
                OutlinedButton.icon(onPressed: _busy ? null : _setUrl, icon: const Icon(Icons.link_outlined), label: const Text('تعديل رابط السيرفر')),
              ],
            ),
          ],
        ),
      ),
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
