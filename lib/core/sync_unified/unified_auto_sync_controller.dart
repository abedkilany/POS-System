import 'dart:async';

import '../../data/app_store.dart';
import '../services/local_database_service.dart';
import '../services/cloud_sync_service.dart';
import '../services/lan_sync_service.dart';
import '../services/sync_diagnostics_log.dart';
import 'cloud_sync_transport_adapter.dart';
import 'lan_sync_transport_adapter.dart';
import 'sync_device_state.dart';
import 'unified_sync_engine.dart';

typedef AutoSnapshotProgressPresenter = void Function(
    String transport, double value, String label);

class UnifiedSyncFactory {
  const UnifiedSyncFactory._();

  static UnifiedSyncEngine cloudEngine(AppStore store,
      {CloudSyncSettings? settings, bool enabled = true}) {
    final current = settings ?? CloudSyncSettings.load();
    return UnifiedSyncEngine(
      CloudSyncTransportAdapter(
        service: CloudSyncService(store),
        settings: current.copyWith(enabled: enabled),
      ),
    );
  }

  static UnifiedSyncEngine lanEngine(AppStore store,
      {LanSyncSettings? settings}) {
    return UnifiedSyncEngine(
      LanSyncTransportAdapter(
        service: LanSyncService(store),
        settings: settings ?? LanSyncSettings.load(),
      ),
    );
  }

  static bool get isLanSetupComplete => LanSyncSettings.load().setupComplete;
  static bool get isLanHost => LanSyncSettings.load().isHost;
  static bool get isCloudConfigured => CloudSyncSettings.load().isConfigured;
  static bool cloudCanCheck(AppStore store) {
    final identity = store.appIdentity;
    final settings = CloudSyncSettings.load();
    final allowed = identity.isHost
        ? identity.isCloudEnabled
        : identity.isClient &&
            identity.activeSyncTransportNormalized == 'cloud';
    return allowed && settings.isConfigured;
  }
}

class UnifiedAutoLanSyncController {
  UnifiedAutoLanSyncController(this.store, {this.onSnapshotProgress});

  final AppStore store;
  final AutoSnapshotProgressPresenter? onSnapshotProgress;
  Timer? _periodicTimer;
  Timer? _debounceTimer;
  bool _running = false;
  bool _disposed = false;
  bool _signalLoopRunning = false;
  bool _workRefreshInFlight = false;
  String _lastSettingsSignature = '';

  String _settingsSignature(LanSyncSettings settings) => [
        settings.setupComplete,
        settings.mode.name,
        settings.hostModeEnabled,
        settings.host.trim(),
        settings.port,
        settings.autoSyncEnabled,
        settings.intervalSeconds,
        settings.secret.trim(),
      ].join('|');

  void _restartPeriodicTimer(LanSyncSettings settings) {
    _periodicTimer?.cancel();
    final interval = Duration(
      seconds: LanSyncSettings.normalizeIntervalSeconds(
        settings.intervalSeconds,
      ),
    );
    _periodicTimer = Timer.periodic(interval, (_) => _syncBecauseOfTimer());
  }

  bool _lanAllowedForCurrentRole(LanSyncSettings settings) {
    final identity = store.appIdentity;
    if (identity.isHost) return settings.setupComplete && settings.isHost;
    if (identity.isClient) {
      return identity.activeSyncTransportNormalized == 'lan' &&
          settings.setupComplete &&
          settings.isClient;
    }
    return false;
  }

  Future<void> start() async {
    _disposed = false;
    final settings = LanSyncSettings.load();
    _lastSettingsSignature = _settingsSignature(settings);

    final allowed = _lanAllowedForCurrentRole(settings);
    SyncDiagnosticsLog.add(
      '[SYNC_TRACE] autoLan:start device=${store.deviceId} '
      'role=${store.appIdentity.deviceRole.name} allowed=$allowed '
      'auto=${settings.autoSyncEnabled} mode=${settings.mode.name} '
      'host=${settings.host}:${settings.port}',
    );
    if (!allowed) {
      await UnifiedSyncFactory.lanEngine(store, settings: settings)
          .transportStopHostIfSupported();
    } else if (store.appIdentity.isHost && settings.isHost) {
      await UnifiedSyncFactory.lanEngine(store, settings: settings)
          .registerCurrentHost(transportName: 'lan');
    }

    store.removeListener(_onStoreChanged);
    store.addListener(_onStoreChanged);
    _restartPeriodicTimer(settings);

    if (allowed &&
        store.appIdentity.isClient &&
        settings.autoSyncEnabled &&
        settings.isClient) {
      unawaited(_signalLoop());
      unawaited(_runClientSync());
    }
  }

