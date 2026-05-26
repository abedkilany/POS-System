import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/localization/app_localizations.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/responsive.dart';
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
        final isWide = constraints.maxWidth >= VentioResponsive.tabletBreakpoint;
        return Scaffold(
          appBar: AppBar(
            title: Text('$shellTitle • ${items[selectedIndex].label}', overflow: TextOverflow.ellipsis),
            actions: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth < 420
                      ? 72
                      : constraints.maxWidth < 720
                          ? 118
                          : VentioResponsive.clampToScreen(context, 360, min: 180, horizontalPadding: 220),
                ),
                child: HostConnectionIndicator(
                  store: widget.store,
                  compact: constraints.maxWidth < 720,
                ),
              ),
              if (constraints.maxWidth >= 720)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Center(
                      child: Text(widget.store.activeUser?.fullName ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
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
    final width = VentioResponsive.clampToScreen(
      context,
      VentioResponsive.adaptiveWidth(context, mobile: 0, tablet: 200, desktop: 224),
      min: 180,
      horizontalPadding: 0,
    );
    return SizedBox(
      width: width,
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
    required this.syncHealth,
  });

  final String roleLabel;
  final String roleMessage;
  final _TransportSnapshot lan;
  final _TransportSnapshot cloud;
  final _TransportSnapshot syncHealth;
}

class HostConnectionIndicator extends StatefulWidget {
  const HostConnectionIndicator({super.key, required this.store, this.compact = false});

  final AppStore store;
  final bool compact;

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
    syncHealth: _TransportSnapshot(label: 'Sync', state: _TransportState.checking, message: 'Checking sync health...'),
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

  String _t(String key) => AppLocalizations.of(context).text(key);

  String _roleLabel() {
    final identity = widget.store.appIdentity;
    if (identity.isHost) return _t('connection_role_host');
    if (identity.isClient) return _t('connection_role_client');
    return _t('connection_role_local');
  }

  String _roleMessage() {
    final identity = widget.store.appIdentity;
    if (identity.isHost) return _t('connection_role_host_desc');
    if (identity.isClient) return _t('connection_role_client_desc');
    return _t('connection_role_local_desc');
  }

  Future<_TransportSnapshot> _readLanStatus() async {
    if (kIsWeb) {
      return _TransportSnapshot(
        label: _t('connection_lan'),
        state: _TransportState.disabled,
        message: _t('connection_lan_web_disabled'),
      );
    }

    if (!UnifiedSyncFactory.isLanSetupComplete) {
      return _TransportSnapshot(
        label: _t('connection_lan'),
        state: _TransportState.disabled,
        message: _t('connection_lan_not_configured'),
      );
    }

    if (UnifiedSyncFactory.isLanHost || widget.store.appIdentity.isHost) {
      return _TransportSnapshot(
        label: _t('connection_lan'),
        state: _TransportState.active,
        message: _t('connection_lan_host_active'),
      );
    }

    try {
      final status = await UnifiedSyncFactory.lanEngine(widget.store).getHostStatus();
      if (status.hostReachable) {
        return _TransportSnapshot(
          label: _t('connection_lan'),
          state: _TransportState.online,
          message: status.message.isEmpty ? _t('connection_lan_host_reachable') : status.message,
          lastSeenAt: status.lastSeenAt ?? DateTime.now(),
        );
      }
      return _TransportSnapshot(
        label: _t('connection_lan'),
        state: _TransportState.offline,
        message: status.message.isEmpty ? _t('connection_lan_host_offline') : status.message,
        lastSeenAt: status.lastSeenAt,
      );
    } catch (error) {
      return _TransportSnapshot(
        label: _t('connection_lan'),
        state: _TransportState.error,
        message: "${_t('connection_lan_check_failed')}: $error",
      );
    }
  }

  Future<_TransportSnapshot> _readCloudStatus() async {
    final pending = widget.store.pendingSyncCount;
    final provisioning = widget.store.appIdentity.isClient && CloudProvisioningStatus.isPending;

    if (!UnifiedSyncFactory.cloudCanCheck(widget.store)) {
      return _TransportSnapshot(
        label: _t('connection_cloud'),
        state: _TransportState.notConfigured,
        message: _t('connection_cloud_not_configured'),
      );
    }

    try {
      final status = await UnifiedSyncFactory.cloudEngine(widget.store).getHostStatus();

      if (provisioning) {
        return _TransportSnapshot(
          label: _t('connection_cloud'),
          state: _TransportState.provisioning,
          message: '${CloudProvisioningStatus.message} ${status.message}'.trim(),
          lastSeenAt: status.lastSeenAt,
        );
      }

      if (!status.cloudReachable) {
        return _TransportSnapshot(
          label: _t('connection_cloud'),
          state: _TransportState.offline,
          message: status.message.isEmpty ? _t('connection_cloud_unreachable') : status.message,
          lastSeenAt: status.lastSeenAt,
        );
      }

      if (pending > 0) {
        return _TransportSnapshot(
          label: _t('connection_cloud'),
          state: _TransportState.pending,
          message: "${_t('connection_cloud_pending_prefix')} $pending ${_t('connection_cloud_pending_suffix')}",
          lastSeenAt: status.lastSeenAt ?? DateTime.now(),
        );
      }

      if (widget.store.appIdentity.isHost) {
        return _TransportSnapshot(
          label: _t('connection_cloud'),
          state: status.hostReachable ? _TransportState.online : _TransportState.pending,
          message: status.hostReachable
              ? _t('connection_cloud_host_heartbeat_active')
              : _t('connection_cloud_waiting_heartbeat'),
          lastSeenAt: status.lastSeenAt,
        );
      }

      if (status.hostReachable) {
        return _TransportSnapshot(
          label: _t('connection_cloud'),
          state: _TransportState.online,
          message: status.message.isEmpty ? _t('connection_cloud_host_reachable') : status.message,
          lastSeenAt: status.lastSeenAt ?? DateTime.now(),
        );
      }

      return _TransportSnapshot(
        label: _t('connection_cloud'),
        state: _TransportState.offline,
        message: status.lastSeenAt == null ? _t('connection_no_host_heartbeat') : _t('connection_host_heartbeat_stale'),
        lastSeenAt: status.lastSeenAt,
      );
    } catch (error) {
      return _TransportSnapshot(
        label: _t('connection_cloud'),
        state: _TransportState.error,
        message: "${_t('connection_cloud_check_failed')}: $error",
      );
    }
  }

