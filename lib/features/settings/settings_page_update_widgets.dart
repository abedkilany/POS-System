part of 'settings_page.dart';

class _WindowsUpdateStatusCard extends StatefulWidget {
  const _WindowsUpdateStatusCard();

  @override
  State<_WindowsUpdateStatusCard> createState() =>
      _WindowsUpdateStatusCardState();
}

class _WindowsUpdateStatusCardState extends State<_WindowsUpdateStatusCard> {
  late final AppUpdateService _service = getAppUpdateService();
  late final VoidCallback _updateStatusListener;
  VoidCallback? _cancelDownload;
  AppUpdateInfo? _latest;
  DateTime? _lastCheckedAt;
  bool _checking = false;
  bool _downloading = false;
  bool _installing = false;
  double? _downloadProgress;
  String? _downloadedInstallerPath;
  String _statusKey = 'you_are_up_to_date';
  String _statusValue = '';

  @override
  void initState() {
    super.initState();
    _updateStatusListener = () {
      if (!mounted) return;
      final state = AppUpdateService.status.value;
      setState(() {
        _latest = state.latest;
        _lastCheckedAt = state.lastCheckedAt;
        _checking = state.checking;
        _downloading = state.downloading;
        _installing = state.installing;
        _downloadProgress = state.downloadProgress;
        _downloadedInstallerPath = state.downloadedInstallerPath;
        if (state.lastError.isNotEmpty && !_downloading && !_installing) {
          _statusKey = 'could_not_check_updates';
          _statusValue = '';
        } else if (_installing) {
          _statusKey = 'installing_update';
          _statusValue = '';
        } else if (_downloading) {
          _statusKey = 'downloading';
          _statusValue = _latest?.displayVersion ?? '';
        } else if (_readyToInstall) {
          _statusKey = 'update_downloaded';
          _statusValue = _latest?.displayVersion ?? '';
        } else if (_hasUpdate) {
          _statusKey = 'update_available';
          _statusValue = _latest?.displayVersion ?? '';
        } else {
          _statusKey = 'you_are_up_to_date';
          _statusValue = '';
        }
      });
    };
    AppUpdateService.status.addListener(_updateStatusListener);
    _updateStatusListener();
  }

  @override
  void dispose() {
    AppUpdateService.status.removeListener(_updateStatusListener);
    super.dispose();
  }

  bool get _hasUpdate =>
      _latest?.isNewerThan(AppBrand.versionName, AppBrand.buildNumber) ?? false;

  bool get _readyToInstall => _downloadedInstallerPath != null;

  bool get _isBusy => _downloading || _installing;

  String _lastCheckedText(AppLocalizations tr) {
    final value = _lastCheckedAt;
    if (value == null) return tr.text('last_checked_not_checked');
    final local = value.toLocal();
    final date = DateFormat('MMM d, h:mm a').format(local);
    return tr.format('last_checked_at', {'time': date});
  }