  Future<void> stop() async {
    _disposed = true;
    store.removeListener(_onStoreChanged);
    _periodicTimer?.cancel();
    _debounceTimer?.cancel();
    await UnifiedSyncFactory.lanEngine(store).transportStopHostIfSupported();
  }

  Future<void> _signalLoop() async {
    if (_signalLoopRunning) return;
    _signalLoopRunning = true;
    try {
      while (!_disposed) {
        final settings = LanSyncSettings.load();
        if (!_lanAllowedForCurrentRole(settings) ||
            !settings.autoSyncEnabled ||
            !settings.isClient ||
            settings.host.trim().isEmpty) {
          await Future<void>.delayed(const Duration(seconds: 5));
          continue;
        }
        try {
          final changed = await LanSyncService(store).waitForRealtimeSignal(
            settings.host,
            port: settings.port,
            token: settings.secret,
          );
          if (changed && !_disposed) {
            await _runClientSync();
          }
        } catch (_) {
          if (!_disposed) {
            await Future<void>.delayed(const Duration(seconds: 5));
          }
        }
      }
    } finally {
      _signalLoopRunning = false;
    }
  }

  void _onStoreChanged() {
    if (_disposed) return;
    final settings = LanSyncSettings.load();
    final signature = _settingsSignature(settings);
    if (signature != _lastSettingsSignature) {
      _lastSettingsSignature = signature;
      unawaited(_applySettingsChange(settings));
      _restartPeriodicTimer(settings);
    }
    if (!_lanAllowedForCurrentRole(settings) ||
        !settings.autoSyncEnabled ||
        !settings.isClient) {
      return;
    }

    unawaited(_refreshPendingClientWork());
  }

  Future<void> _refreshPendingClientWork() async {
    if (_disposed || _workRefreshInFlight) return;
    _workRefreshInFlight = true;
    try {
      final hasPendingClientWork =
          await LocalDatabaseService.pendingSyncQueueCountForTarget(
                'host',
                readyOnly: false,
              ) >
              0;
      if (_disposed ||
          !hasPendingClientWork ||
          !_lanAllowedForCurrentRole(LanSyncSettings.load()) ||
          !LanSyncSettings.load().autoSyncEnabled ||
          !LanSyncSettings.load().isClient) {
        return;
      }
      _debounceTimer?.cancel();
      _debounceTimer =
          Timer(const Duration(seconds: 1), () => _runClientSync());
    } finally {
      _workRefreshInFlight = false;
    }
  }

  void _syncBecauseOfTimer() {
    final settings = LanSyncSettings.load();
    final signature = _settingsSignature(settings);
    if (signature != _lastSettingsSignature) {
      _lastSettingsSignature = signature;
      unawaited(_applySettingsChange(settings));
      _restartPeriodicTimer(settings);
    }
    if (!_lanAllowedForCurrentRole(settings)) {
      unawaited(UnifiedSyncFactory.lanEngine(store, settings: settings)
          .transportStopHostIfSupported());
      return;
    }
    if (store.appIdentity.isHost && settings.isHost) {
      unawaited(UnifiedSyncFactory.lanEngine(store, settings: settings)
          .registerCurrentHost(transportName: 'lan'));
      return;
    }
    if (!settings.autoSyncEnabled) {
      return;
    }
    unawaited(store.retryFailedSyncQueue(target: 'host'));
    unawaited(_runClientSync());
  }

  Future<void> _applySettingsChange(LanSyncSettings settings) async {
    if (_disposed) return;
    final engine = UnifiedSyncFactory.lanEngine(store, settings: settings);
    if (!_lanAllowedForCurrentRole(settings) || !settings.isHost) {
      await engine.transportStopHostIfSupported();
    } else {
      await engine.registerCurrentHost(transportName: 'lan');
    }
    if (store.appIdentity.isClient &&
        _lanAllowedForCurrentRole(settings) &&
        settings.autoSyncEnabled &&
        settings.isClient) {
      await store.retryFailedSyncQueue(target: 'host');
      await _runClientSync();
    }
  }

