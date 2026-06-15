import 'package:flutter/material.dart';

import '../../core/services/account_auth_service.dart';

class AdminSubscribersPage extends StatefulWidget {
  const AdminSubscribersPage({super.key});

  @override
  State<AdminSubscribersPage> createState() => _AdminSubscribersPageState();
}

class _AdminSubscribersPageState extends State<AdminSubscribersPage> {
  final AccountAuthService _service = AccountAuthService();
  final TextEditingController _searchController = TextEditingController();

  bool _loading = true;
  String _error = '';
  String _statusFilter = 'all';
  Map<String, dynamic> _summary = const <String, dynamic>{};
  List<AdminSubscriber> _subscribers = const <AdminSubscriber>[];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    final cache = AccountAuthCache.load();
    final result = await _service.fetchAdminSubscribers(
      adminToken: cache?.adminToken ?? '',
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result.ok) {
        _summary = result.summary;
        _subscribers = result.subscribers;
      } else {
        _error = result.message;
      }
    });
  }

  List<AdminSubscriber> get _visibleSubscribers {
    final query = _searchController.text.trim().toLowerCase();
    return _subscribers.where((subscriber) {
      final status = subscriber.subscriptionStatus.toLowerCase().trim();
      if (_statusFilter != 'all' && status != _statusFilter) return false;
      if (query.isEmpty) return true;
      final haystack = <String>[
        subscriber.loginName,
        subscriber.username,
        subscriber.storeName,
        subscriber.storeSlug,
        subscriber.plan,
        subscriber.subscriptionStatus,
        subscriber.accountStatus,
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList(growable: false);
  }

  String _formatDate(DateTime? value) {
    if (value == null) return '-';
    final local = value.toLocal();
    String two(int input) => input.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  String _formatTrialDays(DateTime? value) {
    if (value == null) return 'No trial date';
    final now = DateTime.now();
    final diff = value.toLocal().difference(now);
    if (diff.inMinutes < 0) return 'Expired';
    if (diff.inHours < 24) return '${diff.inHours.clamp(0, 23)}h left';
    return '${diff.inDays + 1} days left';
  }

  int _summaryInt(String key) {
    return int.tryParse((_summary[key] ?? '0').toString()) ?? 0;
  }

  Color _statusColor(BuildContext context, String status) {
    final normalized = status.toLowerCase().trim();
    if (normalized == 'active' || normalized == 'trial') {
      return Colors.green.shade700;
    }
    if (normalized == 'past_due' || normalized == 'expired') {
      return Colors.orange.shade800;
    }
    if (normalized == 'blocked' || normalized == 'cancelled') {
      return Theme.of(context).colorScheme.error;
    }
    return Theme.of(context).colorScheme.onSurfaceVariant;
  }

  Color _statusBackground(BuildContext context, String status) {
    final color = _statusColor(context, status);
    return color.withValues(alpha: 0.10);
  }



  Future<void> _editSubscriber(AdminSubscriber subscriber) async {
    final usernameController = TextEditingController(text: subscriber.username);
    final fullNameController = TextEditingController(text: subscriber.fullName);
    final storeNameController = TextEditingController(text: subscriber.storeName);
    final storeSlugController = TextEditingController(text: subscriber.storeSlug);
    final devicesLimitController = TextEditingController(text: subscriber.devicesLimit <= 0 ? '2' : subscriber.devicesLimit.toString());
    final trialEndsController = TextEditingController(
      text: subscriber.trialEndsAt == null ? '' : subscriber.trialEndsAt!.toLocal().toIso8601String().split('.').first,
    );
    String accountStatus = subscriber.accountStatus.isEmpty ? 'active' : subscriber.accountStatus;
    String plan = subscriber.plan.isEmpty ? 'trial' : subscriber.plan;
    String subscriptionStatus = subscriber.subscriptionStatus.isEmpty ? 'trial' : subscriber.subscriptionStatus;
    var cloudSyncEnabled = subscriber.cloudSyncEnabled;
    String? localError;

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Edit subscriber'),
              content: SizedBox(
                width: 560,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (localError != null) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(localError!, style: TextStyle(color: theme.colorScheme.onErrorContainer)),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Row(
                        children: [
                          Expanded(child: TextField(controller: usernameController, decoration: const InputDecoration(labelText: 'Username'))),
                          const SizedBox(width: 12),
                          Expanded(child: TextField(controller: storeSlugController, decoration: const InputDecoration(labelText: 'Store slug'))),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(controller: storeNameController, decoration: const InputDecoration(labelText: 'Store name')),
                      const SizedBox(height: 12),
                      TextField(controller: fullNameController, decoration: const InputDecoration(labelText: 'Full name / note')),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: accountStatus,
                              decoration: const InputDecoration(labelText: 'Account status'),
                              items: const [
                                DropdownMenuItem(value: 'active', child: Text('Active')),
                                DropdownMenuItem(value: 'blocked', child: Text('Blocked')),
                                DropdownMenuItem(value: 'suspended', child: Text('Suspended')),
                              ],
                              onChanged: (value) => setDialogState(() => accountStatus = value ?? 'active'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: plan,
                              decoration: const InputDecoration(labelText: 'Plan'),
                              items: const [
                                DropdownMenuItem(value: 'trial', child: Text('Trial')),
                                DropdownMenuItem(value: 'basic', child: Text('Basic')),
                                DropdownMenuItem(value: 'pro', child: Text('Pro')),
                              ],
                              onChanged: (value) => setDialogState(() => plan = value ?? 'trial'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: subscriptionStatus,
                              decoration: const InputDecoration(labelText: 'Subscription status'),
                              items: const [
                                DropdownMenuItem(value: 'trial', child: Text('Trial')),
                                DropdownMenuItem(value: 'active', child: Text('Active')),
                                DropdownMenuItem(value: 'expired', child: Text('Expired')),
                                DropdownMenuItem(value: 'past_due', child: Text('Past due')),
                                DropdownMenuItem(value: 'cancelled', child: Text('Cancelled')),
                                DropdownMenuItem(value: 'blocked', child: Text('Blocked')),
                              ],
                              onChanged: (value) => setDialogState(() => subscriptionStatus = value ?? 'trial'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: devicesLimitController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Device limit'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: trialEndsController,
                        decoration: const InputDecoration(
                          labelText: 'Trial ends at',
                          helperText: 'Example: 2026-06-28T19:08:06 or leave empty',
                        ),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Cloud Sync'),
                        subtitle: const Text('Allow this store to use Cloud Sync.'),
                        value: cloudSyncEnabled,
                        onChanged: (value) =>
                            setDialogState(() => cloudSyncEnabled = value),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
                FilledButton.icon(
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save'),
                  onPressed: () async {
                    final username = usernameController.text.trim().toLowerCase();
                    final storeName = storeNameController.text.trim();
                    final storeSlug = storeSlugController.text.trim().toLowerCase();
                    final limit = int.tryParse(devicesLimitController.text.trim()) ?? 0;
                    final trialText = trialEndsController.text.trim();
                    final trialEndsAt = trialText.isEmpty ? null : DateTime.tryParse(trialText);
                    if (username.isEmpty || username.contains(' ')) {
                      setDialogState(() => localError = 'Username is required and must not contain spaces.');
                      return;
                    }
                    if (storeName.isEmpty) {
                      setDialogState(() => localError = 'Store name is required.');
                      return;
                    }
                    if (storeSlug.isEmpty || storeSlug.contains(' ')) {
                      setDialogState(() => localError = 'Store slug is required and must not contain spaces.');
                      return;
                    }
                    if (limit <= 0) {
                      setDialogState(() => localError = 'Device limit must be greater than zero.');
                      return;
                    }
                    if (trialText.isNotEmpty && trialEndsAt == null) {
                      setDialogState(() => localError = 'Trial date format is invalid.');
                      return;
                    }
                    final cache = AccountAuthCache.load();
                    final result = await _service.updateAdminSubscriber(
                      adminToken: cache?.adminToken ?? '',
                      subscriber: subscriber,
                      username: username,
                      fullName: fullNameController.text,
                      storeName: storeName,
                      storeSlug: storeSlug,
                      accountStatus: accountStatus,
                      plan: plan,
                      subscriptionStatus: subscriptionStatus,
                      devicesLimit: limit,
                      cloudSyncEnabled: cloudSyncEnabled,
                      trialEndsAt: trialEndsAt,
                    );
                    if (!context.mounted) return;
                    if (!result.ok) {
                      setDialogState(() => localError = result.message);
                      return;
                    }
                    Navigator.of(dialogContext).pop(true);
                  },
                ),
              ],
            );
          },
        );
      },
    );
    usernameController.dispose();
    fullNameController.dispose();
    storeNameController.dispose();
    storeSlugController.dispose();
    devicesLimitController.dispose();
    trialEndsController.dispose();
    if (saved == true) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Subscriber updated.')));
      await _load();
    }
  }

  Future<void> _deleteSubscriber(AdminSubscriber subscriber) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete subscriber?'),
        content: Text('This will delete ${subscriber.loginName}, the linked store, subscription, and cloud sync records for that store. This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(dialogContext).colorScheme.error),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final cache = AccountAuthCache.load();
    final result = await _service.deleteAdminSubscriber(
      adminToken: cache?.adminToken ?? '',
      subscriber: subscriber,
    );
    if (!mounted) return;
    if (!result.ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Subscriber deleted.')));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visibleSubscribers = _visibleSubscribers;
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _AdminHeader(onRefresh: _loading ? null : _load),
            const SizedBox(height: 20),
            if (_error.isNotEmpty)
              _ErrorCard(message: _error, onRetry: _load)
            else ...[
              _OverviewGrid(
                accounts: _summaryInt('accounts'),
                stores: _summaryInt('stores'),
                trials: _summaryInt('trial_subscriptions'),
                active: _summaryInt('active_subscriptions'),
                expiredTrials: _summaryInt('expired_trials'),
              ),
              const SizedBox(height: 20),
              Card(
                elevation: 0,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                  side: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
                      child: _SubscribersToolbar(
                        count: visibleSubscribers.length,
                        total: _subscribers.length,
                        controller: _searchController,
                        statusFilter: _statusFilter,
                        onStatusChanged: (value) {
                          if (value == null) return;
                          setState(() => _statusFilter = value);
                        },
                      ),
                    ),
                    const Divider(height: 1),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.all(42),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (visibleSubscribers.isEmpty)
                      const _EmptyState()
                    else
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          headingRowHeight: 52,
                          dataRowMinHeight: 64,
                          dataRowMaxHeight: 74,
                          columns: const [
                            DataColumn(label: Text('Subscriber')),
                            DataColumn(label: Text('Store')),
                            DataColumn(label: Text('Plan')),
                            DataColumn(label: Text('Status')),
                            DataColumn(label: Text('Trial')),
                            DataColumn(label: Text('Devices')),
                            DataColumn(label: Text('Cloud Sync')),
                            DataColumn(label: Text('Created')),
                            DataColumn(label: Text('Last seen')),
                            DataColumn(label: Text('Actions')),
                          ],
                          rows: visibleSubscribers.map((subscriber) {
                            return DataRow(
                              cells: [
                                DataCell(_SubscriberIdentity(subscriber: subscriber)),
                                DataCell(_StoreCell(subscriber: subscriber)),
                                DataCell(_PlanBadge(plan: subscriber.plan)),
                                DataCell(_StatusBadge(
                                  label: subscriber.subscriptionStatus.isEmpty
                                      ? 'unknown'
                                      : subscriber.subscriptionStatus,
                                  color: _statusColor(context, subscriber.subscriptionStatus),
                                  background: _statusBackground(context, subscriber.subscriptionStatus),
                                )),
                                DataCell(_TrialCell(
                                  date: _formatDate(subscriber.trialEndsAt),
                                  remaining: _formatTrialDays(subscriber.trialEndsAt),
                                  isExpired: subscriber.trialEndsAt != null &&
                                      subscriber.trialEndsAt!.toLocal().isBefore(DateTime.now()),
                                )),
                                DataCell(Text('${subscriber.deviceCount}/${subscriber.devicesLimit}')),
                                DataCell(_StatusBadge(
                                  label: subscriber.cloudSyncEnabled ? 'enabled' : 'off',
                                  color: subscriber.cloudSyncEnabled
                                      ? Colors.green.shade700
                                      : Theme.of(context).colorScheme.onSurfaceVariant,
                                  background: subscriber.cloudSyncEnabled
                                      ? Colors.green.withValues(alpha: 0.10)
                                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                                )),
                                DataCell(Text(_formatDate(subscriber.createdAt))),
                                DataCell(Text(_formatDate(subscriber.lastSeenAt))),
                                DataCell(_ActionsCell(
                                  onEdit: () => _editSubscriber(subscriber),
                                  onDelete: () => _deleteSubscriber(subscriber),
                                )),
                              ],
                            );
                          }).toList(growable: false),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AdminHeader extends StatelessWidget {
  const _AdminHeader({required this.onRefresh});

  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primaryContainer,
            theme.colorScheme.surfaceContainerHighest,
          ],
        ),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(Icons.admin_panel_settings, color: theme.colorScheme.onPrimary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ventio Admin Console', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(
                  'Manage platform subscribers, stores, trial status, and device limits from one place.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
          ),
        ],
      ),
    );
  }
}

