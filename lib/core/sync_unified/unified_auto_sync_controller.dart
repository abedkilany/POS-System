import 'dart:async';

import 'package:http/http.dart' as http;

import '../../data/app_store.dart';
import '../services/direct_control_plane_service.dart';
import '../services/local_database_service.dart';
import '../services/lan_sync_service.dart';
import '../services/sync_diagnostics_log.dart';
import 'lan_sync_transport_adapter.dart';
import 'direct_sync_transport_adapter.dart';
import 'unified_sync_policy.dart';
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

class UnifiedSyncFactory {
  const UnifiedSyncFactory._();

  static final Map<AppStore, LanSyncService> _lanServices =
      <AppStore, LanSyncService>{};
  static final Map<AppStore, DirectSyncTransportAdapter> _directAdapters =
      <AppStore, DirectSyncTransportAdapter>{};

  static UnifiedSyncEngine lanEngine(AppStore store,
      {LanSyncSettings? settings}) {
    return UnifiedSyncEngine(
      LanSyncTransportAdapter(
        service: _lanServices.putIfAbsent(store, () => LanSyncService(store)),
        settings: settings ?? LanSyncSettings.load(),
      ),
    );
  }

  static UnifiedSyncEngine directEngine(
    AppStore store, {
    VpsControlPlaneSettings? settings,
    bool enabled = true,
    http.Client? client,
  }) {
    final adapter = _directAdapters.putIfAbsent(
      store,
      () => DirectSyncTransportAdapter(store),
    );
    return UnifiedSyncEngine(
      adapter,
    );
  }

  static Future<void> disposeDirect(AppStore store) async {
    final adapter = _directAdapters.remove(store);
    await adapter?.stopHostIfSupported();
  }

  static UnifiedSyncEngine activeEngine(
    AppStore store, {
    bool directEnabled = true,
    VpsControlPlaneSettings? directSettings,
    LanSyncSettings? lanSettings,
  }) {
    final identity = store.appIdentity;
    if (identity.activeSyncTransportNormalized == 'direct') {
      return directEngine(store);
    }
    return lanEngine(store, settings: lanSettings ?? LanSyncSettings.load());
  }

  static bool get isLanSetupComplete => LanSyncSettings.load().setupComplete;
  static bool get isLanHost => LanSyncSettings.load().isHost;
  static bool get isDirectConfigured => false;
  static bool directCanCheck(AppStore store) {
    return false;
  }

  static bool directFallbackCanCheck(AppStore store) {
    return false;
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

/// Auto-sync loop for the Direct transport. It deliberately does not reuse
/// the Direct loop: a Direct device must never wake or contact the Direct sync
/// path just because it has Direct credentials.
class UnifiedAutoDirectSyncController {
  UnifiedAutoDirectSyncController(this.store);

  final AppStore store;
  Timer? _timer;
  Timer? _localPushDebounce;
  bool _running = false;
  bool _disposed = false;
  bool _signalLoopRunning = false;

  Future<void> start() async {
    stop();
    _disposed = false;
    store.addListener(_onStoreChanged);
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _tick());
    unawaited(_signalLoop());
    await _tick();
  }

  void stop() {
    _disposed = true;
    store.removeListener(_onStoreChanged);
    _timer?.cancel();
    _timer = null;
    _localPushDebounce?.cancel();
    _localPushDebounce = null;
  }

  void _onStoreChanged() {
    if (_disposed ||
        store.appIdentity.activeSyncTransportNormalized != 'direct' ||
        !store.appIdentity.isClient) {
      return;
    }
    _localPushDebounce?.cancel();
    _localPushDebounce = Timer(const Duration(milliseconds: 250), _tick);
  }

  Future<void> _signalLoop() async {
    if (_signalLoopRunning) return;
    _signalLoopRunning = true;
    try {
      while (!_disposed) {
        if (store.appIdentity.activeSyncTransportNormalized != 'direct' ||
            store.appIdentity.isHost) {
          await Future<void>.delayed(const Duration(seconds: 5));
          continue;
        }
        final changed = await UnifiedSyncFactory.directEngine(store)
            .waitForRealtimeSignal();
        if (changed && !_disposed) {
          await _tick();
        } else if (!_disposed) {
          await Future<void>.delayed(const Duration(seconds: 2));
        }
      }
    } finally {
      _signalLoopRunning = false;
    }
  }

  Future<void> _tick() async {
    if (_disposed ||
        _running ||
        store.appIdentity.activeSyncTransportNormalized != 'direct') {
      return;
    }
    _running = true;
    try {
      final result = await UnifiedSyncFactory.directEngine(store).syncNow();
      SyncDiagnosticsLog.add(
          '[SYNC_TRACE] autoDirect:tick result ok=${result.ok} '
          'pushed=${result.pushed} pulled=${result.pulled} message=${result.message}');
    } catch (error) {
      // Direct failures remain Direct failures. Never fall back to the
      // retired Direct Sync transport; the user must explicitly choose LAN or
      // Direct and repair that selected transport.
      SyncDiagnosticsLog.add('[DIRECT] sync failed=$error');
    } finally {
      _running = false;
    }
  }
}
