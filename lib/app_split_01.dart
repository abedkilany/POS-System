part of 'app.dart';

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
  late final UnifiedAutoDirectSyncController _autoDirectSyncController =
      UnifiedAutoDirectSyncController(_store);
  bool _syncStarted = false;
  bool _autoSnapshotProgressDialogOpen = false;
  bool _firstFrameMarked = false;
  String _startupError = '';
  Future<bool> Function()? _activeExitGuard;
  static const MethodChannel _windowLifecycleChannel =
      MethodChannel('ventio/window_lifecycle');
  static const Duration _gracefulShutdownTimeout = Duration(seconds: 30);
  bool _shutdownInProgress = false;

  @override
  void initState() {
    super.initState();
    _windowLifecycleChannel.setMethodCallHandler(_handleWindowLifecycleCall);
    _registerPageTimings();
    AccountingService.setMutationListener(() {
      _store.notifyListeners();
      unawaited(_store.recordPhase8AccountingMutationForSync());
    });
    _initializeApp();
  }

  void _registerPageTimings() {
    const registeredPages = <({String key, String label})>[
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
    for (final page in registeredPages) {
      StartupTimingService.registerPage(
        pageKey: page.key,
        pageLabel: page.label,
      );
    }
  }

  Future<void> _initializeApp() async {
    try {
      await StartupTimingService.measure(
        'ventio_app.initialize',
        () async {
          await _store.initialize(hydrateHeavyData: false);
          final savedTheme = await _store.loadThemeMode();
          final savedLocale = await _store.loadLocale();
          if (mounted) {
            setState(() {
              _startupError = '';
              _themeMode = savedTheme;
              _locale = savedLocale;
            });
          }
          if (_store.activeUser != null) {
            unawaited(_startSyncAfterLogin());
          }
        },
        category: 'ui',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _startupError = error.toString();
      });
    }
  }

  Future<void> _startSyncAfterLogin() async {
    if (_syncStarted || _store.activeUser == null) return;
    _syncStarted = true;
    await StartupTimingService.measure(
      'ventio_app.start_sync_after_login',
      () async {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        if (!mounted || _store.activeUser == null) return;
        await _store.recoverPhase8AccountingSyncAfterStartup();
        if (!mounted || _store.activeUser == null) return;
        unawaited(_autoSyncController.start());
        unawaited(_autoDirectSyncController.start());
        unawaited(_startBackupsAfterLogin());
      },
      category: 'app_store',
    );
  }

  Future<void> _startBackupsAfterLogin() async {
    await Future<void>.delayed(const Duration(seconds: 15));
    if (!mounted || _store.activeUser == null) return;
    try {
      await StartupTimingService.measure(
        'ventio_app.run_local_backup_after_login',
        () => LocalAutoBackupService.runDueBackup(_store),
        category: 'app_store',
      );
    } catch (_) {
      // The backup service records its own error status. Keep Google Drive
      // backup independent if the local backup fails.
    }
    if (!mounted || _store.activeUser == null) return;
    try {
      await StartupTimingService.measure(
        'ventio_app.run_google_backup_after_login',
        () => GoogleDriveBackupService.runDueBackup(_store),
        category: 'app_store',
      );
    } catch (_) {
      // The backup service records its own error status.
    }
  }

  Future<void> _stopSyncForLogout() async {
    _syncStarted = false;
    await _autoSyncController.stop();
    _autoDirectSyncController.stop();
    await UnifiedSyncFactory.disposeDirect(_store);
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
                      : 'preparing_store_data',
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

  Future<void> _handleWindowLifecycleCall(MethodCall call) async {
    if (call.method == 'requestClose') {
      final guard = _activeExitGuard;
      if (guard != null && !await guard()) {
        try {
          await _windowLifecycleChannel.invokeMethod<void>('cancelClose');
        } on MissingPluginException {
          // Non-Windows platforms don't install the native close interceptor.
        }
        return;
      }
      await _gracefulShutdownAndCloseWindow();
    }
  }

  void _setActiveExitGuard(Future<bool> Function()? guard) {
    _activeExitGuard = guard;
  }

  Future<void> _gracefulShutdownAndCloseWindow() async {
    if (_shutdownInProgress) return;
    _shutdownInProgress = true;
    try {
      await _drainAndCloseStorage().timeout(_gracefulShutdownTimeout);
    } on TimeoutException catch (error, stackTrace) {
      // A stalled sync/socket/database shutdown must not leave the native
      // window permanently alive. Committed SQLite WAL data remains
      // recoverable if the process exits before the final checkpoint.
      debugPrint(
        'Graceful shutdown exceeded $_gracefulShutdownTimeout; '
        'allowing the window to close: $error\n$stackTrace',
      );
    } catch (error, stackTrace) {
      debugPrint('Graceful shutdown failed: $error\n$stackTrace');
      // Never delete WAL on failure. SQLite keeps committed WAL data durable
      // and will recover it on the next launch.
    } finally {
      try {
        await _windowLifecycleChannel
            .invokeMethod<void>('allowClose')
            .timeout(const Duration(seconds: 3));
      } on Object catch (error, stackTrace) {
        // Non-Windows platforms don't install the native close interceptor.
        debugPrint(
            'Could not release the native close request: $error\n$stackTrace');
      }
    }
  }

  Future<void> _drainAndCloseStorage() async {
    // Stop producers first so no sync/background task can enqueue a write
    // while SQLite is being checkpointed and closed.
    await _autoSyncController.stop();
    _autoDirectSyncController.stop();
    await UnifiedSyncFactory.disposeDirect(_store);

    await _store.prepareForShutdown();
    await SqliteMigrationManager.shutdown();
  }

  @override
  void dispose() {
    _windowLifecycleChannel.setMethodCallHandler(null);
    unawaited(_autoSyncController.stop());
    _autoDirectSyncController.stop();
    unawaited(UnifiedSyncFactory.disposeDirect(_store));
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
          supportedLocales: const [Locale('en'), Locale('ar'), Locale('fr')],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: _startupError.isNotEmpty
              ? Builder(builder: (context) {
                  final tr = AppLocalizations.of(context);
                  return Scaffold(
                    body: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 560),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Icon(Icons.error_outline,
                                  size: 56,
                                  color: Theme.of(context).colorScheme.error),
                              const SizedBox(height: 16),
                              Text(
                                tr.text('app_startup_failed'),
                                textAlign: TextAlign.center,
                                style:
                                    Theme.of(context).textTheme.headlineSmall,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                localizeRuntimeMessage(_startupError, tr),
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                })
              : _store.isReady
                  ? Builder(builder: (context) {
                      final tr = AppLocalizations.of(context);
                      return LoginGatePage(
                        store: _store,
                        onLocaleChanged: _changeLocale,
                        child: PageTimingScope(
                          key: const ValueKey('MainShellScope'),
                          pageKey: 'MainShell',
                          pageLabel: tr.text('main_shell'),
                          child: MainShell(
                            store: _store,
                            onLogout: _stopSyncForLogout,
                            onLocaleChanged: _changeLocale,
                            onThemeModeChanged: _changeThemeMode,
                            themeMode: _themeMode,
                            onExitGuardChanged: _setActiveExitGuard,
                            onSyncSettingsChanged: () async {
                              _syncStarted = false;
                              unawaited(_startSyncAfterLogin());
                            },
                          ),
                        ),
                      );
                    })
                  : const Scaffold(
                      body: Center(child: CircularProgressIndicator())),
        );
      },
    );
  }
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
            message: message.isEmpty
                ? AppLocalizations.of(context).text('local_backup')
                : message,
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
                        ? AppLocalizations.of(context).text('backup_running')
                        : hasError
                            ? AppLocalizations.of(context).text('backup_issue')
                            : AppLocalizations.of(context).text('backed_up'),
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
      this.onLogout,
      this.onExitGuardChanged});

  final ValueChanged<Locale> onLocaleChanged;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ThemeMode themeMode;
  final AppStore store;
  final Future<void> Function()? onSyncSettingsChanged;
  final Future<void> Function()? onLogout;
  final ValueChanged<Future<bool> Function()?>? onExitGuardChanged;

  @override
  State<MainShell> createState() => _MainShellState();
}
