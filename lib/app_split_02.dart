part of 'app.dart';

class _MainShellState extends State<MainShell> {
  int selectedIndex = 0;
  bool _drawerNavigationLocked = false;
  Future<bool> Function()? _salesExitGuard;
  bool _firstBuildMarked = false;
  late final AppUpdateService _updateService = getAppUpdateService();
  late final VoidCallback _updateStatusListener;
  late final VoidCallback _storeListener;
  VoidCallback? _cancelDownloadUpdate;
  AppUpdateInfo? _availableUpdate;

  Future<void> _editSaleShortcut(
      SaleShortcutAction action, AppLocalizations tr) async {
    final settings = SaleShortcutSettings.load();
    final currentKey =
        settings.keyForSaleAction(action) ?? SaleShortcutSettings.noneKey;
    final selectedKey = await showShortcutKeyPicker(
      context: context,
      title: tr.text('shortcut_change'),
      currentKey: currentKey,
      noneLabel: tr.text('shortcut_none'),
      cancelLabel: tr.text('cancel'),
      saveLabel: tr.text('save'),
    );
    if (selectedKey == null || !mounted) return;
    if (settings.isSaleKeyUsedByAnotherAction(selectedKey, action)) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr.text('shortcut_key_already_used'))));
      return;
    }
    final next = settings.copyWithSaleActionKey(action, selectedKey);
    await next.save();
    if (mounted) setState(() {});
  }

  Widget _buildSalesShortcutStrip(AppLocalizations tr) {
    return ValueListenableBuilder<int>(
      valueListenable: SaleShortcutSettings.revision,
      builder: (context, _, __) {
        final settings = SaleShortcutSettings.load();
        final chips = <Widget>[];
        for (final action in SaleShortcutAction.values) {
          final keyName = settings.keyForSaleAction(action);
          if (keyName == null || keyName == SaleShortcutSettings.noneKey) {
            continue;
          }
          chips.add(Padding(
            padding: const EdgeInsetsDirectional.only(end: 4),
            child: ShortcutGuideChip(
              keyName: keyName,
              label: tr.text(action.labelKey),
              onPressed: () => _editSaleShortcut(action, tr),
            ),
          ));
        }
        if (chips.isEmpty) return const SizedBox.shrink();
        return SizedBox(
          // Keep enough room for the configured shortcut chips. The horizontal
          // scroll remains available when the window is narrower than this.
          width: 900,
          height: 48,
          child: ClipRect(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: chips),
            ),
          ),
        );
      },
    );
  }

  bool _checkingForUpdate = false;
  bool _downloadingUpdate = false;
  bool _installingUpdate = false;
  bool _refreshingData = false;
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

  Future<void> _refreshData() async {
    if (_refreshingData) return;
    if (mounted) setState(() => _refreshingData = true);
    try {
      // Reload the store in place. The shell and the current page remain
      // mounted, so page-local state such as filters, drafts, and scroll
      // position is preserved while the refreshed data is published once.
      await widget.store.reloadAllAfterDatabaseChange();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                '${AppLocalizations.of(context).text('refresh')}: $error')),
      );
    } finally {
      if (mounted) setState(() => _refreshingData = false);
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
      if (selectedIndex != index && _salesExitGuard != null) {
        final canLeave = await _salesExitGuard!();
        if (!canLeave) return;
      }
      if (!mounted) return;
      if (selectedIndex != index) {
        setState(() => selectedIndex = index);
      }
      if (!drawerContext.mounted) return;
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
    final canUseAssistant = widget.store.canViewAccounting ||
        widget.store.canViewSales ||
        widget.store.canViewPurchases ||
        widget.store.canViewExpenses ||
        widget.store.canViewCashBox ||
        widget.store.canViewInventory;
    final items = [
      if (isPlatformAdmin)
        _ShellItem(
            label: tr.text('subscribers'),
            icon: Icons.admin_panel_settings_outlined,
            selectedIcon: Icons.admin_panel_settings,
            page: timedPage('AdminSubscribersPage',
                tr.text('admin_subscribers'), const AdminSubscribersPage())),
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
      if (widget.store.canAccessPage('products'))
        _ShellItem(
            label: tr.text('barcode_labels'),
            icon: Icons.qr_code_2_outlined,
            selectedIcon: Icons.qr_code_2,
            page: timedPage('BarcodeLabelsPage', tr.text('barcode_labels'),
                BarcodeLabelsPage(store: widget.store))),
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
                'SalesPage',
                tr.text('sales'),
                SalesPage(
                  store: widget.store,
                  onExitGuardChanged: (guard) {
                    _salesExitGuard = guard;
                    widget.onExitGuardChanged?.call(guard);
                  },
                ))),
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
      if (widget.store.canViewCashBox)
        _ShellItem(
            label: tr.text('cash_box'),
            icon: Icons.point_of_sale_outlined,
            selectedIcon: Icons.point_of_sale,
            page: timedPage('CashPage', tr.text('cash_box'),
                CashPage(store: widget.store))),
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
      if (canUseAssistant)
        _ShellItem(
            label: tr.text('assistant_chat_title'),
            icon: Icons.auto_awesome_outlined,
            selectedIcon: Icons.auto_awesome,
            page: timedPage(
                'AssistantChatPage',
                tr.text('assistant_chat_title'),
                AssistantChatPage(store: widget.store))),
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
        label: tr.text('access_denied'),
        icon: Icons.lock_outline,
        selectedIcon: Icons.lock,
        page: timedPage(
            '_NoAccessPage', tr.text('no_access'), const _NoAccessPage()),
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
            toolbarHeight:
                resolvedItems[selectedIndex].label == tr.text('sales')
                    ? 64
                    : null,
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
              IconButton(
                tooltip: tr.text('refresh'),
                onPressed: _refreshingData ? null : _refreshData,
                icon: _refreshingData
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
              ),
              LocalAutoBackupIndicator(),
              if (resolvedItems[selectedIndex].label == tr.text('sales'))
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (Localizations.localeOf(context).languageCode ==
                        'ar') ...[
                      _buildSalesShortcutStrip(tr),
                      const SizedBox(width: 6),
                      HostConnectionIndicator(store: widget.store),
                    ] else ...[
                      HostConnectionIndicator(store: widget.store),
                      const SizedBox(width: 6),
                      _buildSalesShortcutStrip(tr),
                    ],
                  ],
                )
              else
                HostConnectionIndicator(store: widget.store),
              PopupMenuButton<String>(
                tooltip: widget.store.activeUser?.fullName ?? tr.text('logout'),
                onSelected: (value) async {
                  if (value == 'language_en') {
                    widget.onLocaleChanged(const Locale('en'));
                  } else if (value == 'language_ar') {
                    widget.onLocaleChanged(const Locale('ar'));
                  } else if (value == 'language_fr') {
                    widget.onLocaleChanged(const Locale('fr'));
                  } else if (value == 'logout') {
                    await widget.onLogout?.call();
                    await AccountAuthCache.clear();
                    await widget.store.logout();
                  }
                },
                itemBuilder: (context) {
                  final currentLocale = Localizations.localeOf(context);
                  final languageCode = currentLocale.languageCode;
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
                        if (languageCode == 'en')
                          const Icon(Icons.check, size: 18),
                      ]),
                    ),
                    PopupMenuItem<String>(
                      value: 'language_ar',
                      child: Row(children: [
                        const Text('🇱🇧'),
                        const SizedBox(width: 10),
                        Expanded(child: Text(tr.text('language_arabic'))),
                        if (languageCode == 'ar')
                          const Icon(Icons.check, size: 18),
                      ]),
                    ),
                    PopupMenuItem<String>(
                      value: 'language_fr',
                      child: Row(children: [
                        const Text('🇫🇷'),
                        const SizedBox(width: 10),
                        Expanded(child: Text(tr.text('language_french'))),
                        if (languageCode == 'fr')
                          const Icon(Icons.check, size: 18),
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
          body: resolvedItems[selectedIndex].page,
        );
      },
    );
  }
}
