import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/localization/app_localizations.dart';
import 'core/theme/app_theme.dart';
import 'core/services/lan_sync_service.dart';
import 'core/services/cloud_sync_service.dart';
import 'data/app_store.dart';
import 'models/user_role.dart';
import 'features/customers/customers_page.dart';
import 'features/dashboard/dashboard_page.dart';
import 'features/expenses/expenses_page.dart';
import 'features/inventory/inventory_page.dart';
import 'features/products/products_page.dart';
import 'features/reports/reports_page.dart';
import 'features/sales/sales_page.dart';
import 'features/security/pin_lock_page.dart';
import 'features/settings/settings_page.dart';
import 'features/settings/sync_setup_page.dart';
import 'features/suppliers/suppliers_page.dart';

class StoreManagerApp extends StatefulWidget {
  const StoreManagerApp({super.key});

  @override
  State<StoreManagerApp> createState() => _StoreManagerAppState();
}

class _StoreManagerAppState extends State<StoreManagerApp> {
  Locale _locale = const Locale('en');
  final AppStore _store = AppStore();
  late final AutoLanSyncController _autoSyncController = AutoLanSyncController(_store);
  late final AutoCloudSyncController _autoCloudSyncController = AutoCloudSyncController(_store);

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _store.initialize();
    await _autoSyncController.start();
    await _autoCloudSyncController.start();
  }

  @override
  void dispose() {
    _autoSyncController.stop();
    _autoCloudSyncController.stop();
    _store.dispose();
    super.dispose();
  }

  void _changeLocale(Locale locale) {
    setState(() => _locale = locale);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: _store.storeProfile.name,
          theme: AppTheme.lightTheme,
          locale: _locale,
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: _store.isReady
              ? (kIsWeb || LanSyncSettings.load().setupComplete
                  ? PinLockPage(store: _store, child: MainShell(store: _store, onLocaleChanged: _changeLocale))
                  : SyncSetupPage(
                      store: _store,
                      onDone: () async {
                        await _autoSyncController.start();
                        await _autoCloudSyncController.start();
                        if (mounted) setState(() {});
                      },
                    ))
              : const Scaffold(body: Center(child: CircularProgressIndicator())),
        );
      },
    );
  }
}

class _ShellItem {
  const _ShellItem({required this.label, required this.icon, required this.selectedIcon, required this.page});

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget page;
}

class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.onLocaleChanged, required this.store});

  final ValueChanged<Locale> onLocaleChanged;
  final AppStore store;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final items = [
      _ShellItem(label: tr.text('dashboard'), icon: Icons.dashboard_outlined, selectedIcon: Icons.dashboard, page: DashboardPage(store: widget.store)),
      if (widget.store.hasPermission(AppPermission.productsCreate) || widget.store.hasPermission(AppPermission.productsEdit) || widget.store.hasPermission(AppPermission.productsDelete))
        _ShellItem(label: tr.text('products'), icon: Icons.inventory_2_outlined, selectedIcon: Icons.inventory_2, page: ProductsPage(store: widget.store)),
      if (widget.store.hasPermission(AppPermission.customersManage))
        _ShellItem(label: tr.text('customers'), icon: Icons.people_outline, selectedIcon: Icons.people, page: CustomersPage(store: widget.store)),
      if (widget.store.hasPermission(AppPermission.suppliersManage))
        _ShellItem(label: tr.text('suppliers'), icon: Icons.local_shipping_outlined, selectedIcon: Icons.local_shipping, page: SuppliersPage(store: widget.store)),
      if (widget.store.hasPermission(AppPermission.salesCreate) || widget.store.hasPermission(AppPermission.salesCancel))
        _ShellItem(label: tr.text('sales'), icon: Icons.receipt_long_outlined, selectedIcon: Icons.receipt_long, page: SalesPage(store: widget.store)),
      if (widget.store.hasPermission(AppPermission.expensesManage))
        _ShellItem(label: tr.text('expenses'), icon: Icons.payments_outlined, selectedIcon: Icons.payments, page: ExpensesPage(store: widget.store)),
      _ShellItem(label: tr.text('inventory'), icon: Icons.warehouse_outlined, selectedIcon: Icons.warehouse, page: InventoryPage(store: widget.store)),
      if (widget.store.hasPermission(AppPermission.reportsView))
        _ShellItem(label: tr.text('reports'), icon: Icons.bar_chart_outlined, selectedIcon: Icons.bar_chart, page: ReportsPage(store: widget.store)),
      _ShellItem(label: tr.text('settings'), icon: Icons.settings_outlined, selectedIcon: Icons.settings, page: SettingsPage(store: widget.store, onLocaleChanged: widget.onLocaleChanged)),
    ];
    if (selectedIndex >= items.length) selectedIndex = items.length - 1;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1100;
        return Scaffold(
          appBar: AppBar(
            title: Text('${widget.store.storeProfile.name} • ${items[selectedIndex].label}'),
            actions: [
              HostConnectionIndicator(store: widget.store),
              if (constraints.maxWidth >= 520)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Center(child: Text(widget.store.activeUser?.fullName ?? '')),
                ),
              IconButton(
                tooltip: tr.text('logout'),
                onPressed: () async {
                  await widget.store.logout();
                  if (context.mounted) {
                    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => PinLockPage(store: widget.store, child: MainShell(store: widget.store, onLocaleChanged: widget.onLocaleChanged))));
                  }
                },
                icon: const Icon(Icons.logout),
              ),
            ],
          ),
          drawer: isWide
              ? null
              : Drawer(
                  child: SafeArea(
                    child: ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return ListTile(
                          leading: Icon(index == selectedIndex ? item.selectedIcon : item.icon),
                          title: Text(item.label),
                          selected: index == selectedIndex,
                          onTap: () {
                            Navigator.pop(context);
                            setState(() => selectedIndex = index);
                          },
                        );
                      },
                    ),
                  ),
                ),
          body: isWide
              ? Row(
                  children: [
                    NavigationRail(
                      selectedIndex: selectedIndex,
                      onDestinationSelected: (value) => setState(() => selectedIndex = value),
                      labelType: NavigationRailLabelType.all,
                      leading: const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircleAvatar(radius: 24, child: Icon(Icons.storefront)),
                      ),
                      destinations: [
                        for (final item in items)
                          NavigationRailDestination(
                            icon: Icon(item.icon),
                            selectedIcon: Icon(item.selectedIcon),
                            label: Text(item.label),
                          ),
                      ],
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: items[selectedIndex].page),
                  ],
                )
              : items[selectedIndex].page,
        );
      },
    );
  }
}