  void Function(double value, String label)? _snapshotOnlyProgress(
      String transport) {
    final presenter = onSnapshotProgress;
    if (presenter == null) return null;
    var active = false;
    return (value, label) {
      final normalized = label.toLowerCase();
      if (!active && _looksLikeSnapshotLifecycleMessage(normalized)) {
        active = true;
      }
      if (active) presenter(transport, value, label);
    };
  }

  bool _looksLikeSnapshotLifecycleMessage(String normalized) {
    return normalized.contains('snapshot') ||
        normalized.contains('rebuild') ||
        normalized.contains('restore') ||
        normalized.contains('لقطة') ||
        normalized.contains('إعادة') ||
        normalized.contains('اعادة') ||
        normalized.contains('استرجاع');
  }

  Future<void> _runClientSync() async {
    if (_running || _disposed) return;
    final settings = LanSyncSettings.load();
    if (!_lanAllowedForCurrentRole(settings) ||
        !settings.autoSyncEnabled ||
        !settings.isClient ||
        settings.host.trim().isEmpty) {
      return;
    }

    _running = true;
    try {
      SyncDiagnosticsLog.add(
        '[SYNC_TRACE] autoLan:runClientSync start device=${store.deviceId} '
        'queue=${await LocalDatabaseService.pendingSyncQueueCountForTarget('host', readyOnly: false)}',
      );
      await store.retryFailedSyncQueue(target: 'host');
      final result =
          await UnifiedSyncFactory.lanEngine(store, settings: settings).syncNow(
        onProgress: _snapshotOnlyProgress('LAN'),
      );
      SyncDiagnosticsLog.add(
        '[SYNC_TRACE] autoLan:runClientSync done ok=${result.ok} '
        'pushed=${result.pushed} pulled=${result.pulled} '
        'message=${result.message}',
      );
    } finally {
      _running = false;
    }
  }
}

class UnifiedAutoCloudSyncController {
  UnifiedAutoCloudSyncController(this.store, {this.onSnapshotProgress});

  final AppStore store;
  final AutoSnapshotProgressPresenter? onSnapshotProgress;

  bool _cloudAllowedForCurrentRole() {
    final identity = store.appIdentity;
    if (identity.isHost) {
      return identity.isCloudEnabled;
    }
    if (!identity.isClient) return false;
    return identity.activeSyncTransportNormalized == 'cloud';
  }

  Timer? _timer;
  Timer? _debounceTimer;
  bool _running = false;
  bool _disposed = false;
  bool _signalLoopRunning = false;
  bool _workRefreshInFlight = false;
  String _lastSettingsSignature = '';

  bool _cloudReady(CloudSyncSettings settings) =>
      settings.autoSyncEnabled &&
      settings.isConfigured &&
      _cloudAllowedForCurrentRole();

  String _settingsSignature(CloudSyncSettings settings) => [
        settings.autoSyncEnabled,
        settings.isConfigured,
        settings.apiBaseUrl.trim(),
        settings.intervalSeconds,
        store.appIdentity.deviceRole.name,
        store.appIdentity.activeSyncTransportNormalized,
      ].join('|');

  void _restartPeriodicTimer(CloudSyncSettings settings) {
    _timer?.cancel();
    final interval = Duration(
      seconds: CloudSyncSettings.normalizeIntervalSeconds(
        settings.intervalSeconds,
      ),
    );
    _timer = Timer.periodic(interval, (_) => _tick());
  }

  Future<void> start() async {
    stop();
    _disposed = false;
    final settings = CloudSyncSettings.load();
    _lastSettingsSignature = _settingsSignature(settings);
    SyncDiagnosticsLog.add(
      '[SYNC_TRACE] autoCloud:start device=${store.deviceId} '
      'role=${store.appIdentity.deviceRole.name} '
      'ready=${_cloudReady(settings)} auto=${settings.autoSyncEnabled} '
      'configured=${settings.isConfigured} apiBase=${settings.apiBaseUrl} '
      'transport=${store.appIdentity.activeSyncTransportNormalized}',
    );

    store.removeListener(_onStoreChanged);
    store.addListener(_onStoreChanged);

    _restartPeriodicTimer(settings);
    unawaited(_signalLoop());
    if (_cloudReady(settings)) {
      await _tick();
    }
  }

  void stop() {
    _disposed = true;
    store.removeListener(_onStoreChanged);
    _timer?.cancel();
    _debounceTimer?.cancel();
    _timer = null;
    _debounceTimer = null;
  }

