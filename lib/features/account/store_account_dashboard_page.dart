import 'package:flutter/material.dart';

import '../../core/services/account_auth_service.dart';
import '../../core/utils/responsive.dart';

class StoreAccountDashboardPage extends StatelessWidget {
  const StoreAccountDashboardPage({
    super.key,
    required this.cache,
    required this.onRecoverExistingStore,
    required this.onLogout,
  });

  final AccountAuthCache cache;
  final VoidCallback onRecoverExistingStore;
  final Future<void> Function() onLogout;

  String _formatDate(DateTime? value) {
    if (value == null) return 'Not set';
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  int? _trialDaysLeft() {
    final end = cache.trialEndsAt;
    if (end == null) return null;
    final diff = end.difference(DateTime.now()).inDays;
    return diff < 0 ? 0 : diff;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final daysLeft = _trialDaysLeft();
    final status = cache.subscriptionStatus.trim().isEmpty
        ? 'unknown'
        : cache.subscriptionStatus.trim();
    final storeName = cache.storeName.trim().isEmpty
        ? cache.storeSlug
        : cache.storeName.trim();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Store account'),
        actions: [
          TextButton.icon(
            onPressed: onLogout,
            icon: const Icon(Icons.logout),
            label: const Text('Logout'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: VentioResponsive.pageInsets(context),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        runSpacing: 20,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircleAvatar(
                                radius: 30,
                                child: Text(
                                  storeName.isEmpty
                                      ? 'V'
                                      : storeName.substring(0, 1).toUpperCase(),
                                  style: theme.textTheme.headlineSmall,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    storeName.isEmpty ? 'Your store' : storeName,
                                    style: theme.textTheme.headlineSmall?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    cache.loginName.isEmpty
                                        ? '${cache.username}@${cache.storeSlug}'
                                        : cache.loginName,
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Chip(
                            avatar: const Icon(Icons.verified_outlined, size: 18),
                            label: Text(status.toUpperCase()),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 760;
                      final cards = [
                        _MetricCard(
                          icon: Icons.workspace_premium_outlined,
                          title: 'Plan',
                          value: status == 'trial' ? 'Trial' : status,
                          subtitle: 'Current subscription',
                        ),
                        _MetricCard(
                          icon: Icons.event_available_outlined,
                          title: 'Trial remaining',
                          value: daysLeft == null ? '—' : '$daysLeft days',
                          subtitle: 'Ends ${_formatDate(cache.trialEndsAt)}',
                        ),
                        _MetricCard(
                          icon: Icons.devices_outlined,
                          title: 'Device limit',
                          value: cache.devicesLimit?.toString() ?? '—',
                          subtitle: 'Allowed devices for this store',
                        ),
                      ];
                      if (!wide) {
                        return Column(
                          children: cards
                              .map((card) => Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: card,
                                  ))
                              .toList(),
                        );
                      }
                      return Row(
                        children: cards
                            .map((card) => Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 12),
                                    child: card,
                                  ),
                                ))
                            .toList(),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Account management',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'This is the online account area for your store. The POS and inventory system stay available from Offline login on this device.',
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 20),
                          _InfoRow(label: 'Account ID', value: cache.accountId),
                          _InfoRow(label: 'Store ID', value: cache.storeId),
                          _InfoRow(label: 'Store slug', value: cache.storeSlug),
                          _InfoRow(label: 'Last verified', value: _formatDate(cache.lastVerifiedAt)),
                          const SizedBox(height: 20),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              OutlinedButton.icon(
                                onPressed: onRecoverExistingStore,
                                icon: const Icon(Icons.key_outlined),
                                label: const Text('Recover existing store'),
                              ),
                              const _ComingSoonButton(
                                icon: Icons.credit_card_outlined,
                                label: 'Manage subscription',
                              ),
                              const _ComingSoonButton(
                                icon: Icons.devices_other_outlined,
                                label: 'Manage devices',
                              ),
                              const _ComingSoonButton(
                                icon: Icons.storefront_outlined,
                                label: 'Online store settings',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String value;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 28),
            const SizedBox(height: 14),
            Text(title, style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(subtitle, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(value.trim().isEmpty ? '—' : value),
          ),
        ],
      ),
    );
  }
}

class _ComingSoonButton extends StatelessWidget {
  const _ComingSoonButton({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: null,
      icon: Icon(icon),
      label: Text('$label · soon'),
    );
  }
}