  Future<void> _check() async {
    if (_checking) return;
    final tr = AppLocalizations.of(context);
    final previousUpdate = _latest;
    setState(() {
      _checking = true;
      _statusKey = 'checking_for_updates';
      _statusValue = '';
    });
    try {
      final latest = await _service.fetchLatest();
      if (!mounted) return;
      setState(() {
        _latest = latest;
        _lastCheckedAt = DateTime.now();
        final updateChanged =
            previousUpdate?.displayVersion != latest?.displayVersion;
        if (latest == null || updateChanged) {
          _downloadedInstallerPath = null;
          _downloadProgress = null;
          _downloading = false;
          _installing = false;
        }
        _statusKey = _hasUpdate ? 'update_available' : 'you_are_up_to_date';
        _statusValue = latest?.displayVersion ?? '';
      });
      if (latest != null) {
        final restoredPath = await _service.getDownloadedInstallerPath(latest);
        if (!mounted) return;
        setState(() {
          _downloadedInstallerPath = restoredPath;
          if (restoredPath == null) {
            _downloadProgress = null;
            _downloading = false;
            _installing = false;
          } else {
            _statusKey = 'update_downloaded';
          }
        });
      } else {
        await _service.clearDownloadedUpdate();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _lastCheckedAt = DateTime.now();
        _statusKey = 'could_not_check_updates';
        _statusValue = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                tr.format('update_check_failed', {'error': error.toString()}))),
      );
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _downloadUpdate() async {
    final update = _latest;
    if (update == null || !_hasUpdate) return;
    if (_isBusy) return;
    final tr = AppLocalizations.of(context);
    _cancelDownload = null;
    setState(() {
      _downloading = true;
      _downloadProgress = 0;
      _statusKey = 'downloading';
      _statusValue = update.displayVersion;
    });
    try {
      final installerPath = await _service.downloadUpdate(
        update,
        onProgress: (value) {
          if (!mounted) return;
          setState(() => _downloadProgress = value);
        },
        registerCancel: (cancel) => _cancelDownload = cancel,
      );
      if (!mounted) return;
      setState(() {
        _downloadedInstallerPath = installerPath;
        _downloading = false;
        _downloadProgress = 1;
        _statusKey = 'update_downloaded';
        _statusValue = update.displayVersion;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr.text('update_downloaded'))),
      );
    } catch (error) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      setState(() {
        _downloading = false;
        _downloadProgress = null;
      });
      if (error.toString().contains('Update download cancelled')) {
        return;
      }
      await _service.clearDownloadedUpdate();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
            content:
                Text(tr.format('update_failed', {'error': error.toString()}))),
      );
    }
  }

  Future<void> _installReadyUpdate() async {
    await _installUpdate();
  }

  Future<void> _installUpdate() async {
    final installerPath = _downloadedInstallerPath;
    if (installerPath == null || installerPath.trim().isEmpty || _installing) {
      return;
    }
    final tr = AppLocalizations.of(context);
    setState(() {
      _installing = true;
      _downloadProgress = null;
      _statusKey = 'installing_update';
      _statusValue = '';
    });
    try {
      await _service.launchInstaller(installerPath);
      if (!mounted) return;
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      SystemNavigator.pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _installing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(tr.format('update_failed', {'error': error.toString()}))),
      );
    }
  }

  Future<void> _cancelDownloadUpdate() async {
    if (!_downloading) return;
    final cancel = _cancelDownload;
    _cancelDownload = null;
    cancel?.call();
    await _service.clearDownloadedUpdate();
    if (!mounted) return;
    setState(() {
      _downloading = false;
      _downloadProgress = null;
      _statusKey = _hasUpdate ? 'update_available' : 'you_are_up_to_date';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_service.isSupported) return const SizedBox.shrink();
    final tr = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final iconColor = _readyToInstall
        ? Colors.green.shade700
        : _hasUpdate
            ? colorScheme.primary
            : Colors.blue.shade700;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 18),
      padding: VentioResponsive.cardInsets(context),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 620;
          final showProgressRing = _downloading || _installing;
          final statusIcon = SizedBox(
            width: 76,
            height: 76,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (showProgressRing)
                  SizedBox(
                    width: 76,
                    height: 76,
                    child: CircularProgressIndicator(
                      value: _installing ? null : _downloadProgress,
                      strokeWidth: 4,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(colorScheme.primary),
                    ),
                  ),
                Icon(Icons.sync_outlined, size: 40, color: iconColor),
                if (!showProgressRing)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: _readyToInstall
                            ? Colors.green
                            : colorScheme.primary,
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: colorScheme.surface, width: 2),
                      ),
                      child: Icon(
                        _readyToInstall ? Icons.check : Icons.arrow_downward,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
              ],
            ),
          );
          final statusText = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                (_statusKey == 'update_available' ||
                            _statusKey == 'update_downloaded') &&
                        _statusValue.isNotEmpty
                    ? '${tr.text(_statusKey)}: $_statusValue'
                    : tr.text(_statusKey),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                _lastCheckedText(tr),
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
              if (_downloading || _installing) ...[
                const SizedBox(height: 8),
                Text(
                  _installing
                      ? tr.text('installing_update')
                      : _downloadProgress == null
                          ? tr.text('downloading')
                          : '${tr.text('downloading')} ${(_downloadProgress! * 100).clamp(0, 100).toStringAsFixed(0)}%',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ],
          );
          final action = _hasUpdate
              ? (_downloading
                  ? TextButton.icon(
                      onPressed: _cancelDownloadUpdate,
                      icon: const Icon(Icons.close),
                      label: Text(tr.text('cancel')),
                    )
                  : _readyToInstall
                      ? FilledButton.icon(
                          onPressed: _installing ? null : _installReadyUpdate,
                          icon: const Icon(Icons.check_circle_outline),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.green.shade600,
                            foregroundColor: Colors.white,
                          ),
                          label: Text(tr.text('update_now')),
                        )
                      : FilledButton.icon(
                          onPressed: _installing ? null : _downloadUpdate,
                          icon: const Icon(Icons.download_outlined),
                          label: Text(tr.text('install_update')),
                        ))
              : FilledButton(
                  onPressed: _checking ? null : _check,
                  child: _checking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(tr.text('check_for_updates')),
                );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    statusIcon,
                    const SizedBox(width: 24),
                    Expanded(child: statusText),
                  ],
                ),
                const SizedBox(height: 16),
                Align(alignment: Alignment.centerRight, child: action),
              ],
            );
          }
          return Row(
            children: [
              statusIcon,
              const SizedBox(width: 24),
              Expanded(child: statusText),
              const SizedBox(width: 16),
              action,
            ],
          );
        },
      ),
    );
  }
}