  Future<void> _signalLoop() async {
    if (_signalLoopRunning) return;
    _signalLoopRunning = true;
    var wasReady = false;
    try {
      while (!_disposed) {
        final settings = CloudSyncSettings.load();
        final ready = _cloudReady(settings);
        if (!ready) {
          wasReady = false;
          await Future<void>.delayed(const Duration(seconds: 5));
          continue;
        }
        try {
          if (!wasReady) {
            wasReady = true;
            await _tick();
          }
          await for (final signal
              in CloudSyncService(store).watchRealtimeSignals(settings)) {
            if (_disposed) break;
            final current = CloudSyncSettings.load();
            if (!_cloudReady(current) ||
                _settingsSignature(current) != _settingsSignature(settings)) {
              break;
            }
            SyncDiagnosticsLog.add(
              '[SYNC_TRACE] autoCloud:realtimeWake type=${signal.type} '
              'latestSequence=${signal.latestSequence} '
              'pendingRequests=${signal.pendingRequests}',
            );
            await _tick();
          }
          if (!_disposed) {
            await Future<void>.delayed(const Duration(seconds: 2));
          }
        } catch (error) {
          SyncDiagnosticsLog.add(
            '[SYNC_TRACE] autoCloud:realtimeFallback error=$error',
          );
          try {
            final changed =
                await CloudSyncService(store).waitForRealtimeSignal(settings);
            if (changed && !_disposed) {
              await _tick();
            }
          } catch (_) {}
          if (!_disposed) {
            await Future<void>.delayed(const Duration(seconds: 5));
          }
        }
      }
    } finally {
      _signalLoopRunning = false;
    }
  }

  void _onStoreChanged() {
    if (_disposed) return;
    final settings = CloudSyncSettings.load();
    final signature = _settingsSignature(settings);
    if (signature != _lastSettingsSignature) {
      _lastSettingsSignature = signature;
      _restartPeriodicTimer(settings);
    }
    if (!settings.autoSyncEnabled ||
        !settings.isConfigured ||
        !_cloudAllowedForCurrentRole()) {
      return;
    }
    unawaited(_refreshPendingCloudWork());
  }