class _OverviewGrid extends StatelessWidget {
  const _OverviewGrid({
    required this.accounts,
    required this.stores,
    required this.trials,
    required this.active,
    required this.expiredTrials,
  });

  final int accounts;
  final int stores;
  final int trials;
  final int active;
  final int expiredTrials;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _SummaryCard(label: 'Accounts', value: accounts, icon: Icons.people_alt_outlined),
        _SummaryCard(label: 'Stores', value: stores, icon: Icons.storefront_outlined),
        _SummaryCard(label: 'Trials', value: trials, icon: Icons.hourglass_top_outlined),
        _SummaryCard(label: 'Active', value: active, icon: Icons.verified_outlined),
        _SummaryCard(label: 'Expired trials', value: expiredTrials, icon: Icons.warning_amber_outlined),
      ],
    );
  }
}

class _SubscribersToolbar extends StatelessWidget {
  const _SubscribersToolbar({
    required this.count,
    required this.total,
    required this.controller,
    required this.statusFilter,
    required this.onStatusChanged,
  });

  final int count;
  final int total;
  final TextEditingController controller;
  final String statusFilter;
  final ValueChanged<String?> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 320,
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Search username, store, plan...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              isDense: true,
            ),
          ),
        ),
        SizedBox(
          width: 180,
          child: DropdownButtonFormField<String>(
            initialValue: statusFilter,
            decoration: InputDecoration(
              labelText: 'Status',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              isDense: true,
            ),
            items: const [
              DropdownMenuItem(value: 'all', child: Text('All statuses')),
              DropdownMenuItem(value: 'trial', child: Text('Trial')),
              DropdownMenuItem(value: 'active', child: Text('Active')),
              DropdownMenuItem(value: 'expired', child: Text('Expired')),
              DropdownMenuItem(value: 'blocked', child: Text('Blocked')),
              DropdownMenuItem(value: 'cancelled', child: Text('Cancelled')),
            ],
            onChanged: onStatusChanged,
          ),
        ),
        Chip(
          avatar: const Icon(Icons.filter_list, size: 18),
          label: Text('$count of $total shown'),
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
        ),
      ],
    );
  }
}

