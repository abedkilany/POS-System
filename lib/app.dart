import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/localization/app_localizations.dart';
import 'core/theme/app_theme.dart';
import 'core/services/lan_sync_service.dart';
import 'core/services/cloud_sync_service.dart';
import 'data/app_store.dart';
import 'models/user_role.dart';
import 'models/app_identity.dart';
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
            title: Text(isWide ? '${widget.store.storeProfile.name} • ${items[selectedIndex].label}' : items[selectedIndex].label),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(46),
              child: ConnectionStatusBar(store: widget.store),
            ),
            actions: [
              if (isWide)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Center(child: Text(widget.store.activeUser?.fullName ?? '')),
                ),
              IconButton(
                tooltip: 'Logout',
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


class ConnectionStatusBar extends StatelessWidget {
  const ConnectionStatusBar({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final status = _ConnectionStatus.fromStore(store);
    final theme = Theme.of(context);
    final isCompact = MediaQuery.sizeOf(context).width < 520;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: EdgeInsets.symmetric(horizontal: isCompact ? 10 : 14, vertical: 8),
        decoration: BoxDecoration(
          color: status.color.withOpacity(0.13),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: status.color.withOpacity(0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(status.icon, size: 18, color: status.color),
            const SizedBox(width: 8),
            Text(
              status.label,
              style: theme.textTheme.labelLarge?.copyWith(color: status.color, fontWeight: FontWeight.w800),
            ),
            if (!isCompact) ...[
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  status.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ],
            if (store.pendingSyncCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: status.color.withOpacity(0.16), borderRadius: BorderRadius.circular(999)),
                child: Text('${store.pendingSyncCount} pending', style: theme.textTheme.labelSmall?.copyWith(color: status.color, fontWeight: FontWeight.w700)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ConnectionStatus {
  const _ConnectionStatus({required this.label, required this.description, required this.color, required this.icon});

  final String label;
  final String description;
  final Color color;
  final IconData icon;

  static _ConnectionStatus fromStore(AppStore store) {
    final identity = store.appIdentity;
    final cloudSettings = CloudSyncSettings.load();
    final lanReady = !kIsWeb && LanSyncSettings.load().setupComplete;
    if (identity.isCloudEnabled && cloudSettings.isConfigured) {
      return const _ConnectionStatus(
        label: 'Online',
        description: 'Cloud sync is enabled',
        color: Color(0xFF15803D),
        icon: Icons.cloud_done_outlined,
      );
    }
    if (identity.syncMode == SyncMode.lanOnly && lanReady) {
      return _ConnectionStatus(
        label: 'LAN',
        description: identity.isHost ? 'Local network host' : 'Connected through local network',
        color: const Color(0xFF2563EB),
        icon: Icons.hub_outlined,
      );
    }
    return const _ConnectionStatus(
      label: 'Offline',
      description: 'Local device only; changes will wait for sync',
      color: Color(0xFFB45309),
      icon: Icons.cloud_off_outlined,
    );
  }
}