  _TransportSnapshot _readSyncHealthStatus() {
    final pending = widget.store.pendingSyncCount;
    if (CloudProvisioningStatus.isPending) {
      return _TransportSnapshot(
        label: _t('connection_sync_health'),
        state: _TransportState.provisioning,
        message: _t('connection_sync_provisioning'),
      );
    }
    if (pending > 0) {
      return _TransportSnapshot(
        label: _t('connection_sync_health'),
        state: _TransportState.pending,
        message: '${_t('connection_sync_pending_prefix')} $pending ${_t('connection_sync_pending_suffix')}',
      );
    }
    return _TransportSnapshot(
      label: _t('connection_sync_health'),
      state: _TransportState.active,
      message: _t('connection_sync_healthy'),
    );
  }

  Future<void> _refresh() async {
    final checking = _ConnectionStatusSnapshot(
      roleLabel: _roleLabel(),
      roleMessage: _roleMessage(),
      lan: _TransportSnapshot(label: _t('connection_lan'), state: _TransportState.checking, message: _t('connection_lan_checking')),
      cloud: _TransportSnapshot(label: _t('connection_cloud'), state: _TransportState.checking, message: _t('connection_cloud_checking')),
      syncHealth: _TransportSnapshot(label: _t('connection_sync_health'), state: _TransportState.checking, message: _t('connection_sync_checking')),
    );
    if (mounted) setState(() => _snapshot = checking);

    final lan = await _readLanStatus();
    final cloud = await _readCloudStatus();
    final syncHealth = _readSyncHealthStatus();
    if (!mounted) return;
    setState(() {
      _snapshot = _ConnectionStatusSnapshot(
        roleLabel: _roleLabel(),
        roleMessage: _roleMessage(),
        lan: lan,
        cloud: cloud,
        syncHealth: syncHealth,
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
      _TransportState.active => _t('connection_state_active'),
      _TransportState.online => _t('connection_state_online'),
      _TransportState.pending => _t('connection_state_pending'),
      _TransportState.provisioning => _t('connection_state_provisioning'),
      _TransportState.offline => _t('connection_state_offline'),
      _TransportState.error => _t('connection_state_error'),
      _TransportState.checking => _t('connection_state_checking'),
      _TransportState.disabled => _t('connection_state_disabled'),
      _TransportState.notConfigured => _t('connection_state_not_configured'),
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
    final syncHealth = _snapshot.syncHealth;
    final tooltip = [
      _snapshot.roleLabel,
      _snapshot.roleMessage,
      "${_t('connection_lan')}: ${_stateText(lan.state)}${_lastSeenText(lan.lastSeenAt)} — ${lan.message}",
      "${_t('connection_cloud')}: ${_stateText(cloud.state)}${_lastSeenText(cloud.lastSeenAt)} — ${cloud.message}",
    ].join('\n');

    final chips = <Widget>[
      _chip(context, _snapshot.roleLabel, _TransportState.online, role: true),
      _chip(context, _t('connection_lan'), lan.state),
      _chip(context, _t('connection_cloud'), cloud.state),
      _chip(context, _t('connection_sync_health'), syncHealth.state),
    ];

    if (widget.compact) {
      return Padding(
        padding: const EdgeInsetsDirectional.only(end: 2),
        child: Tooltip(
          message: tooltip,
          child: PopupMenuButton<void>(
            tooltip: tooltip,
            constraints: BoxConstraints(minWidth: 200, maxWidth: VentioResponsive.modalMaxWidth(context, 280)),
            onOpened: _refresh,
            itemBuilder: (context) => [
              PopupMenuItem<void>(enabled: false, child: Text(_snapshot.roleLabel, style: Theme.of(context).textTheme.titleSmall)),
              PopupMenuItem<void>(enabled: false, child: Text('${_t('connection_lan')}: ${_stateText(lan.state)}')),
              PopupMenuItem<void>(enabled: false, child: Text('${_t('connection_cloud')}: ${_stateText(cloud.state)}')),
              PopupMenuItem<void>(enabled: false, child: Text('${_t('connection_sync_health')}: ${_stateText(syncHealth.state)}')),
              PopupMenuItem<void>(enabled: false, child: Text(_snapshot.roleMessage, maxLines: 2, overflow: TextOverflow.ellipsis)),
            ],
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: widget.compact ? 118 : VentioResponsive.clampToScreen(context, 220, min: 118)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lan_outlined, size: 14, color: _stateColor(context, lan.state)),
                  const SizedBox(width: 4),
                  Icon(Icons.cloud_outlined, size: 14, color: _stateColor(context, cloud.state)),
                  const SizedBox(width: 6),
                  Flexible(child: Text(_snapshot.roleLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelSmall)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 4),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: _refresh,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: VentioResponsive.clampToScreen(context, 360, min: 220, horizontalPadding: 160)),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: chips,
            ),
          ),
        ),
      ),
    );
  }
}
