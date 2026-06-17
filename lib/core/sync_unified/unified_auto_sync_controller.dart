
import 'dart:async';

import '../../data/app_store.dart';
import '../services/cloud_sync_service.dart';
import '../services/lan_sync_service.dart';
import 'cloud_sync_transport_adapter.dart';
import 'lan_sync_transport_adapter.dart';
import 'unified_sync_engine.dart';

typedef AutoSnapshotProgressPresenter = void Function(String transport, double value, String label);

class UnifiedSyncFactory {
  const UnifiedSyncFactory._();

  static UnifiedSyncEngine cloudEngine(AppStore store, {CloudSyncSettings? settings, bool enabled = true}) {
    final current = settings ?? CloudSyncSettings.load();
    return UnifiedSyncEngine(
      CloudSyncTransportAdapter(
        service: CloudSyncService(store),
        settings: current.copyWith(enabled: enabled),
      ),
    );
  }

  static UnifiedSyncEngine lanEngine(AppStore store, {LanSyncSettings? settings}) {
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
        : identity.isClient && identity.activeSyncTransportNormalized == 'cloud';
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
  int _lastPendingCount = 0;
  String _lastSettingsSignature = '';

  String _settingsSignature(LanSyncSettings settings) => [
        settings.setupComplete,
        settings.mode.name,
        settings.hostModeEnabled,
        settings.host.trim(),
        settings.port,
        settings.autoSyncEnabled,
        settings.secret.trim(),
      ].join('|');

  bool _lanAllowedForCurrentRole(LanSyncSettings settings) {
    final identity = store.appIdentity;
    if (identity.isHost) return settings.setupComplete && settings.isHost;
    if (identity.isClient) {
      return identity.activeSyncTransportNormalized == 'lan' && settings.setupComplete && settings.isClient;
    }
    return false;
  }

  Future<void> start() async {
    _disposed = false;
    final settings = LanSyncSettings.load();
    _lastSettingsSignature = _settingsSignature(settings);
    _lastPendingCount = store.pendingSyncCount;

    if (!_lanAllowedForCurrentRole(settings)) {
      await UnifiedSyncFactory.lanEngine(store, settings: settings).transportStopHostIfSupported();
      store.removeListener(_onStoreChanged);
      _periodicTimer?.cancel();
      _debounceTimer?.cancel();
      return;
    }

    if (store.appIdentity.isHost && settings.isHost) {
      await UnifiedSyncFactory.lanEngine(store, settings: settings).registerCurrentHost(transportName: 'lan');
    }

    store.removeListener(_onStoreChanged);
    store.addListener(_onStoreChanged);
    _periodicTimer?.cancel();
    final interval = Duration(seconds: LanSyncSettings.defaultIntervalSeconds);
    _periodicTimer = Timer.periodic(interval, (_) => _syncBecauseOfTimer());

    if (store.appIdentity.isClient && settings.autoSyncEnabled && settings.isClient) {
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

  void _onStoreChanged() {
    if (_disposed) return;
    final settings = LanSyncSettings.load();
    final signature = _settingsSignature(settings);
    if (signature != _lastSettingsSignature) {
      _lastSettingsSignature = signature;
      unawaited(_applySettingsChange(settings));
    }

    final pending = store.pendingSyncCount;
    final pendingIncreased = pending > _lastPendingCount;
    _lastPendingCount = pending;
    if (!_lanAllowedForCurrentRole(settings) || !settings.autoSyncEnabled || !settings.isClient || !pendingIncreased) return;

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 3), () => _runClientSync());
  }

  void _syncBecauseOfTimer() {
    final settings = LanSyncSettings.load();
    final signature = _settingsSignature(settings);
    if (signature != _lastSettingsSignature) {
      _lastSettingsSignature = signature;
      unawaited(_applySettingsChange(settings));
    }
    if (!_lanAllowedForCurrentRole(settings)) {
      unawaited(UnifiedSyncFactory.lanEngine(store, settings: settings).transportStopHostIfSupported());
      return;
    }
    if (store.appIdentity.isHost && settings.isHost) {
      unawaited(UnifiedSyncFactory.lanEngine(store, settings: settings).registerCurrentHost(transportName: 'lan'));
      return;
    }
    if (!settings.autoSyncEnabled) return;
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
    if (store.appIdentity.isClient && _lanAllowedForCurrentRole(settings) && settings.autoSyncEnabled && settings.isClient) {
      await store.retryFailedSyncQueue(target: 'host');
      await _runClientSync();
    }
  }

  void Function(double value, String label)? _snapshotOnlyProgress(String transport) {
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
    if (!_lanAllowedForCurrentRole(settings) || !settings.autoSyncEnabled || !settings.isClient || settings.host.trim().isEmpty) return;

    _running = true;
    try {
      await store.retryFailedSyncQueue(target: 'host');
      final result = await UnifiedSyncFactory.lanEngine(store, settings: settings).syncNow(
        onProgress: _snapshotOnlyProgress('LAN'),
      );
      if (result.ok) {
        _lastPendingCount = store.pendingSyncCount;
      }
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
  int _lastCloudQueueCount = 0;
  int _lastRelayQueueCount = 0;

  Future<void> start() async {
    stop();
    _disposed = false;
    if (!_cloudAllowedForCurrentRole()) return;
    final settings = CloudSyncSettings.load();
    if (!settings.autoSyncEnabled || !settings.isConfigured) return;

    _lastCloudQueueCount = store.pendingSyncQueueForTarget('cloud', readyOnly: false).length;
    _lastRelayQueueCount = store.pendingSyncQueueForTarget('cloud_host', readyOnly: false).length;
    store.removeListener(_onStoreChanged);
    store.addListener(_onStoreChanged);

    final interval = Duration(seconds: CloudSyncSettings.defaultIntervalSeconds);
    _timer = Timer.periodic(interval, (_) => _tick());
    await _tick();
  }

  void stop() {
    _disposed = true;
    store.removeListener(_onStoreChanged);
    _timer?.cancel();
    _debounceTimer?.cancel();
    _timer = null;
    _debounceTimer = null;
  }

  void _onStoreChanged() {
    if (_disposed) return;
    final settings = CloudSyncSettings.load();
    if (!settings.autoSyncEnabled || !settings.isConfigured || !_cloudAllowedForCurrentRole()) return;

    final cloudCount = store.pendingSyncQueueForTarget('cloud', readyOnly: false).length;
    final relayCount = store.pendingSyncQueueForTarget('cloud_host', readyOnly: false).length;
    final hasNewCloudWork = cloudCount > _lastCloudQueueCount || relayCount > _lastRelayQueueCount;
    _lastCloudQueueCount = cloudCount;
    _lastRelayQueueCount = relayCount;
    if (!hasNewCloudWork) return;

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 3), () => _tick());
  }

  void Function(double value, String label)? _snapshotOnlyProgress(String transport) {
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
    if (_running || _disposed) return;
    _running = true;
    try {
      var settings = CloudSyncSettings.load();
      if (settings.autoSyncEnabled && settings.isConfigured && _cloudAllowedForCurrentRole()) {
        final hasOutgoingWork = store.pendingSyncQueueForTarget('cloud', readyOnly: false).isNotEmpty ||
            store.pendingSyncQueueForTarget('cloud_host', readyOnly: false).isNotEmpty;
        final now = DateTime.now().toUtc();
        final pendingProvisioning = store.appIdentity.isClient && CloudProvisioningStatus.isPending;
        if (pendingProvisioning) {
          final lastAttempt = CloudProvisioningStatus.lastAttemptAt;
          final shouldRequest = lastAttempt == null || now.difference(lastAttempt) > const Duration(minutes: 10);
          if (shouldRequest) {
            await CloudProvisioningStatus.markAttempted(now);
            final requestedAt = CloudProvisioningStatus.requestedAt ?? now;
            await CloudSyncService(store).requestFreshHostSnapshot(settings, requestedAt: requestedAt);
            settings = settings.copyWith(clearLastPullCursor: true);
          }
        }

        final cursor = settings.lastPullCursor;
        final staleClient = store.appIdentity.isClient &&
            cursor != null &&
            now.difference(cursor.toUtc()) > const Duration(days: 7);
        await store.recoverStaleInProgressSyncQueue(target: 'cloud');
        await store.recoverStaleInProgressSyncQueue(target: 'cloud_host');
        await store.retryFailedSyncQueue(target: 'cloud');
        await store.retryFailedSyncQueue(target: 'cloud_host');
        final engine = UnifiedSyncFactory.cloudEngine(store, settings: settings);
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
        await UnifiedSyncFactory.cloudEngine(store, settings: settings).syncNow(
          onProgress: _snapshotOnlyProgress('Cloud'),
        );
        _lastCloudQueueCount = store.pendingSyncQueueForTarget('cloud', readyOnly: false).length;
        _lastRelayQueueCount = store.pendingSyncQueueForTarget('cloud_host', readyOnly: false).length;
      }
    } finally {
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
