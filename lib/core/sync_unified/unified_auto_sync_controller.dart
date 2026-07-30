import 'dart:async';

import 'package:http/http.dart' as http;

import '../../data/app_store.dart';
import '../services/cloud_sync_service.dart';
import '../services/local_database_service.dart';
import '../services/lan_sync_service.dart';
import '../services/sync_diagnostics_log.dart';
import 'cloud_sync_transport_adapter.dart';
import 'lan_sync_transport_adapter.dart';
import 'direct_sync_transport_adapter.dart';
import 'unified_sync_policy.dart';
import 'sync_device_state.dart';
import 'unified_sync_engine.dart';
import 'sync_contracts.dart';

typedef AutoSnapshotProgressPresenter = void Function(
    String transport, double value, String label);

typedef _SignalLoopWaitResult = ({
  bool changed,
  String? debugLabel,
});

Future<void> _runUnifiedRealtimeSignalLoop<TSettings>({
  required bool Function() isDisposed,
  required TSettings Function() loadSettings,
  required bool Function(TSettings settings) isReady,
  required Future<_SignalLoopWaitResult> Function(TSettings settings)
      waitForSignal,
  required Future<void> Function() onWake,
  Future<void> Function()? onFirstReady,
  void Function(Object error)? onError,
  Duration idleDelay = const Duration(seconds: 5),
  Duration postWakeDelay = Duration.zero,
}) async {
  var wasReady = false;
  while (!isDisposed()) {
    final settings = loadSettings();
    if (!isReady(settings)) {
      wasReady = false;
      await Future<void>.delayed(idleDelay);
      continue;
    }
    try {
      if (!wasReady) {
        wasReady = true;
        if (onFirstReady != null) {
          await onFirstReady();
        }
      }
      final result = await waitForSignal(settings);
      if (result.changed && !isDisposed()) {
        if ((result.debugLabel ?? '').trim().isNotEmpty) {
          SyncDiagnosticsLog.add(result.debugLabel!);
        }
        await onWake();
      }
      if (!isDisposed() && postWakeDelay > Duration.zero) {
        await Future<void>.delayed(postWakeDelay);
      }
    } catch (error) {
      onError?.call(error);
      if (!isDisposed()) {
        await Future<void>.delayed(idleDelay);
      }
    }
  }
}

Future<void> _recoverSyncQueues(
  AppStore store,
  List<String> targets,
) async {
  for (final target in targets) {
    await store.recoverStaleInProgressSyncQueue(target: target);
    await store.retryFailedSyncQueue(target: target);
  }
}

Future<void> _recoverClientSyncQueue(AppStore store) =>
    _recoverSyncQueues(store, const ['host']);

Future<void> _recoverCloudSyncQueues(AppStore store) =>
    _recoverSyncQueues(store, const ['cloud', 'cloud_host']);

class UnifiedSyncFactory {
  const UnifiedSyncFactory._();

