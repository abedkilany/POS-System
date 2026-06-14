import 'package:flutter/material.dart';

import '../../core/services/account_auth_service.dart';

class AdminSubscribersPage extends StatefulWidget {
  const AdminSubscribersPage({super.key});

  @override
  State<AdminSubscribersPage> createState() => _AdminSubscribersPageState();
}

class _AdminSubscribersPageState extends State<AdminSubscribersPage> {
  final AccountAuthService _service = AccountAuthService();
  bool _loading = true;
  String _error = '';
  Map<String, dynamic> _summary = const <String, dynamic>{};
  List<AdminSubscriber> _subscribers = const <AdminSubscriber>[];

  @override
  void initState() {
    super.initState();
    _load();
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

  String _formatDate(DateTime? value) {
    if (value == null) return '-';
    final local = value.toLocal();
    String two(int input) => input.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Subscribers', style: theme.textTheme.headlineMedium),
                      const SizedBox(height: 6),
                      Text(
                        'Manage Ventio platform subscribers and trial accounts.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: _loading ? null : _load,
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (_error.isNotEmpty)
              Card(
                color: theme.colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: theme.colorScheme.error),
                      const SizedBox(width: 12),
                      Expanded(child: Text(_error)),
                    ],
                  ),
                ),
              )
            else ...[
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _SummaryCard(label: 'Accounts', value: _summaryInt('accounts')),
                  _SummaryCard(label: 'Stores', value: _summaryInt('stores')),
                  _SummaryCard(label: 'Trials', value: _summaryInt('trial_subscriptions')),
                  _SummaryCard(label: 'Active', value: _summaryInt('active_subscriptions')),
                  _SummaryCard(label: 'Expired trials', value: _summaryInt('expired_trials')),
                ],
              ),
              const SizedBox(height: 20),
              Card(
                clipBehavior: Clip.antiAlias,
                child: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : _subscribers.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(32),
                            child: Center(child: Text('No subscribers yet.')),
                          )
                        : SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              columns: const [
                                DataColumn(label: Text('Login')),
                                DataColumn(label: Text('Store')),
                                DataColumn(label: Text('Plan')),
                                DataColumn(label: Text('Status')),
                                DataColumn(label: Text('Trial ends')),
                                DataColumn(label: Text('Devices')),
                                DataColumn(label: Text('Created')),
                                DataColumn(label: Text('Last seen')),
                              ],
                              rows: _subscribers.map((subscriber) {
                                final statusColor = _statusColor(context, subscriber.subscriptionStatus);
                                return DataRow(
                                  cells: [
                                    DataCell(Text(subscriber.loginName)),
                                    DataCell(Text(subscriber.storeName.isEmpty
                                        ? subscriber.storeSlug
                                        : subscriber.storeName)),
                                    DataCell(Text(subscriber.plan.isEmpty ? '-' : subscriber.plan)),
                                    DataCell(Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: statusColor.withValues(alpha: 0.10),
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        subscriber.subscriptionStatus.isEmpty
                                            ? '-'
                                            : subscriber.subscriptionStatus,
                                        style: TextStyle(
                                          color: statusColor,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    )),
                                    DataCell(Text(_formatDate(subscriber.trialEndsAt))),
                                    DataCell(Text('${subscriber.deviceCount}/${subscriber.devicesLimit}')),
                                    DataCell(Text(_formatDate(subscriber.createdAt))),
                                    DataCell(Text(_formatDate(subscriber.lastSeenAt))),
                                  ],
                                );
                              }).toList(growable: false),
                            ),
                          ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 160,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Text(
                value.toString(),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
