import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/services/account_auth_service.dart';
import '../../core/utils/responsive.dart';
import '../../data/app_store.dart';
import '../shared/sync_monitoring_section.dart';

class StoreAccountDashboardPage extends StatefulWidget {
  const StoreAccountDashboardPage({
    super.key,
    required this.store,
    required this.cache,
    required this.hasStoreIdentity,
    required this.hasLocalStoreData,
    required this.canRecoverStoreData,
    required this.onRecoverStoreIdentity,
    required this.onRecoverStoreData,
    required this.onLogout,
    required this.onLocaleChanged,
  });

  final AppStore store;
  final AccountAuthCache cache;
  final bool hasStoreIdentity;
  final bool hasLocalStoreData;
  final bool canRecoverStoreData;
  final VoidCallback onRecoverStoreIdentity;
  final VoidCallback onRecoverStoreData;
  final Future<void> Function() onLogout;
  final ValueChanged<Locale> onLocaleChanged;

  @override
  State<StoreAccountDashboardPage> createState() =>
      _StoreAccountDashboardPageState();
}

class _StoreAccountDashboardPageState extends State<StoreAccountDashboardPage> {
  var _selectedIndex = 0;

  AccountAuthCache get cache => widget.cache;

  String _formatDate(BuildContext context, DateTime? value) {
    if (value == null) {
      return AppLocalizations.of(context).text('account_not_set');
    }
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

  Future<void> _changePassword() async {
    final currentController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var saving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: !saving,
      builder: (dialogContext) {
        final tr = AppLocalizations.of(dialogContext);
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submit() async {
              if (!(formKey.currentState?.validate() ?? false)) return;
              setDialogState(() => saving = true);
              final result = await AccountAuthService().changePassword(
                accountToken: cache.accountToken,
                currentPassword: currentController.text,
                newPassword: newController.text,
              );
              if (!dialogContext.mounted) return;
              setDialogState(() => saving = false);
              if (result.ok) {
                Navigator.of(dialogContext).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(result.message.isEmpty
                          ? tr.text('account_password_changed_success')
                          : result.message)),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(result.message.isEmpty
                          ? tr.text('account_password_change_failed')
                          : result.message)),
                );
              }
            }

