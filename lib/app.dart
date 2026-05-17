import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/localization/app_localizations.dart';
import 'core/theme/app_theme.dart';
import 'core/sync_unified/sync_unified.dart';
import 'core/services/cloud_sync_service.dart';
import 'data/app_store.dart';
import 'models/user_role.dart';
import 'features/customers/customers_page.dart';
import 'features/dashboard/dashboard_page.dart';
import 'features/expenses/expenses_page.dart';
import 'features/inventory/inventory_page.dart';
import 'features/products/products_page.dart';
import 'features/purchases/purchases_page.dart';
import 'features/reports/reports_page.dart';
import 'features/sales/sales_page.dart';
import 'features/security/pin_lock_page.dart';
import 'features/settings/settings_page.dart';
import 'features/suppliers/suppliers_page.dart';

class StoreManagerApp extends StatefulWidget {
  const StoreManagerApp({super.key});

  @override
  State<StoreManagerApp> createState() => _StoreManagerAppState();
}

class _StoreManagerAppState extends State<StoreManagerApp> {
  Locale _locale = const Locale('en');
  ThemeMode _themeMode = ThemeMode.system;
  final AppStore _store = AppStore();
  late final UnifiedAutoLanSyncController _autoSyncController = UnifiedAutoLanSyncController(_store);
  late final UnifiedAutoCloudSyncController _autoCloudSyncController = UnifiedAutoCloudSyncController(_store);
  bool _syncStarted = false;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _store.initialize();
    final savedTheme = await _store.loadThemeMode();
    if (mounted) setState(() => _themeMode = savedTheme);
    if (_store.activeUser != null) {
      unawaited(_startSyncAfterLogin());
    }
  }


  Future<void> _startSyncAfterLogin() async {
    if (_syncStarted || _store.activeUser == null) return;
    _syncStarted = true;
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted || _store.activeUser == null) return;
    unawaited(_autoSyncController.start());
    unawaited(_autoCloudSyncController.start());
  }

  Future<void> _stopSyncForLogout() async {
    _syncStarted = false;
    await _autoSyncController.stop();
    _autoCloudSyncController.stop();
  }

  @override
  void dispose() {
    unawaited(_autoSyncController.stop());
    _autoCloudSyncController.stop();
    _store.dispose();
    super.dispose();
  }

  void _changeLocale(Locale locale) {
    setState(() => _locale = locale);
  }

  Future<void> _changeThemeMode(ThemeMode mode) async {
    await _store.saveThemeMode(mode);
    if (mounted) setState(() => _themeMode = mode);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) {
        if (_store.activeUser != null && !_syncStarted) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _startSyncAfterLogin());
        }
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Ventio',
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: _themeMode,
          locale: _locale,
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: _store.isReady
              ? PinLockPage(
                  store: _store,
                  child: MainShell(
                    store: _store,
                    onLogout: _stopSyncForLogout,
                    onLocaleChanged: _changeLocale,
                    onThemeModeChanged: _changeThemeMode,
                    themeMode: _themeMode,
                    onSyncSettingsChanged: () async {
                      _syncStarted = false;
                      unawaited(_startSyncAfterLogin());
                    },
                  ),
                )
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
  const MainShell({super.key, required this.onLocaleChanged, required this.onThemeModeChanged, required this.themeMode, required this.store, this.onSyncSettingsChanged, this.onLogout});

  final ValueChanged<Locale> onLocaleChanged;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ThemeMode themeMode;
  final AppStore store;
  final Future<void> Function()? onSyncSettingsChanged;
  final Future<void> Function()? onLogout;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final storeName = widget.store.storeProfile.name.trim();
    final shellTitle = storeName.isEmpty || storeName == 'My Store' ? 'Ventio' : storeName;
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
      if (widget.store.hasPermission(AppPermission.suppliersManage))
        _ShellItem(label: tr.text('purchases'), icon: Icons.add_shopping_cart_outlined, selectedIcon: Icons.add_shopping_cart, page: PurchasesPage(store: widget.store)),
      if (widget.store.hasPermission(AppPermission.expensesManage))
        _ShellItem(label: tr.text('expenses'), icon: Icons.payments_outlined, selectedIcon: Icons.payments, page: ExpensesPage(store: widget.store)),
      _ShellItem(label: tr.text('inventory'), icon: Icons.warehouse_outlined, selectedIcon: Icons.warehouse, page: InventoryPage(store: widget.store)),
      if (widget.store.hasPermission(AppPermission.reportsView))
        _ShellItem(label: tr.text('reports'), icon: Icons.bar_chart_outlined, selectedIcon: Icons.bar_chart, page: ReportsPage(store: widget.store)),
      _ShellItem(label: tr.text('settings'), icon: Icons.settings_outlined, selectedIcon: Icons.settings, page: SettingsPage(store: widget.store, onLocaleChanged: widget.onLocaleChanged, onThemeModeChanged: widget.onThemeModeChanged, themeMode: widget.themeMode, onSyncSettingsChanged: widget.onSyncSettingsChanged)),
    ];
    if (selectedIndex >= items.length) selectedIndex = items.length - 1;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1100;
        return Scaffold(
          appBar: AppBar(
            title: Text('$shellTitle • ${items[selectedIndex].label}', overflow: TextOverflow.ellipsis),
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
                  await widget.onLogout?.call();
                  await widget.store.logout();
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
                    _WideSideNavigation(
                      items: items,
                      selectedIndex: selectedIndex,
                      onSelected: (value) => setState(() => selectedIndex = value),
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



class _WideSideNavigation extends StatelessWidget {
  const _WideSideNavigation({required this.items, required this.selectedIndex, required this.onSelected});

  final List<_ShellItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 224,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: colorScheme.primaryContainer,
                    foregroundColor: colorScheme.onPrimaryContainer,
                    child: const Icon(Icons.flash_on_rounded),
                  ),
                  const SizedBox(width: 10),
                  Text('Ventio', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  final selected = index == selectedIndex;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: NavigationRailDestinationListTile(
                      icon: selected ? item.selectedIcon : item.icon,
                      label: item.label,
                      selected: selected,
                      onTap: () => onSelected(index),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NavigationRailDestinationListTile extends StatelessWidget {
  const NavigationRailDestinationListTile({super.key, required this.icon, required this.label, required this.selected, required this.onTap});

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? colorScheme.primaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: ListTile(
        dense: true,
        selected: selected,
        leading: Icon(icon, color: selected ? colorScheme.onPrimaryContainer : null),
        title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        onTap: onTap,
      ),
    );
  }
}

enum _TransportState { checking, active, online, pending, provisioning, offline, error, disabled, notConfigured }

class _TransportSnapshot {
  const _TransportSnapshot({
    required this.label,
    required this.state,
    required this.message,
    this.lastSeenAt,
  });

  final String label;
  final _TransportState state;
  final String message;
  final DateTime? lastSeenAt;
}

class _ConnectionStatusSnapshot {
  const _ConnectionStatusSnapshot({
    required this.roleLabel,
    required this.roleMessage,
    required this.lan,
    required this.cloud,
  });

  final String roleLabel;
  final String roleMessage;
  final _TransportSnapshot lan;
  final _TransportSnapshot cloud;
}

class HostConnectionIndicator extends StatefulWidget {
  const HostConnectionIndicator({super.key, required this.store});

  final AppStore store;

  @override
  State<HostConnectionIndicator> createState() => _HostConnectionIndicatorState();
}

class _HostConnectionIndicatorState extends State<HostConnectionIndicator> {
  Timer? _timer;
  bool _didStartRefreshLoop = false;
  _ConnectionStatusSnapshot _snapshot = const _ConnectionStatusSnapshot(
    roleLabel: 'Device',
    roleMessage: 'Checking device role...',
    lan: _TransportSnapshot(label: 'LAN', state: _TransportState.checking, message: 'Checking LAN status...'),
    cloud: _TransportSnapshot(label: 'Cloud', state: _TransportState.checking, message: 'Checking Cloud status...'),
  );

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didStartRefreshLoop) return;
    _didStartRefreshLoop = true;
    _refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _roleLabel() {
    final identity = widget.store.appIdentity;
    if (identity.isHost) return 'Host Device';
    if (identity.isClient) return 'Client Device';
    return 'Local Device';
  }

  String _roleMessage() {
    final identity = widget.store.appIdentity;
    if (identity.isHost) return 'This device is the main store Host. LAN and Cloud are shown separately.';
    if (identity.isClient) return 'This device is connected as a Client. Host reachability is shown by transport.';
    return 'This device is running locally without a paired Host.';
  }

  Future<_TransportSnapshot> _readLanStatus() async {
    if (kIsWeb) {
      return const _TransportSnapshot(
        label: 'LAN',
        state: _TransportState.disabled,
        message: 'LAN is not available in the web build.',
      );
    }

    if (!UnifiedSyncFactory.isLanSetupComplete) {
      return const _TransportSnapshot(
        label: 'LAN',
        state: _TransportState.disabled,
        message: 'LAN is not configured on this device.',
      );
    }

    if (UnifiedSyncFactory.isLanHost || widget.store.appIdentity.isHost) {
      return const _TransportSnapshot(
        label: 'LAN',
        state: _TransportState.active,
        message: 'LAN Host is active on this device.',
      );
    }

    try {
      final status = await UnifiedSyncFactory.lanEngine(widget.store).getHostStatus();
      if (status.hostReachable) {
        return _TransportSnapshot(
          label: 'LAN',
          state: _TransportState.online,
          message: status.message.isEmpty ? 'LAN Host is reachable.' : status.message,
          lastSeenAt: status.lastSeenAt ?? DateTime.now(),
        );
      }
      return _TransportSnapshot(
        label: 'LAN',
        state: _TransportState.offline,
        message: status.message.isEmpty ? 'LAN Host is offline.' : status.message,
        lastSeenAt: status.lastSeenAt,
      );
    } catch (error) {
      return _TransportSnapshot(
        label: 'LAN',
        state: _TransportState.error,
        message: 'LAN status check failed: $error',
      );
    }
  }

  Future<_TransportSnapshot> _readCloudStatus() async {
    final pending = widget.store.pendingSyncCount;
    final provisioning = widget.store.appIdentity.isClient && CloudProvisioningStatus.isPending;

    if (!UnifiedSyncFactory.cloudCanCheck(widget.store)) {
      return const _TransportSnapshot(
        label: 'Cloud',
        state: _TransportState.notConfigured,
        message: 'Cloud is not configured on this device.',
      );
    }

    try {
      final status = await UnifiedSyncFactory.cloudEngine(widget.store).getHostStatus();

      if (provisioning) {
        return _TransportSnapshot(
          label: 'Cloud',
          state: _TransportState.provisioning,
          message: '${CloudProvisioningStatus.message} ${status.message}'.trim(),
          lastSeenAt: status.lastSeenAt,
        );
      }

      if (!status.cloudReachable) {
        return _TransportSnapshot(
          label: 'Cloud',
          state: _TransportState.offline,
          message: status.message.isEmpty ? 'Cloud is unreachable.' : status.message,
          lastSeenAt: status.lastSeenAt,
        );
      }

      if (pending > 0) {
        return _TransportSnapshot(
          label: 'Cloud',
          state: _TransportState.pending,
          message: '$pending pending change(s) waiting for sync.',
          lastSeenAt: status.lastSeenAt ?? DateTime.now(),
        );
      }

      if (widget.store.appIdentity.isHost) {
        return _TransportSnapshot(
          label: 'Cloud',
          state: status.hostReachable ? _TransportState.online : _TransportState.pending,
          message: status.hostReachable
              ? 'Cloud heartbeat is active for this Host.'
              : 'Cloud is reachable. Waiting for this Host heartbeat to publish.',
          lastSeenAt: status.lastSeenAt,
        );
      }

      if (status.hostReachable) {
        return _TransportSnapshot(
          label: 'Cloud',
          state: _TransportState.online,
          message: status.message.isEmpty ? 'Cloud Host is reachable.' : status.message,
          lastSeenAt: status.lastSeenAt ?? DateTime.now(),
        );
      }

      return _TransportSnapshot(
        label: 'Cloud',
        state: _TransportState.offline,
        message: status.lastSeenAt == null ? 'No Host heartbeat has been published yet.' : 'Host heartbeat is stale.',
        lastSeenAt: status.lastSeenAt,
      );
    } catch (error) {
      return _TransportSnapshot(
        label: 'Cloud',
        state: _TransportState.error,
        message: 'Cloud status check failed: $error',
      );
    }
  }

  Future<void> _refresh() async {
    final checking = _ConnectionStatusSnapshot(
      roleLabel: _roleLabel(),
      roleMessage: _roleMessage(),
      lan: const _TransportSnapshot(label: 'LAN', state: _TransportState.checking, message: 'Checking LAN status...'),
      cloud: const _TransportSnapshot(label: 'Cloud', state: _TransportState.checking, message: 'Checking Cloud status...'),
    );
    if (mounted) setState(() => _snapshot = checking);

    final lan = await _readLanStatus();
    final cloud = await _readCloudStatus();
    if (!mounted) return;
    setState(() {
      _snapshot = _ConnectionStatusSnapshot(
        roleLabel: _roleLabel(),
        roleMessage: _roleMessage(),
        lan: lan,
        cloud: cloud,
      );
    });
  }

  Color _stateColor(BuildContext context, _TransportState state) {
    final theme = Theme.of(context);
    return switch (state) {
      _TransportState.active => Colors.green,
      _TransportState.online => Colors.green,
      _TransportState.pending => Colors.orange,
      _TransportState.provisioning => Colors.blue,
      _TransportState.offline => theme.colorScheme.error,
      _TransportState.error => theme.colorScheme.error,
      _TransportState.checking => Colors.amber,
      _TransportState.disabled => Colors.grey,
      _TransportState.notConfigured => Colors.grey,
    };
  }

  String _stateText(_TransportState state) {
    return switch (state) {
      _TransportState.active => 'Active',
      _TransportState.online => 'Online',
      _TransportState.pending => 'Pending',
      _TransportState.provisioning => 'Provisioning',
      _TransportState.offline => 'Offline',
      _TransportState.error => 'Error',
      _TransportState.checking => 'Checking',
      _TransportState.disabled => 'Disabled',
      _TransportState.notConfigured => 'Not Configured',
    };
  }

  String _lastSeenText(DateTime? value) {
    if (value == null) return '';
    final local = value.toLocal();
    return ' • ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  Widget _chip(BuildContext context, String label, _TransportState state, {bool role = false}) {
    final theme = Theme.of(context);
    final color = role ? Colors.blue : _stateColor(context, state);
    final text = role ? label : '$label ${_stateText(state)}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        border: Border.all(color: color.withValues(alpha: 0.42)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, color: color, size: 8),
          const SizedBox(width: 5),
          Text(text, style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lan = _snapshot.lan;
    final cloud = _snapshot.cloud;
    final tooltip = [
      _snapshot.roleLabel,
      _snapshot.roleMessage,
      'LAN: ${_stateText(lan.state)}${_lastSeenText(lan.lastSeenAt)} — ${lan.message}',
      'Cloud: ${_stateText(cloud.state)}${_lastSeenText(cloud.lastSeenAt)} — ${cloud.message}',
    ].join('\n');

    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: _refresh,
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _chip(context, _snapshot.roleLabel, _TransportState.online, role: true),
              _chip(context, 'LAN', lan.state),
              _chip(context, 'Cloud', cloud.state),
            ],
          ),
        ),
      ),
    );
  }
}
