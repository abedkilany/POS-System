import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';

import 'core/app_brand.dart';
import 'core/localization/app_localizations.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/responsive.dart';
import 'core/sync_unified/sync_unified.dart';
import 'core/sync_unified/sync_device_state.dart';
import 'core/snapshot/unified_snapshot_progress.dart';
import 'core/services/cloud_sync_service.dart';
import 'core/services/accounting_service.dart';
import 'core/services/google_drive_backup_service.dart';
import 'core/services/lan_sync_service.dart';
import 'core/services/local_auto_backup_service.dart';
import 'core/services/app_update_service.dart';
import 'core/services/account_auth_service.dart';
import 'core/repositories/auth_repository.dart';
import 'core/services/page_timing_scope.dart';
import 'core/services/startup_timing_service.dart';
import 'data/app_store.dart';
import 'features/accounting/accounting_page.dart';
import 'features/accounting/accounting_snapshot_service.dart';
import 'features/customers/customers_page.dart';
import 'features/dashboard/dashboard_page.dart';
import 'features/database/database_page.dart';
import 'features/expenses/expenses_page.dart';
import 'features/inventory/inventory_page.dart';
import 'features/inventory/manufacturing_page.dart';
import 'features/maintenance/maintenance_page.dart';
import 'features/products/products_page.dart';
import 'features/purchases/purchases_page.dart';
import 'features/reports/reports_page.dart';
import 'features/reports/reports_snapshot_service.dart';
import 'features/sales/sales_page.dart';
import 'features/sales/quotations_page.dart';
import 'features/sales/delivery_notes_page.dart';
import 'features/security/login_gate_page.dart';
import 'features/settings/settings_page.dart';
import 'features/admin/admin_subscribers_page.dart';
import 'features/suppliers/suppliers_page.dart';

class _AutoSnapshotProgressState {
  const _AutoSnapshotProgressState({
    this.transport = '',
    this.value,
    this.label = '',
  });

  final String transport;
  final double? value;
  final String label;
}

class VentioApp extends StatefulWidget {
  const VentioApp({super.key});

  @override
  State<VentioApp> createState() => _VentioAppState();
}

class _VentioAppState extends State<VentioApp> {
  static const ReportsSnapshotService _reportsSnapshotService =
      ReportsSnapshotService();
  static const AccountingSnapshotService _accountingSnapshotService =
      AccountingSnapshotService();

  Locale _locale = const Locale('en');
  ThemeMode _themeMode = ThemeMode.system;
  final AppStore _store = AppStore();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final ValueNotifier<_AutoSnapshotProgressState> _autoSnapshotProgress =
      ValueNotifier<_AutoSnapshotProgressState>(
          const _AutoSnapshotProgressState());
  late final UnifiedAutoLanSyncController _autoSyncController =
      UnifiedAutoLanSyncController(
    _store,
    onSnapshotProgress: _handleAutoSnapshotProgress,
  );
  late final UnifiedAutoCloudSyncController _autoCloudSyncController =
      UnifiedAutoCloudSyncController(
    _store,
    onSnapshotProgress: _handleAutoSnapshotProgress,
  );
  bool _syncStarted = false;
  Timer? _heavyCacheWarmTimer;
  bool _autoSnapshotProgressDialogOpen = false;
  bool _firstFrameMarked = false;

  @override
  void initState() {
    super.initState();
    _registerPageTimings();
    _initializeApp();
  }

  void _registerPageTimings() {
    const pages = <({String key, String label})>[
      (key: 'LoginGatePage', label: 'Login gate'),
      (key: 'MainShell', label: 'Main shell'),
      (key: 'DashboardPage', label: 'Dashboard'),
      (key: 'ProductsPage', label: 'Products'),
      (key: 'CustomersPage', label: 'Customers'),
      (key: 'SuppliersPage', label: 'Suppliers'),
      (key: 'SalesPage', label: 'Sales'),
      (key: 'QuotationsPage', label: 'Quotations'),
      (key: 'DeliveryNotesPage', label: 'Delivery notes'),
      (key: 'PurchasesPage', label: 'Purchases'),
      (key: 'ExpensesPage', label: 'Expenses'),
      (key: 'AccountingPage', label: 'Accounting'),
      (key: 'InventoryPage', label: 'Inventory'),
      (key: 'ManufacturingPage', label: 'Manufacturing'),
      (key: 'ReportsPage', label: 'Reports'),
      (key: 'MaintenancePage', label: 'Maintenance'),
      (key: 'StressLabPage', label: 'Stress lab'),
      (key: 'DatabasePage', label: 'Database'),
      (key: 'SettingsPage', label: 'Settings'),
      (key: 'AdminSubscribersPage', label: 'Admin subscribers'),
      (key: 'StoreAccountDashboardPage', label: 'Store account dashboard'),
      (key: 'PlatformAdminDashboardPage', label: 'Platform admin dashboard'),
      (key: 'DiagnosticsPage', label: 'Diagnostics'),
      (key: 'SyncSetupPage', label: 'Sync setup'),
      (key: 'UsersPermissionsPage', label: 'Users permissions'),
      (key: 'BarcodeScannerPage', label: 'Barcode scanner'),
      (key: '_NoAccessPage', label: 'No access'),
    ];
    for (final page in pages) {
      StartupTimingService.registerPage(
        pageKey: page.key,
        pageLabel: page.label,
      );
    }
  }

  Future<void> _initializeApp() async {
    await StartupTimingService.measure(
      'ventio_app.initialize',
      () async {
        await _store.initialize();
        final savedTheme = await _store.loadThemeMode();
        final savedLocale = await _store.loadLocale();
        if (mounted) {
          setState(() {
            _themeMode = savedTheme;
            _locale = savedLocale;
          });
        }
        _heavyCacheWarmTimer?.cancel();
        _heavyCacheWarmTimer = Timer(
          const Duration(milliseconds: 500),
          () {
            if (!mounted) return;
            unawaited(_primeHeavyCaches());
          },
        );
        if (_store.activeUser != null) {
          unawaited(_startSyncAfterLogin());
        }
      },
      category: 'ui',
    );
  }

  Future<void> _primeHeavyCaches() async {
    if (!mounted) return;
    try {
      await _reportsSnapshotService.prewarm(_store);
    } catch (error, stackTrace) {
      debugPrint('Reports prewarm failed: $error');
      debugPrint('$stackTrace');
    }
    if (!mounted) return;
    try {
      await _accountingSnapshotService.prewarm(_store);
    } catch (error, stackTrace) {
      debugPrint('Accounting prewarm failed: $error');
      debugPrint('$stackTrace');
    }
  }

