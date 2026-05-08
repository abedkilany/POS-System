import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../models/online_order.dart';
import '../../models/platform_store.dart';

class PlatformPage extends StatelessWidget {
  const PlatformPage({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('Platform Foundation', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Basic structure for stores, customers, app administration, online orders, and future delivery users.'),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _MetricCard(title: 'Stores', value: store.platformStores.length.toString(), icon: Icons.storefront),
                _MetricCard(title: 'Online orders', value: store.onlineOrders.length.toString(), icon: Icons.shopping_bag),
                _MetricCard(title: 'Pending orders', value: store.pendingOnlineOrders.length.toString(), icon: Icons.pending_actions),
                _MetricCard(title: 'Delivery ready', value: store.roles.any((role) => role.id == 'driver') ? 'Yes' : 'No', icon: Icons.delivery_dining),
              ],
            ),
            const SizedBox(height: 24),
            _SectionCard(
              title: 'Platform roles',
              child: Column(
                children: [
                  for (final role in store.roles.where((role) => ['platform_admin', 'store_owner', 'store_staff', 'customer', 'driver'].contains(role.id)))
                    ListTile(
                      leading: const Icon(Icons.verified_user_outlined),
                      title: Text(role.name),
                      subtitle: Text(role.permissions.join(' • ')),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: 'Registered stores',
              trailing: store.canManagePlatform
                  ? FilledButton.icon(
                      onPressed: () => _createLocalStore(context),
                      icon: const Icon(Icons.add),
                      label: const Text('Add test store'),
                    )
                  : null,
              child: Column(
                children: store.platformStores.isEmpty
                    ? const [ListTile(title: Text('No stores yet.'))]
                    : [
                        for (final item in store.platformStores)
                          ListTile(
                            leading: const Icon(Icons.storefront),
                            title: Text(item.name),
                            subtitle: Text('${item.subscriptionPlan} / ${item.subscriptionStatus} • Online: ${item.isOnlineEnabled ? 'enabled' : 'disabled'}'),
                          ),
                      ],
              ),
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: 'Online orders pipeline',
              trailing: store.canManageOnlineOrders
                  ? FilledButton.icon(
                      onPressed: () => _createDemoOrder(context),
                      icon: const Icon(Icons.add_shopping_cart),
                      label: const Text('Add demo order'),
                    )
                  : null,
              child: Column(
                children: store.onlineOrders.isEmpty
                    ? const [ListTile(title: Text('No online orders yet.'))]
                    : [
                        for (final order in store.onlineOrders)
                          ListTile(
                            leading: const Icon(Icons.shopping_bag_outlined),
                            title: Text('${order.customerName} • ${order.total.toStringAsFixed(2)}'),
                            subtitle: Text('${order.status} • ${order.deliveryAddress}'),
                            trailing: store.canManageOnlineOrders
                                ? PopupMenuButton<String>(
                                    onSelected: (value) => store.updateOnlineOrderStatus(order.id, value),
                                    itemBuilder: (_) => [
                                      for (final status in OnlineOrderStatus.all)
                                        PopupMenuItem(value: status, child: Text(status)),
                                    ],
                                  )
                                : null,
                          ),
                      ],
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _createLocalStore(BuildContext context) async {
    final now = DateTime.now();
    await store.addOrUpdatePlatformStore(PlatformStore(
      id: 'store_${now.microsecondsSinceEpoch}',
      name: 'Demo Online Store',
      description: 'Created from Platform Foundation page',
      isOnlineEnabled: true,
      subscriptionPlan: 'trial',
      subscriptionStatus: 'active',
      createdAt: now,
      updatedAt: now,
    ));
  }

  Future<void> _createDemoOrder(BuildContext context) async {
    final now = DateTime.now();
    final storeId = store.platformStores.isNotEmpty ? store.platformStores.first.id : 'store_default';
    await store.addOnlineOrder(OnlineOrder(
      id: 'order_${now.microsecondsSinceEpoch}',
      storeId: storeId,
      customerUserId: 'customer_demo',
      customerName: 'Demo Customer',
      customerPhone: '00000000',
      deliveryAddress: 'Demo address',
      status: OnlineOrderStatus.placed,
      items: const [OnlineOrderItem(productId: 'demo', productName: 'Demo Product', unitPrice: 10, quantity: 1)],
      deliveryFee: 2,
      createdAt: now,
      updatedAt: now,
    ));
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.title, required this.value, required this.icon});

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(child: Icon(icon)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title), Text(value, style: Theme.of(context).textTheme.titleLarge)])),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))), if (trailing != null) trailing!]),
            const Divider(height: 24),
            child,
          ],
        ),
      ),
    );
  }
}