  static UnifiedSyncEngine cloudEngine(AppStore store,
      {CloudSyncSettings? settings, bool enabled = true, http.Client? client}) {
    final current = settings ?? CloudSyncSettings.load();
    return UnifiedSyncEngine(
      CloudSyncTransportAdapter(
        service: CloudSyncService(store, client: client),
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

  static UnifiedSyncEngine directEngine(AppStore store) {
    return UnifiedSyncEngine(
      DirectSyncTransportAdapter(store),
    );
  }

  static UnifiedSyncEngine activeEngine(
    AppStore store, {
    bool cloudEnabled = true,
    CloudSyncSettings? cloudSettings,
    LanSyncSettings? lanSettings,
  }) {
    final identity = store.appIdentity;
    if (identity.activeSyncTransportNormalized == 'direct') {
      return directEngine(store);
    }
    if (identity.activeSyncTransportNormalized == 'cloud') {
      return cloudEngine(
        store,
        settings: cloudSettings ?? CloudSyncSettings.load(),
        enabled: cloudEnabled,
      );
    }
    return lanEngine(store, settings: lanSettings ?? LanSyncSettings.load());
  }

  static bool get isLanSetupComplete => LanSyncSettings.load().setupComplete;
  static bool get isLanHost => LanSyncSettings.load().isHost;
  static bool get isCloudConfigured => CloudSyncSettings.load().isConfigured;
  static bool cloudCanCheck(AppStore store) {
    final settings = CloudSyncSettings.load();
    final allowed = UnifiedSyncPolicy.isCloudAllowedForCurrentRole(
      store.appIdentity,
    );
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
    return UnifiedSyncPolicy.isLanAllowedForCurrentRole(
      store.appIdentity,
      setupComplete: settings.setupComplete,
      isHostModeEnabled: settings.isHost,
      isClientModeEnabled: settings.isClient,
    );
  }

  Future<void> start() async {
    _disposed = false;
    final settings = LanSyncSettings.load();
    _lastSettingsSignature = _settingsSignature(settings);

    // A LAN-only Host is the authority; it must not retain legacy queue rows
    // that were incorrectly targeted back to the Host itself.
    await store.settleLegacyLanHostQueue();

    final allowed = _lanAllowedForCurrentRole(settings);
    SyncDiagnosticsLog.add(
      '[SYNC_TRACE] autoLan:start device=${store.deviceId} '
      'role=${store.appIdentity.deviceRole.name} allowed=$allowed '
      'auto=${settings.autoSyncEnabled} mode=${settings.mode.name} '
      'host=${settings.host}:${settings.port}',
    );
    if (!allowed) {
      await UnifiedSyncFactory.lanEngine(store, settings: settings)
          .stopHostIfSupported();
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
    await UnifiedSyncFactory.lanEngine(store).stopHostIfSupported();
  }

  Future<void> _signalLoop() async {
    if (_signalLoopRunning) return;
    _signalLoopRunning = true;
    try {
      await _runUnifiedRealtimeSignalLoop<LanSyncSettings>(
        isDisposed: () => _disposed,
        loadSettings: LanSyncSettings.load,
        isReady: (settings) =>
            _lanAllowedForCurrentRole(settings) &&
            settings.autoSyncEnabled &&
            settings.isClient &&
            settings.host.trim().isNotEmpty,
        waitForSignal: (settings) async {
          final changed = await UnifiedSyncFactory.lanEngine(
            store,
            settings: settings,
          ).waitForRealtimeSignal();
          return (changed: changed, debugLabel: null);
        },
        onWake: _runClientSync,
      );
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
          .stopHostIfSupported());
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
    unawaited(_recoverClientSyncQueue(store));
    unawaited(_runClientSync());
  }

  Future<void> _applySettingsChange(LanSyncSettings settings) async {
    if (_disposed) return;
    final engine = UnifiedSyncFactory.lanEngine(store, settings: settings);
    if (!_lanAllowedForCurrentRole(settings) || !settings.isHost) {
      await engine.stopHostIfSupported();
    } else {
      await engine.registerCurrentHost(transportName: 'lan');
    }
    if (store.appIdentity.isClient &&
        _lanAllowedForCurrentRole(settings) &&
        settings.autoSyncEnabled &&
        settings.isClient) {
      await _recoverClientSyncQueue(store);
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
      await store.retryFailedSyncQueue(target: UnifiedSyncQueueTarget.host);
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
    if (store.appIdentity.activeSyncTransportNormalized == 'direct') {
      return false;
    }
    return UnifiedSyncPolicy.isCloudAllowedForCurrentRole(store.appIdentity);
  }

  Timer? _timer;
  Timer? _debounceTimer;
  bool _running = false;
  bool _disposed = false;
  bool _signalLoopRunning = false;
  bool _hostRealtimeLoopRunning = false;
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
    // A Cloud Host must keep a realtime channel open. The heartbeat only
    // marks the Host online; snapshot requests are delivered over this stream.
    if (store.appIdentity.isHost) {
      unawaited(_hostRealtimeLoop());
    } else {
      unawaited(_signalLoop());
    }
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

  Future<void> _hostRealtimeLoop() async {
    if (_hostRealtimeLoopRunning) return;
    _hostRealtimeLoopRunning = true;
    var retrySeconds = 1;
    try {
      while (!_disposed && store.appIdentity.isHost) {
        final settings = CloudSyncSettings.load();
        if (!_cloudReady(settings)) {
          await Future<void>.delayed(const Duration(seconds: 5));
          continue;
        }
        try {
          SyncDiagnosticsLog.add(
              '[SYNC_TRACE] autoCloud:hostRealtime connecting');
          final service = CloudSyncService(store);
          await for (final _ in service.watchRealtimeSignals(settings)) {
            if (_disposed || !store.appIdentity.isHost) break;
          }
          if (!_disposed) {
            SyncDiagnosticsLog.add(
                '[SYNC_TRACE] autoCloud:hostRealtime closed; reconnecting');
          }
          retrySeconds = 1;
        } catch (error) {
          SyncDiagnosticsLog.add(
              '[SYNC_TRACE] autoCloud:hostRealtime error=$error retry=${retrySeconds}s');
          if (!_disposed) {
            await Future<void>.delayed(Duration(seconds: retrySeconds));
            retrySeconds = (retrySeconds * 2).clamp(1, 30);
          }
        }
      }
    } finally {
      _hostRealtimeLoopRunning = false;
    }
  }

  Future<void> _signalLoop() async {
    if (_signalLoopRunning) return;
    _signalLoopRunning = true;
    try {
      await _runUnifiedRealtimeSignalLoop<CloudSyncSettings>(
        isDisposed: () => _disposed,
        loadSettings: CloudSyncSettings.load,
        isReady: _cloudReady,
        onFirstReady: _tick,
        waitForSignal: (settings) async {
          final changed = await UnifiedSyncFactory.cloudEngine(
            store,
            settings: settings,
          ).waitForRealtimeSignal();
          return (
            changed: changed,
            debugLabel: changed
                ? '[SYNC_TRACE] autoCloud:realtimeWake transport=cloud'
                : null,
          );
        },
        onWake: _tick,
        onError: (error) {
          SyncDiagnosticsLog.add(
            '[SYNC_TRACE] autoCloud:realtimeFallback error=$error',
          );
        },
        postWakeDelay: const Duration(seconds: 2),
      );
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
              await UnifiedSyncFactory.cloudEngine(
                store,
                settings: settings,
              ).requestFreshHostSnapshotIfSupported(
                requestedAt: requestedAt,
              );
              settings = settings.copyWith(clearLastPullCursor: true);
            }
          }
        }

        final cursor = settings.lastPullCursor;
        final staleClient = store.appIdentity.isClient &&
            !hasAppliedCloudBaseline &&
            cursor != null &&
            now.difference(cursor.toUtc()) > const Duration(days: 7);
        await _recoverCloudSyncQueues(store);
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

/// Auto-sync loop for the Direct transport. It deliberately does not reuse
/// the Cloud loop: a Direct device must never wake or contact the Cloud sync
/// path just because it has Cloud credentials.
class UnifiedAutoDirectSyncController {
  UnifiedAutoDirectSyncController(this.store);

  final AppStore store;
  Timer? _timer;
  bool _running = false;
  bool _disposed = false;

  Future<void> start() async {
    stop();
    _disposed = false;
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _tick());
    await _tick();
  }

  void stop() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick() async {
    if (_disposed ||
        _running ||
        store.appIdentity.activeSyncTransportNormalized != 'direct') {
      return;
    }
    _running = true;
    try {
      await UnifiedSyncFactory.directEngine(store).syncNow();
    } finally {
      _running = false;
    }
  }
}