  Future<void> _refreshPendingCloudWork() async {
    if (_disposed || _workRefreshInFlight) return;
    _workRefreshInFlight = true;
    try {
      final settings = CloudSyncSettings.load();
      if (!settings.autoSyncEnabled ||
          !settings.isConfigured ||
          !_cloudAllowedForCurrentRole()) {
        return;
      }
      final cloudCount =
          await LocalDatabaseService.pendingSyncQueueCountForTarget(
        'cloud',
        readyOnly: false,
      );
      final relayCount =
          await LocalDatabaseService.pendingSyncQueueCountForTarget(
        'cloud_host',
        readyOnly: false,
      );
      final pendingAuthorityCount =
          await LocalDatabaseService.pendingSyncChangesCount();
      final hasPendingCloudWork =
          cloudCount > 0 || relayCount > 0 || pendingAuthorityCount > 0;
      if (_disposed || !hasPendingCloudWork) return;
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(seconds: 1), () => _tick());
    } finally {
      _workRefreshInFlight = false;
    }
  }

  void Function(double value, String label)? _snapshotOnlyProgress(
      String transport) {
    final presenter = onSnapshotProgress;
    if (presenter == null) return null;
    var active = false;
    return (value, label) {
      final normalized = label.toLowerCase();
      if (!active && _looksLikeSnapshotLifecycleMessage(normalized)) {
        active = true;
      }
      if (active) presenter(transport, value, label);
    };
  }

  bool _looksLikeSnapshotLifecycleMessage(String normalized) {
    return normalized.contains('snapshot') ||
        normalized.contains('rebuild') ||
        normalized.contains('restore') ||
        normalized.contains('لقطة') ||
        normalized.contains('إعادة') ||
        normalized.contains('اعادة') ||
        normalized.contains('استرجاع');
  }

  Future<void> _tick() async {
    if (_running || _disposed) {
      SyncDiagnosticsLog.add(
        '[SYNC_TRACE] autoCloud:tickSkipped running=$_running disposed=$_disposed',
      );
      return;
    }
    _running = true;
    try {
      var settings = CloudSyncSettings.load();
      final cloudCount =
          await LocalDatabaseService.pendingSyncQueueCountForTarget(
        'cloud',
        readyOnly: false,
      );
      final relayCount =
          await LocalDatabaseService.pendingSyncQueueCountForTarget(
        'cloud_host',
        readyOnly: false,
      );
      final pendingAuthorityCount =
          await LocalDatabaseService.pendingSyncChangesCount();
      SyncDiagnosticsLog.add(
        '[SYNC_TRACE] autoCloud:tick start device=${store.deviceId} '
        'role=${store.appIdentity.deviceRole.name} '
        'ready=${_cloudReady(settings)} auto=${settings.autoSyncEnabled} '
        'configured=${settings.isConfigured} cursor=${settings.lastPullCursor?.toIso8601String()} '
        'cloudQueue=$cloudCount relayQueue=$relayCount',
      );
      if (settings.autoSyncEnabled &&
          settings.isConfigured &&
          _cloudAllowedForCurrentRole()) {
        final hasOutgoingWork =
            cloudCount > 0 || relayCount > 0 || pendingAuthorityCount > 0;
        final now = DateTime.now().toUtc();
        final deviceState = SyncDeviceStateStore.load(store.appIdentity);
        final hasAppliedCloudBaseline =
            store.appIdentity.isClient && deviceState.lastAppliedSequence > 0;
        final pendingProvisioning =
            store.appIdentity.isClient && CloudProvisioningStatus.isPending;
        if (pendingProvisioning) {
          if (hasAppliedCloudBaseline) {
            await CloudProvisioningStatus.markComplete(
              message: 'Initial Store data installed.',
            );
          } else {
            final lastAttempt = CloudProvisioningStatus.lastAttemptAt;
            final shouldRequest = lastAttempt == null ||
                now.difference(lastAttempt) > const Duration(minutes: 10);
            if (shouldRequest) {
              await CloudProvisioningStatus.markAttempted(now);
              final requestedAt = CloudProvisioningStatus.requestedAt ?? now;
              await CloudSyncService(store)
                  .requestFreshHostSnapshot(settings, requestedAt: requestedAt);
              settings = settings.copyWith(clearLastPullCursor: true);
            }
          }
        }

        final cursor = settings.lastPullCursor;
        final staleClient = store.appIdentity.isClient &&
            !hasAppliedCloudBaseline &&
            cursor != null &&
            now.difference(cursor.toUtc()) > const Duration(days: 7);
        await store.recoverStaleInProgressSyncQueue(target: 'cloud');
        await store.recoverStaleInProgressSyncQueue(target: 'cloud_host');
        await store.retryFailedSyncQueue(target: 'cloud');
        await store.retryFailedSyncQueue(target: 'cloud_host');
        final engine =
            UnifiedSyncFactory.cloudEngine(store, settings: settings);
        if (staleClient && !hasOutgoingWork) {
          final repair = await engine.rebuildFromHostSnapshot(
            onProgress: _snapshotOnlyProgress('Cloud'),
          );
          if (!repair.ok) {
            await CloudSyncSettings.clearSavedPullCursor();
            settings = settings.copyWith(clearLastPullCursor: true);
          } else {
            settings = CloudSyncSettings.load();
          }
        }
        final result =
            await UnifiedSyncFactory.cloudEngine(store, settings: settings)
                .syncNow(
          onProgress: _snapshotOnlyProgress('Cloud'),
        );
        SyncDiagnosticsLog.add(
          '[SYNC_TRACE] autoCloud:tick syncDone ok=${result.ok} '
          'pushed=${result.pushed} pulled=${result.pulled} '
          'restored=${result.restoredSnapshot} message=${result.message}',
        );
      } else {
        SyncDiagnosticsLog.add(
          '[SYNC_TRACE] autoCloud:tick notReady auto=${settings.autoSyncEnabled} '
          'configured=${settings.isConfigured} allowed=${_cloudAllowedForCurrentRole()}',
        );
      }
    } finally {
      SyncDiagnosticsLog.add('[SYNC_TRACE] autoCloud:tick end');
      _running = false;
    }
  }
}

extension UnifiedLanHostServerControl on UnifiedSyncEngine {
  Future<void> transportStopHostIfSupported() async {
    final currentTransport = transport;
    if (currentTransport is LanSyncTransportAdapter) {
      await currentTransport.stopHostIfSupported();
    }
  }
}