            return AlertDialog(
              title: Text(tr.text('account_change_password')),
              content: Form(
                key: formKey,
                child: SizedBox(
                  width: 420,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: currentController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: tr.text('account_current_password'),
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                        validator: (value) => (value ?? '').isEmpty
                            ? tr.text('account_enter_current_password')
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: newController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: tr.text('account_new_password'),
                          prefixIcon: Icon(Icons.password_outlined),
                        ),
                        validator: (value) {
                          final text = value ?? '';
                          if (text.length < 6) {
                            return tr.text('account_password_min_6');
                          }
                          if (text == currentController.text) {
                            return tr
                                .text('account_password_must_be_different');
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: confirmController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: tr.text('account_confirm_new_password'),
                          prefixIcon: Icon(Icons.check_circle_outline),
                        ),
                        validator: (value) => value != newController.text
                            ? tr.text('account_passwords_do_not_match')
                            : null,
                        onFieldSubmitted: (_) => saving ? null : submit(),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      saving ? null : () => Navigator.of(dialogContext).pop(),
                  child: Text(tr.text('cancel')),
                ),
                FilledButton.icon(
                  onPressed: saving ? null : submit,
                  icon: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(saving
                      ? tr.text('saving')
                      : tr.text('account_save_password')),
                ),
              ],
            );
          },
        );
      },
    );

    currentController.dispose();
    newController.dispose();
    confirmController.dispose();
  }

  Widget _buildAccountSettings(BuildContext context) {
    final theme = Theme.of(context);
    final tr = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr.text('account_settings'),
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              tr.text('account_settings_description'),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            _InfoRow(
                label: tr.text('account_login_name'), value: cache.loginName),
            _InfoRow(label: tr.text('username'), value: cache.username),
            _InfoRow(
                label: tr.text('store'),
                value: cache.storeName.trim().isEmpty
                    ? cache.storeSlug
                    : cache.storeName),
            _InfoRow(
                label: tr.text('subscription'),
                value: cache.subscriptionStatus),
            const Divider(height: 32),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(child: Icon(Icons.password_outlined)),
              title: Text(tr.text('account_change_password')),
              subtitle: Text(tr.text('account_change_password_subtitle')),
              trailing: const Icon(Icons.chevron_right),
              onTap: _changePassword,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverview(BuildContext context) {
    final theme = Theme.of(context);
    final tr = AppLocalizations.of(context);
    final daysLeft = _trialDaysLeft();
    final status = cache.subscriptionStatus.trim().isEmpty
        ? tr.text('unknown')
        : cache.subscriptionStatus.trim();
    final storeName = cache.storeName.trim().isEmpty
        ? cache.storeSlug
        : cache.storeName.trim();

    return Column(
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
                          storeName.isEmpty ? tr.text('your_store') : storeName,
                          style: theme.textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
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
                title: tr.text('plan'),
                value: status == 'trial' ? tr.text('trial') : status,
                subtitle: tr.text('current_subscription'),
              ),
              _MetricCard(
                icon: Icons.event_available_outlined,
                title: tr.text('trial_remaining'),
                value: daysLeft == null
                    ? '—'
                    : tr.format('days_count', {'count': daysLeft}),
                subtitle: tr.format('ends_date',
                    {'date': _formatDate(context, cache.trialEndsAt)}),
              ),
              _MetricCard(
                icon: Icons.devices_outlined,
                title: tr.text('device_limit'),
                value: cache.devicesLimit?.toString() ?? '—',
                subtitle: tr.text('allowed_devices_for_store'),
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
                  tr.text('account_management'),
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  tr.text('account_management_description'),
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                _InfoRow(label: tr.text('account_id'), value: cache.accountId),
                _InfoRow(label: tr.text('store_id'), value: cache.storeId),
                _InfoRow(label: tr.text('store_slug'), value: cache.storeSlug),
                _InfoRow(
                    label: tr.text('last_verified'),
                    value: _formatDate(context, cache.lastVerifiedAt)),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    if (!widget.hasStoreIdentity)
                      FilledButton.icon(
                        onPressed: widget.hasLocalStoreData
                            ? null
                            : widget.onRecoverStoreIdentity,
                        icon: Icon(widget.hasLocalStoreData
                            ? Icons.lock_outline
                            : Icons.key_outlined),
                        label: Text(tr.text('recover_store_identity')),
                      )
                    else
                      FilledButton.icon(
                        onPressed: widget.onRecoverStoreData,
                        icon: Icon(widget.canRecoverStoreData
                            ? Icons.download_outlined
                            : Icons.lock_outline),
                        label: Text(tr.text('recover_store_data')),
                      ),
                    OutlinedButton.icon(
                      onPressed: () => setState(() => _selectedIndex = 1),
                      icon: const Icon(Icons.manage_accounts_outlined),
                      label: Text(tr.text('account_settings')),
                    ),
                    _ComingSoonButton(
                      icon: Icons.credit_card_outlined,
                      label: tr.text('manage_subscription'),
                    ),
                    _ComingSoonButton(
                      icon: Icons.devices_other_outlined,
                      label: tr.text('manage_devices'),
                    ),
                    _ComingSoonButton(
                      icon: Icons.storefront_outlined,
                      label: tr.text('online_store_settings'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        SyncMonitoringSection(store: widget.store),
      ],
    );
  }

  Widget _pageForSelection(BuildContext context) {
    switch (_selectedIndex) {
      case 1:
        return _buildAccountSettings(context);
      default:
        return _buildOverview(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final page = SafeArea(
      child: SingleChildScrollView(
        padding: VentioResponsive.pageInsets(context),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: _pageForSelection(context),
          ),
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(tr.text('store_account')),
        actions: [
          PopupMenuButton<Locale>(
            tooltip: tr.text('language'),
            onSelected: widget.onLocaleChanged,
            itemBuilder: (context) {
              final currentLocale = Localizations.localeOf(context);
              final isArabic = currentLocale.languageCode == 'ar';
              return [
                PopupMenuItem<Locale>(
                  value: const Locale('en'),
                  child: Row(children: [
                    const Text('🇺🇸'),
                    const SizedBox(width: 10),
                    Expanded(child: Text(tr.text('language_english'))),
                    if (!isArabic) const Icon(Icons.check, size: 18),
                  ]),
                ),
                PopupMenuItem<Locale>(
                  value: const Locale('ar'),
                  child: Row(children: [
                    const Text('🇱🇧'),
                    const SizedBox(width: 10),
                    Expanded(child: Text(tr.text('language_arabic'))),
                    if (isArabic) const Icon(Icons.check, size: 18),
                  ]),
                ),
              ];
            },
            icon: const Icon(Icons.language_outlined),
          ),
          TextButton.icon(
            onPressed: widget.onLogout,
            icon: const Icon(Icons.logout),
            label: Text(tr.text('logout')),
          ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: wide
          ? null
          : Drawer(
              child: _AccountNavigation(
                  selectedIndex: _selectedIndex,
                  onSelected: (index) {
                    Navigator.of(context).pop();
                    setState(() => _selectedIndex = index);
                  })),
      body: Row(
        children: [
          if (wide)
            _AccountNavigation(
              selectedIndex: _selectedIndex,
              onSelected: (index) => setState(() => _selectedIndex = index),
            ),
          Expanded(child: page),
        ],
      ),
    );
  }
}

class _AccountNavigation extends StatelessWidget {
  const _AccountNavigation(
      {required this.selectedIndex, required this.onSelected});

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return NavigationRail(
      selectedIndex: selectedIndex,
      onDestinationSelected: onSelected,
      extended: MediaQuery.sizeOf(context).width >= 1100,
      leading: const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Icon(Icons.storefront_outlined),
      ),
      destinations: [
        NavigationRailDestination(
          icon: Icon(Icons.dashboard_outlined),
          selectedIcon: Icon(Icons.dashboard),
          label: Text(AppLocalizations.of(context).text('overview')),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.manage_accounts_outlined),
          selectedIcon: Icon(Icons.manage_accounts),
          label: Text(AppLocalizations.of(context).text('account_settings')),
        ),
      ],
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
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
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
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(child: SelectableText(value.trim().isEmpty ? '—' : value)),
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
      label: Text(AppLocalizations.of(context)
          .format('coming_soon_label', {'label': label})),
    );
  }
}