  Future<void> _startSyncAfterLogin() async {
    if (_syncStarted || _store.activeUser == null) return;
    _syncStarted = true;
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted || _store.activeUser == null) return;
    unawaited(_autoSyncController.start());
    unawaited(_autoCloudSyncController.start());
    unawaited(LocalAutoBackupService.runDueBackup(_store));
    unawaited(GoogleDriveBackupService.runDueBackup(_store));
  }

  Future<void> _stopSyncForLogout() async {
    _syncStarted = false;
    await _autoSyncController.stop();
    _autoCloudSyncController.stop();
  }

  void _handleAutoSnapshotProgress(
      String transport, double value, String label) {
    if (!mounted || _store.activeUser == null) return;
    final safeValue = value.clamp(0.0, 1.0).toDouble();
    _autoSnapshotProgress.value = _AutoSnapshotProgressState(
      transport: transport,
      value: safeValue,
      label: label,
    );
    _showAutoSnapshotProgressDialog();
    if (safeValue >= 1.0) {
      Future<void>.delayed(const Duration(milliseconds: 900), () {
        if (!_autoSnapshotProgressDialogOpen) return;
        final current = _autoSnapshotProgress.value.value ?? 0;
        if (current >= 1.0) {
          _dismissAutoSnapshotProgressDialog();
        }
      });
    }
  }

  void _showAutoSnapshotProgressDialog() {
    if (_autoSnapshotProgressDialogOpen) return;
    final navigator = _navigatorKey.currentState;
    final dialogContext = _navigatorKey.currentContext;
    if (navigator == null || dialogContext == null) return;
    _autoSnapshotProgressDialogOpen = true;
    unawaited(showDialog<void>(
      context: dialogContext,
      barrierDismissible: false,
      builder: (context) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            contentPadding: const EdgeInsets.all(20),
            content: SizedBox(
              width: 560,
              child: ValueListenableBuilder<_AutoSnapshotProgressState>(
                valueListenable: _autoSnapshotProgress,
                builder: (context, state, _) => UnifiedSnapshotProgressView(
                  value: state.value,
                  label: state.label.isEmpty
                      ? localizeRuntimeMessage(
                          'Host restored data. Rebuilding this device from the latest snapshot...',
                          AppLocalizations.of(context),
                        )
                      : state.label,
                  titleKey: state.transport.toLowerCase() == 'lan'
                      ? 'snapshot_progress_lan_rebuild_title'
                      : 'snapshot_progress_cloud_rebuild_title',
                ),
              ),
            ),
          ),
        );
      },
    ).whenComplete(() {
      _autoSnapshotProgressDialogOpen = false;
      _autoSnapshotProgress.value = const _AutoSnapshotProgressState();
    }));
  }

  void _dismissAutoSnapshotProgressDialog() {
    final navigator = _navigatorKey.currentState;
    if (navigator == null || !navigator.canPop()) return;
    navigator.pop();
  }

  @override
  void dispose() {
    unawaited(_autoSyncController.stop());
    _autoCloudSyncController.stop();
    _heavyCacheWarmTimer?.cancel();
    _autoSnapshotProgress.dispose();
    AccountingService.setMutationListener(null);
    _store.dispose();
    super.dispose();
  }

  Future<void> _changeLocale(Locale locale) async {
    await _store.saveLocale(locale);
    if (mounted) setState(() => _locale = locale);
  }

  Future<void> _changeThemeMode(ThemeMode mode) async {
    await _store.saveThemeMode(mode);
    if (mounted) setState(() => _themeMode = mode);
  }

  @override
  Widget build(BuildContext context) {
    if (!_firstFrameMarked) {
      _firstFrameMarked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        StartupTimingService.event(
          'ventio_app_first_frame_painted',
          category: 'ui',
        );
      });
    }
    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) {
        if (_store.activeUser != null && !_syncStarted) {
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _startSyncAfterLogin());
        } else if (_store.activeUser == null && _syncStarted) {
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _stopSyncForLogout());
        }
        return MaterialApp(
          navigatorKey: _navigatorKey,
          debugShowCheckedModeBanner: false,
          title: AppBrand.name,
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
              ? LoginGatePage(
                  store: _store,
                  onLocaleChanged: _changeLocale,
                  child: PageTimingScope(
                    key: const ValueKey('MainShellScope'),
                    pageKey: 'MainShell',
                    pageLabel: 'Main shell',
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
                  ),
                )
              : const Scaffold(
                  body: Center(child: CircularProgressIndicator())),
        );
      },
    );
  }
}

class _CloudProvisioningPage extends StatefulWidget {
  const _CloudProvisioningPage({this.onChanged});

  final VoidCallback? onChanged;

  @override
  State<_CloudProvisioningPage> createState() => _CloudProvisioningPageState();
}