enum _HostReachability { disabled, hostDevice, checking, connected, pending, disconnected, cloudOffline }

class HostConnectionIndicator extends StatefulWidget {
  const HostConnectionIndicator({super.key, required this.store});

  final AppStore store;

  @override
  State<HostConnectionIndicator> createState() => _HostConnectionIndicatorState();
}

class _HostConnectionIndicatorState extends State<HostConnectionIndicator> {
  Timer? _timer;
  _HostReachability _state = _HostReachability.checking;
  DateTime? _lastOk;
  String _message = '';

  String trText(String key) => AppLocalizations.of(context).text(key);

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (kIsWeb) {
      final settings = CloudSyncSettings.load();
      if (!settings.isConfigured || !widget.store.appIdentity.isCloudEnabled) {
        if (mounted) setState(() { _state = _HostReachability.disabled; _message = trText('cloud_off'); });
        return;
      }
      if (mounted) setState(() => _state = _HostReachability.checking);
      final status = await CloudSyncService(widget.store).getHostHeartbeatStatus(settings);
      final pending = widget.store.pendingSyncCount;
      if (!mounted) return;
      setState(() {
        if (!status.cloudReachable) {
          _state = _HostReachability.cloudOffline;
          _message = status.message;
        } else if (status.hostReachable) {
          _lastOk = status.lastSeenAt ?? DateTime.now();
          _state = pending > 0 ? _HostReachability.pending : _HostReachability.connected;
          _message = pending > 0 ? trText('pending_changes').replaceAll('{count}', '$pending') : trText('host_heartbeat_fresh');
        } else {
          _lastOk = status.lastSeenAt;
          _state = _HostReachability.disconnected;
          _message = status.lastSeenAt == null ? trText('no_host_heartbeat') : trText('host_heartbeat_stale');
        }
      });
      return;
    }

    final settings = LanSyncSettings.load();
    if (!settings.setupComplete) {
      if (mounted) setState(() { _state = _HostReachability.disabled; _message = trText('lan_not_configured'); });
      return;
    }
    if (settings.isHost) {
      if (mounted) setState(() { _state = _HostReachability.hostDevice; _message = trText('this_device_is_host'); });
      return;
    }
    if (mounted) setState(() => _state = _HostReachability.checking);
    final result = await LanSyncService(widget.store).testConnection(settings.host, port: settings.port, token: settings.secret);
    final pending = widget.store.pendingSyncCount;
    if (!mounted) return;
    setState(() {
      if (result.ok) {
        _lastOk = DateTime.now();
        _state = pending > 0 ? _HostReachability.pending : _HostReachability.connected;
        _message = pending > 0 ? trText('pending_changes').replaceAll('{count}', '$pending') : trText('host_reachable');
      } else {
        _state = _HostReachability.disconnected;
        _message = result.message;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final color = switch (_state) {
      _HostReachability.connected => Colors.green,
      _HostReachability.pending => Colors.orange,
      _HostReachability.disconnected => theme.colorScheme.error,
      _HostReachability.cloudOffline => theme.colorScheme.error,
      _HostReachability.hostDevice => Colors.blue,
      _HostReachability.checking => Colors.amber,
      _HostReachability.disabled => Colors.grey,
    };
    final label = switch (_state) {
      _HostReachability.connected => tr.text('host_connected'),
      _HostReachability.pending => tr.text('sync_pending'),
      _HostReachability.disconnected => tr.text('host_offline'),
      _HostReachability.cloudOffline => tr.text('cloud_offline'),
      _HostReachability.hostDevice => tr.text('host_device'),
      _HostReachability.checking => kIsWeb ? tr.text('checking_cloud') : tr.text('checking_host'),
      _HostReachability.disabled => kIsWeb ? tr.text('cloud_off') : tr.text('lan_off'),
    };
    final last = _lastOk == null ? '' : ' • ${tr.text(kIsWeb ? 'last_seen' : 'last_ok')} ${_lastOk!.toLocal().hour.toString().padLeft(2, '0')}:${_lastOk!.toLocal().minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: Tooltip(
        message: '${tr.text('host_status')}: $label$last\n$_message',
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: _refresh,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.14),
              border: Border.all(color: color.withOpacity(0.45)),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, color: color, size: 10),
                const SizedBox(width: 6),
                Text(label, style: theme.textTheme.labelMedium),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