class _SubscriberIdentity extends StatelessWidget {
  const _SubscriberIdentity({required this.subscriber});

  final AdminSubscriber subscriber;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 18,
          child: Text(
            subscriber.username.isEmpty ? '?' : subscriber.username.characters.first.toUpperCase(),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(width: 10),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subscriber.loginName, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(
              subscriber.accountStatus.isEmpty ? 'account' : subscriber.accountStatus,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ],
    );
  }
}

class _StoreCell extends StatelessWidget {
  const _StoreCell({required this.subscriber});

  final AdminSubscriber subscriber;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = subscriber.storeName.isEmpty ? subscriber.storeSlug : subscriber.storeName;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name.isEmpty ? '-' : name, style: const TextStyle(fontWeight: FontWeight.w700)),
        if (subscriber.storeSlug.isNotEmpty)
          Text('@${subscriber.storeSlug}', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

class _PlanBadge extends StatelessWidget {
  const _PlanBadge({required this.plan});

  final String plan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = plan.trim().isEmpty ? '-' : plan.trim();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: TextStyle(color: theme.colorScheme.onSecondaryContainer, fontWeight: FontWeight.w700)),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color, required this.background});

  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800)),
    );
  }
}

class _TrialCell extends StatelessWidget {
  const _TrialCell({required this.date, required this.remaining, required this.isExpired});

  final String date;
  final String remaining;
  final bool isExpired;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(date),
        Text(
          remaining,
          style: theme.textTheme.bodySmall?.copyWith(
            color: isExpired ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}


class _ActionsCell extends StatelessWidget {
  const _ActionsCell({required this.onEdit, required this.onDelete});

  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: 'Edit subscriber',
          child: IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: onEdit,
          ),
        ),
        Tooltip(
          message: 'Delete subscriber',
          child: IconButton(
            icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
            onPressed: onDelete,
          ),
        ),
      ],
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: theme.colorScheme.error),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
            TextButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(44),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.inbox_outlined, size: 56, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text('No subscribers found', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('Try changing the search text or status filter.', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.label, required this.value, required this.icon});

  final String label;
  final int value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 188,
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: theme.colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    Text(value.toString(), style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