class _CloudProvisioningPageState extends State<_CloudProvisioningPage> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      widget.onChanged?.call();
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  bool _isComplete(Map<String, String> sections, Iterable<String> names) {
    return names.every((name) => sections[name] == 'completed');
  }

  bool _hasAny(Map<String, String> sections, Iterable<String> names) {
    return names.any(sections.containsKey);
  }

  String _stageStatus(Map<String, String> sections, Iterable<String> names,
      AppLocalizations tr) {
    final values = names
        .where(sections.containsKey)
        .map((name) => sections[name] ?? '')
        .toList(growable: false);
    if (values.isEmpty) return tr.text('waiting');
    if (values.every((value) => value == 'completed')) {
      return tr.text('completed');
    }
    if (values.any((value) => value == 'uploading')) {
      return tr.text('downloading');
    }
    if (values.any((value) => value == 'pending')) {
      return tr.text('waiting_for_host');
    }
    return values.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tr = AppLocalizations.of(context);
    final sections = CloudProvisioningStatus.sections;
    final stages = <_ProvisioningStageView>[
      _ProvisioningStageView(
          tr.text('login_settings_and_users'), ['roles', 'users'],
          forceComplete: true),
      _ProvisioningStageView(tr.text('catalogs_and_warehouses'),
          ['categories', 'brands', 'units', 'warehouses']),
      _ProvisioningStageView(tr.text('products_customers_suppliers'),
          ['products', 'customers', 'suppliers', 'supplierProductPrices']),
      _ProvisioningStageView(tr.text('inventory_movements'),
          ['stockMovements', 'billsOfMaterials', 'manufacturingOrders']),
      _ProvisioningStageView(tr.text('sales_and_purchases'),
          ['sales', 'saleQuotations', 'deliveryNotes', 'purchases']),
      _ProvisioningStageView(tr.text('accounting_and_reports'),
          ['expenses', 'accountTransactions']),
    ];
    final completedCount = stages
        .where((stage) =>
            stage.forceComplete || _isComplete(sections, stage.sections))
        .length;
    final progress = stages.isEmpty
        ? null
        : (completedCount / stages.length).clamp(0.05, 1.0).toDouble();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Card(
          margin: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.cloud_sync_outlined,
                    size: 48, color: theme.colorScheme.primary),
                const SizedBox(height: 16),
                Text(tr.text('preparing_store_data'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  localizeRuntimeMessage(CloudProvisioningStatus.message, tr),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                LinearProgressIndicator(
                    value: CloudProvisioningStatus.allSectionsComplete
                        ? 1
                        : progress),
                const SizedBox(height: 20),
                for (final stage in stages)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Builder(
                          builder: (_) {
                            final complete = stage.forceComplete ||
                                _isComplete(sections, stage.sections);
                            final started = _hasAny(sections, stage.sections);
                            final icon = complete
                                ? Icons.check_circle
                                : started
                                    ? Icons.downloading_outlined
                                    : Icons.radio_button_unchecked;
                            final color = complete
                                ? Colors.green
                                : started
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.outline;
                            return Icon(icon, size: 20, color: color);
                          },
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(localizeRuntimeMessage(stage.label, tr)),
                              if (!stage.forceComplete)
                                Text(
                                  _stageStatus(sections, stage.sections, tr),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color:
                                          theme.colorScheme.onSurfaceVariant),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                Text(
                  tr.text('provisioning_wait_message'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProvisioningStageView {
  const _ProvisioningStageView(this.label, this.sections,
      {this.forceComplete = false});

  final String label;
  final List<String> sections;
  final bool forceComplete;
}

class _ShellItem {
  const _ShellItem(
      {required this.label,
      required this.icon,
      required this.selectedIcon,
      required this.page});

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget page;
}

class LocalAutoBackupIndicator extends StatelessWidget {
  const LocalAutoBackupIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<LocalAutoBackupStatus>(
      valueListenable: LocalAutoBackupService.status,
      builder: (context, status, _) {
        if (!status.isRunning &&
            status.message.isEmpty &&
            status.lastError.isEmpty) {
          return const SizedBox.shrink();
        }
        final hasError = status.lastError.isNotEmpty;
        final color =
            hasError ? theme.colorScheme.error : theme.colorScheme.primary;
        final message = hasError ? status.lastError : status.message;
        return Padding(
          padding: const EdgeInsetsDirectional.only(end: 4),
          child: Tooltip(
            message: message.isEmpty ? 'Local backup' : message,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                border: Border.all(color: color.withValues(alpha: 0.38)),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (status.isRunning)
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: color),
                    )
                  else
                    Icon(
                        hasError
                            ? Icons.backup_outlined
                            : Icons.check_circle_outline,
                        size: 14,
                        color: color),
                  const SizedBox(width: 6),
                  Text(
                    status.isRunning
                        ? 'Backup'
                        : hasError
                            ? 'Backup issue'
                            : 'Backed up',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(fontWeight: FontWeight.w700, color: color),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell(
      {super.key,
      required this.onLocaleChanged,
      required this.onThemeModeChanged,
      required this.themeMode,
      required this.store,
      this.onSyncSettingsChanged,
      this.onLogout});

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
  bool _drawerNavigationLocked = false;
  bool _firstBuildMarked = false;
  late final AppUpdateService _updateService = getAppUpdateService();
  late final VoidCallback _updateStatusListener;
  late final VoidCallback _storeListener;
  VoidCallback? _cancelDownloadUpdate;
  AppUpdateInfo? _availableUpdate;
  bool _checkingForUpdate = false;
  bool _downloadingUpdate = false;
  bool _installingUpdate = false;
  double? _downloadProgress;
  String? _downloadedInstallerPath;
  late final AccountAuthCache? _authCache = AccountAuthCache.load();

  void _handleStoreChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _storeListener = _handleStoreChanged;
    widget.store.addListener(_storeListener);
    _updateStatusListener = () {
      if (!mounted) return;
      final state = AppUpdateService.status.value;
      setState(() {
        _availableUpdate = state.latest;
        _checkingForUpdate = state.checking;
        _downloadingUpdate = state.downloading;
        _installingUpdate = state.installing;
        _downloadProgress = state.downloadProgress;
        _downloadedInstallerPath = state.downloadedInstallerPath;
      });
    };
    AppUpdateService.status.addListener(_updateStatusListener);
    _updateStatusListener();
    unawaited(_checkForUpdates());
  }

  @override
  void didUpdateWidget(covariant MainShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_storeListener);
      widget.store.addListener(_storeListener);
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_storeListener);
    AppUpdateService.status.removeListener(_updateStatusListener);
    super.dispose();
  }

  Future<void> _checkForUpdates() async {
    if (!kReleaseMode || !_updateService.isSupported || _checkingForUpdate) {
      return;
    }
    final previousUpdate = _availableUpdate;
    setState(() => _checkingForUpdate = true);
    try {
      final update = await _updateService.checkForUpdate();
      if (!mounted) return;
      setState(() {
        _availableUpdate = update;
        final updateChanged =
            previousUpdate?.displayVersion != update?.displayVersion;
        if (update == null ||
            updateChanged ||
            _downloadedInstallerPath == null ||
            _downloadedInstallerPath!.isEmpty) {
          _downloadedInstallerPath = null;
          _downloadProgress = null;
          _downloadingUpdate = false;
          _installingUpdate = false;
        }
      });
      if (update != null) {
        final restoredPath =
            await _updateService.getDownloadedInstallerPath(update);
        if (!mounted) return;
        setState(() {
          _downloadedInstallerPath = restoredPath;
          if (restoredPath == null) {
            _downloadProgress = null;
            _downloadingUpdate = false;
            _installingUpdate = false;
          }
        });
      } else {
        await _updateService.clearDownloadedUpdate();
      }
    } catch (_) {
      // Update checks must never interrupt store operations.
    } finally {
      if (mounted) setState(() => _checkingForUpdate = false);
    }
  }

  bool get _hasReadyUpdate =>
      _availableUpdate != null && _downloadedInstallerPath != null;

  Future<void> _startDownload(AppUpdateInfo update) async {
    if (_downloadingUpdate || _installingUpdate) return;
    _cancelDownloadUpdate = null;
    setState(() {
      _downloadingUpdate = true;
      _downloadProgress = 0;
    });
    try {
      final installerPath = await _updateService.downloadUpdate(
        update,
        onProgress: (value) {
          if (!mounted) return;
          setState(() => _downloadProgress = value);
        },
        registerCancel: (cancel) {
          _cancelDownloadUpdate = () {
            cancel();
            if (!mounted) return;
            setState(() {
              _downloadingUpdate = false;
              _downloadProgress = null;
              _cancelDownloadUpdate = null;
            });
          };
        },
      );
      if (!mounted) return;
      setState(() {
        _downloadedInstallerPath = installerPath;
        _downloadingUpdate = false;
        _downloadProgress = 1;
        _cancelDownloadUpdate = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(AppLocalizations.of(context).text('update_downloaded'))),
      );
    } catch (error) {
      if (!mounted) return;
      final tr = AppLocalizations.of(context);
      final messenger = ScaffoldMessenger.of(context);
      setState(() {
        _downloadingUpdate = false;
        _downloadProgress = null;
        _cancelDownloadUpdate = null;
      });
      await _updateService.clearDownloadedUpdate();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
            content: Text(tr.format('update_failed', {
          'error': error.toString(),
        }))),
      );
    }
  }

  Future<void> _installReadyUpdate() async {
    await _installDownloadedUpdate();
  }

  Future<void> _installDownloadedUpdate() async {
    final installerPath = _downloadedInstallerPath;
    if (installerPath == null || installerPath.trim().isEmpty) return;
    if (_installingUpdate) return;
    setState(() {
      _installingUpdate = true;
      _downloadProgress = null;
    });
    try {
      await _updateService.launchInstaller(installerPath);
      if (!mounted) return;
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      SystemNavigator.pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _installingUpdate = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(context).format('update_failed', {
          'error': error.toString(),
        }))),
      );
    }
  }

  Future<void> _handleUpdateAction() async {
    final update = _availableUpdate;
    if (update == null) return;
    if (_hasReadyUpdate) {
      await _installReadyUpdate();
    } else {
      await _startDownload(update);
    }
  }

  PreferredSizeWidget? _buildUpdateProgressBar(AppLocalizations tr) {
    if (!_downloadingUpdate && !_installingUpdate) return null;
    final message = _installingUpdate
        ? tr.text('installing_update')
        : _downloadProgress == null
            ? tr.text('downloading')
            : '${tr.text('downloading')} ${(_downloadProgress! * 100).clamp(0, 100).toStringAsFixed(0)}%';
    return PreferredSize(
      preferredSize: const Size.fromHeight(66),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 34,
                height: 34,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: _installingUpdate ? null : _downloadProgress,
                      strokeWidth: 3,
                    ),
                    Icon(
                      Icons.sync_outlined,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.labelLarge,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              TextButton.icon(
                onPressed: _downloadingUpdate ? _cancelDownloadUpdate : null,
                icon: const Icon(Icons.close),
                label: Text(tr.text('cancel')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUpdateAction(BuildContext context, AppLocalizations tr) {
    final colorScheme = Theme.of(context).colorScheme;
    final update = _availableUpdate!;
    final ready = _hasReadyUpdate;
    if (_downloadingUpdate || _installingUpdate) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: TextButton.icon(
          onPressed: null,
          icon: const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          label: Text(_installingUpdate
              ? tr.text('installing_update')
              : tr.text('downloading')),
        ),
      );
    }
    if (ready) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.green.shade600,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          onPressed: _handleUpdateAction,
          icon: const Icon(Icons.check_circle_outline),
          label: Text(tr.text('update_now')),
        ),
      );
    }
    final background = update.required
        ? colorScheme.errorContainer
        : colorScheme.primaryContainer;
    final foreground = update.required
        ? colorScheme.onErrorContainer
        : colorScheme.onPrimaryContainer;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: background,
        shape: const CircleBorder(),
        child: IconButton(
          tooltip: tr.format('update_available_tooltip', {
            'version': update.displayVersion,
          }),
          onPressed: _handleUpdateAction,
          icon: Badge(
            label: const Text('1'),
            child: Icon(
              update.required
                  ? Icons.priority_high_outlined
                  : Icons.system_update_alt_outlined,
              color: foreground,
            ),
          ),
        ),
      ),
    );
  }

  // ignore: unused_element
  Future<void> _showUpdateDialog(AppUpdateInfo update) async {
    final tr = AppLocalizations.of(context);
    var installing = false;
    double? progress;
    await showDialog<void>(
      context: context,
      barrierDismissible: !update.required,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(tr.text('update_available')),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr.format('update_available_desc', {
                  'version': update.displayVersion,
                })),
                if (update.notes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ...update.notes.take(5).map(
                        (note) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('• '),
                              Expanded(child: Text(note)),
                            ],
                          ),
                        ),
                      ),
                ],
                if (installing) ...[
                  const SizedBox(height: 16),
                  LinearProgressIndicator(value: progress),
                  const SizedBox(height: 8),
                  Text(progress == null
                      ? tr.text('downloading')
                      : '${tr.text('downloading')} ${(progress! * 100).clamp(0, 100).toStringAsFixed(0)}%'),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: installing || update.required
                  ? null
                  : () => Navigator.of(dialogContext).pop(),
              child: Text(tr.text('later')),
            ),
            FilledButton.icon(
              onPressed: installing
                  ? null
                  : () async {
                      setDialogState(() {
                        installing = true;
                        progress = null;
                      });
                      try {
                        await _updateService.downloadAndInstall(
                          update,
                          onProgress: (value) =>
                              setDialogState(() => progress = value),
                        );
                        if (!dialogContext.mounted) return;
                        Navigator.of(dialogContext).pop();
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content:
                                  Text(tr.text('update_installer_started'))),
                        );
                      } catch (error) {
                        setDialogState(() {
                          installing = false;
                          progress = null;
                        });
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(tr.format('update_failed', {
                            'error': error.toString(),
                          }))),
                        );
                      }
                    },
              icon: const Icon(Icons.system_update_alt_outlined),
              label: Text(tr.text('update_now')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectDrawerItem(BuildContext drawerContext, int index) async {
    if (_drawerNavigationLocked) return;
    _drawerNavigationLocked = true;
    try {
      if (mounted && selectedIndex != index) {
        setState(() => selectedIndex = index);
      }
      final navigator = Navigator.of(drawerContext);
      if (navigator.canPop()) {
        navigator.pop();
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    } finally {
      _drawerNavigationLocked = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_firstBuildMarked) {
      _firstBuildMarked = true;
      StartupTimingService.event('main_shell_first_build', category: 'ui');
    }
    final tr = AppLocalizations.of(context);
    Widget timedPage(String pageKey, String pageLabel, Widget page) {
      return PageTimingScope(
        key: ValueKey<String>(pageKey),
        pageKey: pageKey,
        pageLabel: pageLabel,
        child: page,
      );
    }

    final storeName = widget.store.storeProfile.name.trim();
    final shellTitle = storeName.isEmpty ||
            storeName == 'My Store' ||
            storeName == tr.text('my_store')
        ? 'Ventio'
        : storeName;
    final authCache = _authCache;
    final isPlatformAdmin = authCache?.accountType == 'platform_admin';
    final items = [
      if (isPlatformAdmin)
        _ShellItem(
            label: 'Subscribers',
            icon: Icons.admin_panel_settings_outlined,
            selectedIcon: Icons.admin_panel_settings,
            page: timedPage('AdminSubscribersPage', 'Admin subscribers',
                const AdminSubscribersPage())),
      if (widget.store.canAccessPage('dashboard'))
        _ShellItem(
            label: tr.text('dashboard'),
            icon: Icons.dashboard_outlined,
            selectedIcon: Icons.dashboard,
            page: PageTimingScope(
              key: const ValueKey('DashboardPage'),
              pageKey: 'DashboardPage',
              pageLabel: tr.text('dashboard'),
              autoReady: false,
              child: DashboardPage(store: widget.store),
            )),
      if (widget.store.canAccessPage('products'))
        _ShellItem(
            label: tr.text('products'),
            icon: Icons.inventory_2_outlined,
            selectedIcon: Icons.inventory_2,
            page: timedPage('ProductsPage', tr.text('products'),
                ProductsPage(store: widget.store))),
      if (widget.store.canAccessPage('customers'))
        _ShellItem(
            label: tr.text('customers'),
            icon: Icons.people_outline,
            selectedIcon: Icons.people,
            page: timedPage('CustomersPage', tr.text('customers'),
                CustomersPage(store: widget.store))),
      if (widget.store.canAccessPage('suppliers'))
        _ShellItem(
            label: tr.text('suppliers'),
            icon: Icons.local_shipping_outlined,
            selectedIcon: Icons.local_shipping,
            page: timedPage('SuppliersPage', tr.text('suppliers'),
                SuppliersPage(store: widget.store))),
      if (widget.store.canAccessPage('sales'))
        _ShellItem(
            label: tr.text('sales'),
            icon: Icons.receipt_long_outlined,
            selectedIcon: Icons.receipt_long,
            page: timedPage(
                'SalesPage', tr.text('sales'), SalesPage(store: widget.store))),
      if (widget.store.canAccessPage('quotations'))
        _ShellItem(
            label: tr.text('quotations'),
            icon: Icons.request_quote_outlined,
            selectedIcon: Icons.request_quote,
            page: timedPage('QuotationsPage', tr.text('quotations'),
                QuotationsPage(store: widget.store))),
      if (widget.store.canAccessPage('delivery_notes'))
        _ShellItem(
            label: tr.text('delivery_notes'),
            icon: Icons.local_shipping_outlined,
            selectedIcon: Icons.local_shipping,
            page: timedPage('DeliveryNotesPage', tr.text('delivery_notes'),
                DeliveryNotesPage(store: widget.store))),
      if (widget.store.canAccessPage('purchases'))
        _ShellItem(
            label: tr.text('purchases'),
            icon: Icons.add_shopping_cart_outlined,
            selectedIcon: Icons.add_shopping_cart,
            page: timedPage('PurchasesPage', tr.text('purchases'),
                PurchasesPage(store: widget.store))),
      if (widget.store.canAccessPage('expenses'))
        _ShellItem(
            label: tr.text('expenses'),
            icon: Icons.payments_outlined,
            selectedIcon: Icons.payments,
            page: timedPage('ExpensesPage', tr.text('expenses'),
                ExpensesPage(store: widget.store))),
      if (widget.store.canAccessPage('accounting'))
        _ShellItem(
            label: tr.text('accounting'),
            icon: Icons.account_balance_wallet_outlined,
            selectedIcon: Icons.account_balance_wallet,
            page: timedPage('AccountingPage', tr.text('accounting'),
                AccountingPage(store: widget.store))),
      if (widget.store.canAccessPage('inventory'))
        _ShellItem(
            label: tr.text('inventory'),
            icon: Icons.warehouse_outlined,
            selectedIcon: Icons.warehouse,
            page: timedPage('InventoryPage', tr.text('inventory'),
                InventoryPage(store: widget.store))),
      if (widget.store.canAccessPage('manufacturing'))
        _ShellItem(
            label: tr.text('manufacturing_page'),
            icon: Icons.precision_manufacturing_outlined,
            selectedIcon: Icons.precision_manufacturing,
            page: timedPage('ManufacturingPage', tr.text('manufacturing_page'),
                ManufacturingPage(store: widget.store))),
      if (widget.store.canAccessPage('reports'))
        _ShellItem(
            label: tr.text('reports'),
            icon: Icons.bar_chart_outlined,
            selectedIcon: Icons.bar_chart,
            page: timedPage('ReportsPage', tr.text('reports'),
                ReportsPage(store: widget.store))),
      if (widget.store.canAccessPage('maintenance'))
        _ShellItem(
            label: tr.text('maintenance'),
            icon: Icons.health_and_safety_outlined,
            selectedIcon: Icons.health_and_safety,
            page: timedPage('MaintenancePage', tr.text('maintenance'),
                MaintenancePage(store: widget.store))),
      if (widget.store.canAccessPage('database'))
        _ShellItem(
            label: tr.text('database'),
            icon: Icons.storage_outlined,
            selectedIcon: Icons.storage,
            page: timedPage('DatabasePage', tr.text('database'),
                DatabasePage(store: widget.store))),
      if (widget.store.canAccessPage('settings'))
        _ShellItem(
            label: tr.text('settings'),
            icon: Icons.settings_outlined,
            selectedIcon: Icons.settings,
            page: timedPage(
                'SettingsPage',
                tr.text('settings'),
                SettingsPage(
                    store: widget.store,
                    onLocaleChanged: widget.onLocaleChanged,
                    onThemeModeChanged: widget.onThemeModeChanged,
                    themeMode: widget.themeMode,
                    onSyncSettingsChanged: widget.onSyncSettingsChanged))),
    ];
    if (items.isEmpty) {
      items.add(_ShellItem(
        label: 'Access denied',
        icon: Icons.lock_outline,
        selectedIcon: Icons.lock,
        page: timedPage('_NoAccessPage', 'No access', const _NoAccessPage()),
      ));
    }
    final resolvedItems = items;
    if (selectedIndex >= resolvedItems.length) {
      selectedIndex = resolvedItems.length - 1;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return Scaffold(
          appBar: AppBar(
            leading: Builder(
              builder: (context) => IconButton(
                tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
                icon: const Icon(Icons.menu),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            ),
            title: Text('$shellTitle • ${resolvedItems[selectedIndex].label}',
                overflow: TextOverflow.ellipsis),
            bottom: _buildUpdateProgressBar(tr),
            actions: [
              if (_availableUpdate != null) _buildUpdateAction(context, tr),
              LocalAutoBackupIndicator(),
              HostConnectionIndicator(store: widget.store),
              PopupMenuButton<String>(
                tooltip: widget.store.activeUser?.fullName ?? tr.text('logout'),
                onSelected: (value) async {
                  if (value == 'language_en') {
                    widget.onLocaleChanged(const Locale('en'));
                  } else if (value == 'language_ar') {
                    widget.onLocaleChanged(const Locale('ar'));
                  } else if (value == 'logout') {
                    await widget.onLogout?.call();
                    await AccountAuthCache.clear();
                    await AuthRepository.logout(widget.store);
                  }
                },
                itemBuilder: (context) {
                  final currentLocale = Localizations.localeOf(context);
                  final isArabic = currentLocale.languageCode == 'ar';
                  return [
                    if ((widget.store.activeUser?.fullName ?? '')
                        .trim()
                        .isNotEmpty)
                      PopupMenuItem<String>(
                        enabled: false,
                        child: Text(widget.store.activeUser!.fullName,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    PopupMenuItem<String>(
                      value: 'language_en',
                      child: Row(children: [
                        const Text('🇺🇸'),
                        const SizedBox(width: 10),
                        Expanded(child: Text(tr.text('language_english'))),
                        if (!isArabic) const Icon(Icons.check, size: 18),
                      ]),
                    ),
                    PopupMenuItem<String>(
                      value: 'language_ar',
                      child: Row(children: [
                        const Text('🇱🇧'),
                        const SizedBox(width: 10),
                        Expanded(child: Text(tr.text('language_arabic'))),
                        if (isArabic) const Icon(Icons.check, size: 18),
                      ]),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem<String>(
                      value: 'logout',
                      child: Row(children: [
                        const Icon(Icons.logout),
                        const SizedBox(width: 10),
                        Text(tr.text('logout')),
                      ]),
                    ),
                  ];
                },
                icon: const Icon(Icons.more_vert),
              ),
            ],
          ),
          drawer: Drawer(
            child: SafeArea(
              child: ListView.builder(
                itemCount: resolvedItems.length,
                itemBuilder: (context, index) {
                  final item = resolvedItems[index];
                  return ListTile(
                    leading: Icon(
                        index == selectedIndex ? item.selectedIcon : item.icon),
                    title: Text(item.label),
                    selected: index == selectedIndex,
                    enabled: !_drawerNavigationLocked,
                    onTap: () => _selectDrawerItem(context, index),
                  );
                },
              ),
            ),
          ),
          body: CloudProvisioningStatus.isPending &&
                  widget.store.appIdentity.isClient &&
                  widget.store.appIdentity.activeSyncTransportNormalized ==
                      'cloud'
              ? _CloudProvisioningPage(onChanged: () => setState(() {}))
              : resolvedItems[selectedIndex].page,
        );
      },
    );
  }
}

class _NoAccessPage extends StatelessWidget {
  const _NoAccessPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 42),
                  const SizedBox(height: 12),
                  Text(
                    'No accessible pages',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'This account does not have permissions to open any section.',
                    textAlign: TextAlign.center,
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

enum _TransportState {
  checking,
  active,
  online,
  pending,
  provisioning,
  suspended,
  offline,
  error,
  disabled,
  notConfigured
}

class _TransportSnapshot {
  const _TransportSnapshot({
    required this.label,
    required this.state,
    required this.message,
    this.lastSeenAt,
    this.lastSuccessfulSyncAt,
  });

  final String label;
  final _TransportState state;
  final String message;
  final DateTime? lastSeenAt;
  final DateTime? lastSuccessfulSyncAt;
}

class _ConnectionStatusSnapshot {
  const _ConnectionStatusSnapshot({
    required this.roleLabel,
    required this.roleMessage,
    required this.lan,
    required this.cloud,
    required this.syncHealth,
    required this.activeTransportLabel,
    required this.pendingChanges,
  });

  final String roleLabel;
  final String roleMessage;
  final _TransportSnapshot lan;
  final _TransportSnapshot cloud;
  final _TransportSnapshot syncHealth;
  final String activeTransportLabel;
  final int pendingChanges;
}

class HostConnectionIndicator extends StatefulWidget {
  const HostConnectionIndicator(
      {super.key, required this.store, this.compact = false});

  final AppStore store;
  final bool compact;

  @override
  State<HostConnectionIndicator> createState() =>
      _HostConnectionIndicatorState();
}

class _HostConnectionIndicatorState extends State<HostConnectionIndicator> {
  Timer? _timer;
  bool _didStartRefreshLoop = false;
  _ConnectionStatusSnapshot _snapshot = const _ConnectionStatusSnapshot(
    roleLabel: '',
    roleMessage: '...',
    lan: _TransportSnapshot(
        label: 'LAN', state: _TransportState.checking, message: '...'),
    cloud: _TransportSnapshot(
        label: '', state: _TransportState.checking, message: '...'),
    syncHealth: _TransportSnapshot(
        label: '', state: _TransportState.checking, message: '...'),
    activeTransportLabel: '',
    pendingChanges: 0,
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
  String _rt(String message) =>
      localizeRuntimeMessage(message, AppLocalizations.of(context));

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

  String _activeTransportLabel() {
    final identity = widget.store.appIdentity;
    if (identity.isHost) {
      final lan =
          UnifiedSyncFactory.isLanSetupComplete ? _t('connection_lan') : '';
      final cloud = UnifiedSyncFactory.cloudCanCheck(widget.store)
          ? _t('connection_cloud')
          : '';
      final parts = [lan, cloud]
          .where((part) => part.trim().isNotEmpty)
          .toList(growable: false);
      if (parts.isEmpty) return _t('local');
      return parts.join(' + ');
    }
    final active = identity.activeSyncTransportNormalized;
    if (active == 'lan') return _t('connection_lan');
    if (active == 'cloud') return _t('connection_cloud');
    return _t('local');
  }

  bool _isActiveTransport(_TransportSnapshot snapshot) {
    final identity = widget.store.appIdentity;
    if (identity.isHost) {
      if (snapshot.label == _t('connection_lan')) {
        return UnifiedSyncFactory.isLanSetupComplete;
      }
      if (snapshot.label == _t('connection_cloud')) {
        return UnifiedSyncFactory.cloudCanCheck(widget.store);
      }
      return true;
    }
    final active = identity.activeSyncTransportNormalized;
    if (snapshot.label == _t('connection_lan')) return active == 'lan';
    if (snapshot.label == _t('connection_cloud')) return active == 'cloud';
    return true;
  }

  Future<_TransportSnapshot> _readLanStatus() async {
    if (kIsWeb) {
      return _TransportSnapshot(
        label: _t('connection_lan'),
        state: _TransportState.disabled,
        message: _t('connection_lan_web_disabled'),
      );
    }

    final identity = widget.store.appIdentity;
    final settings = LanSyncSettings.load();
    final hasSavedLanSettings =
        settings.host.trim().isNotEmpty || settings.secret.trim().isNotEmpty;
    final lanEnabledForRole = identity.isHost
        ? settings.setupComplete && settings.isHost
        : identity.isClient &&
            identity.activeSyncTransportNormalized == 'lan' &&
            settings.setupComplete &&
            settings.isClient;

    if (!lanEnabledForRole) {
      return _TransportSnapshot(
        label: _t('connection_lan'),
        state: hasSavedLanSettings
            ? _TransportState.disabled
            : _TransportState.notConfigured,
        message: hasSavedLanSettings
            ? _t('connection_state_disabled')
            : _t('connection_lan_not_configured'),
      );
    }

    // A device can be the store Host, but LAN is only Active when the LAN
    // settings explicitly say the LAN host service is enabled/configured.
    if (identity.isHost && settings.isHost) {
      return _TransportSnapshot(
        label: _t('connection_lan'),
        state: _TransportState.active,
        message: _t('connection_lan_host_active'),
      );
    }

    try {
      final status =
          await UnifiedSyncFactory.lanEngine(widget.store, settings: settings)
              .getHostStatus();
      if (status.hostReachable) {
        return _TransportSnapshot(
          label: _t('connection_lan'),
          state: _TransportState.online,
          message: status.message.isEmpty
              ? _t('connection_lan_host_reachable')
              : _rt(status.message),
          lastSeenAt: status.lastSeenAt ?? DateTime.now(),
        );
      }
      return _TransportSnapshot(
        label: _t('connection_lan'),
        state: _TransportState.offline,
        message: status.message.isEmpty
            ? _t('connection_lan_host_offline')
            : _rt(status.message),
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
    final identity = widget.store.appIdentity;
    final settings = CloudSyncSettings.load();
    final provisioning = identity.isClient &&
        identity.activeSyncTransportNormalized == 'cloud' &&
        CloudProvisioningStatus.isPending;
    final hasSavedCloudSettings = settings.isConfigured;
    final cloudEnabledForRole = identity.isHost
        ? identity.isCloudEnabled && hasSavedCloudSettings
        : identity.isClient &&
            identity.activeSyncTransportNormalized == 'cloud' &&
            hasSavedCloudSettings;

    if (!cloudEnabledForRole) {
      return _TransportSnapshot(
        label: _t('connection_cloud'),
        state: hasSavedCloudSettings
            ? _TransportState.disabled
            : _TransportState.notConfigured,
        message: hasSavedCloudSettings
            ? _t('connection_state_disabled')
            : _t('connection_cloud_not_configured'),
      );
    }

    try {
      final status =
          await UnifiedSyncFactory.cloudEngine(widget.store, settings: settings)
              .getHostStatus();

      if (provisioning) {
        return _TransportSnapshot(
          label: _t('connection_cloud'),
          state: _TransportState.provisioning,
          message:
              '${_rt(CloudProvisioningStatus.message)} ${_rt(status.message)}'
                  .trim(),
          lastSeenAt: status.lastSeenAt,
        );
      }

      if (!status.cloudReachable) {
        return _TransportSnapshot(
          label: _t('connection_cloud'),
          state: _TransportState.offline,
          message: status.message.isEmpty
              ? _t('connection_cloud_unreachable')
              : _rt(status.message),
          lastSeenAt: status.lastSeenAt,
        );
      }

      if (widget.store.appIdentity.isHost) {
        return _TransportSnapshot(
          label: _t('connection_cloud'),
          state: status.hostReachable
              ? _TransportState.online
              : _TransportState.pending,
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
          message: status.message.isEmpty
              ? _t('connection_cloud_host_reachable')
              : status.message,
          lastSeenAt: status.lastSeenAt ?? DateTime.now(),
        );
      }

      return _TransportSnapshot(
        label: _t('connection_cloud'),
        state: _TransportState.offline,
        message: status.lastSeenAt == null
            ? _t('connection_no_host_heartbeat')
            : _t('connection_host_heartbeat_stale'),
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
    final identity = widget.store.appIdentity;
    final pending = widget.store.isSyncDataLoaded
        ? (identity.isClient
            ? widget.store.activeClientPendingSyncCount
            : widget.store.pendingSyncCount)
        : 0;
    final lastSuccessfulSync =
        SyncDeviceStateStore.lastSuccessfulSyncAt(identity);

    if (identity.isClient &&
        identity.activeSyncTransportNormalized == 'cloud' &&
        CloudProvisioningStatus.isPending) {
      return _TransportSnapshot(
        label: _t('connection_sync_health'),
        state: _TransportState.provisioning,
        message: _t('connection_sync_provisioning'),
        lastSuccessfulSyncAt: lastSuccessfulSync,
      );
    }

    if (identity.isClient && widget.store.isSuspendedByHost) {
      return _TransportSnapshot(
        label: _t('connection_sync_health'),
        state: _TransportState.suspended,
        message: widget.store.suspendedByHostReason.trim().isEmpty
            ? _t('client_suspended_by_host_desc')
            : _rt(widget.store.suspendedByHostReason),
        lastSuccessfulSyncAt: lastSuccessfulSync,
      );
    }

    final lanSettings = LanSyncSettings.load();
    final cloudSettings = CloudSyncSettings.load();
    final hasSavedCloudSettings = cloudSettings.isConfigured;
    final lanEnabled = identity.isHost
        ? lanSettings.setupComplete && lanSettings.isHost
        : identity.isClient &&
            identity.activeSyncTransportNormalized == 'lan' &&
            lanSettings.setupComplete &&
            lanSettings.isClient;
    final cloudEnabled = identity.isHost
        ? identity.isCloudEnabled && hasSavedCloudSettings
        : identity.isClient &&
            identity.activeSyncTransportNormalized == 'cloud' &&
            hasSavedCloudSettings;

    if (!lanEnabled && !cloudEnabled) {
      return _TransportSnapshot(
        label: _t('connection_sync_health'),
        state: _TransportState.disabled,
        message: _t('connection_state_disabled'),
        lastSuccessfulSyncAt: lastSuccessfulSync,
      );
    }

    if (pending > 0) {
      return _TransportSnapshot(
        label: _t('connection_sync_health'),
        state: _TransportState.pending,
        message: identity.isClient
            ? '${_t('sync_pending')} • $pending ${_t('connection_sync_pending_suffix')}'
            : '${_t('connection_sync_pending_prefix')} $pending ${_t('connection_sync_pending_suffix')}',
        lastSuccessfulSyncAt: lastSuccessfulSync,
      );
    }

    if (lastSuccessfulSync == null) {
      return _TransportSnapshot(
        label: _t('connection_sync_health'),
        state: _TransportState.notConfigured,
        message: _t('not_synced_yet'),
      );
    }

    return _TransportSnapshot(
      label: _t('connection_sync_health'),
      state: _TransportState.active,
      message: _t('synced'),
      lastSuccessfulSyncAt: lastSuccessfulSync,
    );
  }

  Future<void> _refresh() async {
    final checking = _ConnectionStatusSnapshot(
      roleLabel: _roleLabel(),
      roleMessage: _roleMessage(),
      lan: _TransportSnapshot(
          label: _t('connection_lan'),
          state: _TransportState.checking,
          message: _t('connection_lan_checking')),
      cloud: _TransportSnapshot(
          label: _t('connection_cloud'),
          state: _TransportState.checking,
          message: _t('connection_cloud_checking')),
      syncHealth: _TransportSnapshot(
          label: _t('connection_sync_health'),
          state: _TransportState.checking,
          message: _t('connection_sync_checking')),
      activeTransportLabel: _activeTransportLabel(),
      pendingChanges: widget.store.isSyncDataLoaded
          ? (widget.store.appIdentity.isClient
              ? widget.store.activeClientPendingSyncCount
              : widget.store.pendingSyncCount)
          : 0,
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
        activeTransportLabel: _activeTransportLabel(),
        pendingChanges: widget.store.isSyncDataLoaded
            ? (widget.store.appIdentity.isClient
                ? widget.store.activeClientPendingSyncCount
                : widget.store.pendingSyncCount)
            : 0,
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
      _TransportState.suspended => Colors.orange,
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
      _TransportState.online => _t('connection_state_active'),
      _TransportState.pending => _t('connection_state_pending'),
      _TransportState.provisioning => _t('connection_state_provisioning'),
      _TransportState.suspended => _t('suspended'),
      _TransportState.offline => _t('connection_state_pending'),
      _TransportState.error => _t('connection_state_error'),
      _TransportState.checking => _t('connection_state_checking'),
      _TransportState.disabled => _t('connection_state_disabled'),
      _TransportState.notConfigured => _t('connection_state_not_configured'),
    };
  }

  String _timeText(DateTime? value) {
    if (value == null) return _t('never');
    final local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  String _lastSeenText(DateTime? value) {
    if (value == null) return '';
    final local = value.toLocal();
    return ' • ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  bool _needsAttention(_TransportSnapshot snapshot) {
    return switch (snapshot.state) {
      _TransportState.offline ||
      _TransportState.error ||
      _TransportState.pending ||
      _TransportState.provisioning ||
      _TransportState.suspended ||
      _TransportState.checking =>
        true,
      _ => false,
    };
  }

  _TransportSnapshot get _activeConnectionSnapshot {
    final identity = widget.store.appIdentity;
    if (identity.isHost) {
      final candidates = <_TransportSnapshot>[];
      if (UnifiedSyncFactory.isLanSetupComplete) candidates.add(_snapshot.lan);
      if (UnifiedSyncFactory.cloudCanCheck(widget.store)) {
        candidates.add(_snapshot.cloud);
      }
      if (candidates.isEmpty) return _snapshot.lan;
      if (candidates.any((item) => item.state == _TransportState.checking)) {
        return candidates
            .firstWhere((item) => item.state == _TransportState.checking);
      }
      if (candidates.any((item) =>
          item.state == _TransportState.online ||
          item.state == _TransportState.active)) {
        return candidates.firstWhere((item) =>
            item.state == _TransportState.online ||
            item.state == _TransportState.active);
      }
      return candidates.first;
    }
    final active = identity.activeSyncTransportNormalized;
    if (active == 'lan') return _snapshot.lan;
    if (active == 'cloud') return _snapshot.cloud;
    return _TransportSnapshot(
        label: _t('local'),
        state: _TransportState.disabled,
        message: _t('connection_role_local_desc'));
  }

  bool get _hasAttention {
    final activeConnection = _activeConnectionSnapshot;
    return _needsAttention(activeConnection) ||
        _needsAttention(_snapshot.syncHealth);
  }

  _TransportState get _summaryState {
    final activeConnection = _activeConnectionSnapshot;
    if (activeConnection.state == _TransportState.checking ||
        _snapshot.syncHealth.state == _TransportState.checking) {
      return _TransportState.checking;
    }
    if (_hasAttention) return _TransportState.error;
    return _TransportState.active;
  }

  String get _connectionSummaryLabel {
    final connection = _activeConnectionSnapshot;
    if (connection.state == _TransportState.online ||
        connection.state == _TransportState.active) {
      return _t('connection_state_active');
    }
    if (connection.state == _TransportState.disabled) {
      return _t('connection_state_disabled');
    }
    if (connection.state == _TransportState.notConfigured) {
      return _t('connection_state_not_configured');
    }
    return _stateText(connection.state);
  }

  String get _syncSummaryLabel {
    final sync = _snapshot.syncHealth;
    if (sync.state == _TransportState.active) return _t('synced');
    if (sync.state == _TransportState.suspended) return _t('suspended');
    if (sync.state == _TransportState.pending) {
      return widget.store.appIdentity.isClient
          ? _t('sync_pending')
          : _t('connection_state_pending');
    }
    if (sync.state == _TransportState.notConfigured) {
      return _t('not_synced_yet');
    }
    return _stateText(sync.state);
  }

  String get _summaryLabel {
    if (_summaryState == _TransportState.checking) {
      return _t('connection_state_checking');
    }
    return '$_connectionSummaryLabel • $_syncSummaryLabel';
  }

  PopupMenuItem<void> _detailItem(BuildContext context, IconData icon,
      String title, _TransportSnapshot snapshot,
      {bool activeTransport = true}) {
    final theme = Theme.of(context);
    final color =
        activeTransport ? _stateColor(context, snapshot.state) : Colors.grey;
    final titleSuffix =
        activeTransport ? '' : ' (${_t('connection_state_disabled')})';
    return PopupMenuItem<void>(
      enabled: false,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$title$titleSuffix: ${_stateText(snapshot.state)}',
                    style: theme.textTheme.labelLarge),
                if (snapshot.message.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '${snapshot.message}${_lastSeenText(snapshot.lastSeenAt)}',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<void> _infoItem(
      BuildContext context, IconData icon, String title, String value) {
    final theme = Theme.of(context);
    return PopupMenuItem<void>(
      enabled: false,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, color: theme.colorScheme.primary, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: theme.textTheme.labelLarge),
                const SizedBox(height: 2),
                Text(value,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lan = _snapshot.lan;
    final cloud = _snapshot.cloud;
    final syncHealth = _snapshot.syncHealth;
    final summaryColor = _stateColor(context, _summaryState);
    final tooltip = [
      _summaryLabel,
      _snapshot.roleLabel,
      '${_t('active_transport')}: ${_snapshot.activeTransportLabel}',
      '${_t('connection_status')}: $_connectionSummaryLabel',
      '${_t('sync_status')}: $_syncSummaryLabel',
      '${_t('pending_changes')}: ${_snapshot.pendingChanges}',
      '${_t('last_successful_sync')}: ${_timeText(syncHealth.lastSuccessfulSyncAt)}',
      "${_t('connection_lan')}: ${_stateText(lan.state)}${_lastSeenText(lan.lastSeenAt)} — ${lan.message}",
      "${_t('connection_cloud')}: ${_stateText(cloud.state)}${_lastSeenText(cloud.lastSeenAt)} — ${cloud.message}",
    ].join('\n');

    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 4),
      child: Tooltip(
        message: tooltip,
        child: PopupMenuButton<void>(
          tooltip: tooltip,
          constraints: BoxConstraints(
              minWidth: 280,
              maxWidth: VentioResponsive.modalMaxWidth(context, 390)),
          onOpened: _refresh,
          itemBuilder: (context) => [
            PopupMenuItem<void>(
              enabled: false,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.circle, color: summaryColor, size: 12),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_summaryLabel,
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        Text(_snapshot.roleLabel,
                            style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const PopupMenuDivider(),
            _infoItem(context, Icons.swap_horiz_outlined,
                _t('active_transport'), _snapshot.activeTransportLabel),
            _infoItem(context, Icons.device_hub_outlined,
                _t('connection_status'), _connectionSummaryLabel),
            _infoItem(context, Icons.sync_outlined, _t('sync_status'),
                _syncSummaryLabel),
            _infoItem(context, Icons.pending_actions_outlined,
                _t('pending_changes'), _snapshot.pendingChanges.toString()),
            _infoItem(
                context,
                Icons.verified_outlined,
                _t('last_successful_sync'),
                _timeText(syncHealth.lastSuccessfulSyncAt)),
            const PopupMenuDivider(),
            _detailItem(context, Icons.lan_outlined, _t('connection_lan'), lan,
                activeTransport: _isActiveTransport(lan)),
            _detailItem(
                context, Icons.cloud_outlined, _t('connection_cloud'), cloud,
                activeTransport: _isActiveTransport(cloud)),
            PopupMenuItem<void>(
              enabled: false,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text(_snapshot.roleMessage,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall),
            ),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: summaryColor.withValues(alpha: 0.12),
              border: Border.all(color: summaryColor.withValues(alpha: 0.38)),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, color: summaryColor, size: 9),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: Text(
                    _summaryLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
