import '../../data/app_store.dart';
import '../../models/app_identity.dart';
import 'sync_device_state.dart';
import 'unified_snapshot_lifecycle.dart';

class UnifiedPairingSnapshotSuccess {
  const UnifiedPairingSnapshotSuccess({
    required this.identity,
    required this.cursor,
    required this.sequence,
    required this.verificationOk,
    required this.verificationMessage,
  });

  final AppIdentity identity;
  final DateTime cursor;
  final int sequence;
  final bool verificationOk;
  final String verificationMessage;
}

class UnifiedPairingSnapshotFlow {
  const UnifiedPairingSnapshotFlow._();

  static Future<UnifiedPairingSnapshotSuccess> applyForCloud({
    required AppStore store,
    required Map<String, dynamic> envelope,
    required Future<void> Function() markSnapshotApplied,
    required Future<void> Function() markProvisioningComplete,
  }) async {
    final applied = await UnifiedSnapshotLifecycle.applyEnvelope(
      store: store,
      envelope: envelope,
      afterImport: (_) => markSnapshotApplied(),
      verifyLocalData: true,
    );
    if (store.needsInitialAdminSetup) {
      throw StateError(applied.verificationMessage);
    }
    await SyncDeviceStateStore.recordSyncResult(
      store.appIdentity,
      transport: 'cloud',
      appliedCursor: applied.cursor,
      ackCursor: applied.cursor,
      appliedSequence: applied.sequence,
      ackSequence: applied.sequence,
    );
    await markProvisioningComplete();
    // Pairing may be completed from Settings while the user is already
    // logged in. Saving the transport settings alone does not notify the
    // running auto-sync controller, so publish the new client state now.
    store.refreshUi();
    return UnifiedPairingSnapshotSuccess(
      identity: store.appIdentity,
      cursor: applied.cursor,
      sequence: applied.sequence,
      verificationOk: applied.verificationOk,
      verificationMessage: applied.verificationMessage,
    );
  }

  static Future<UnifiedPairingSnapshotSuccess> applyForLan({
    required AppStore store,
    required String host,
    required int port,
    required Map<String, dynamic> envelope,
    required Future<void> Function() markSnapshotApplied,
    required Future<void> Function(DateTime cursor) saveLanSettings,
    required Future<void> Function(DateTime cursor, int sequence)
        saveCursorAndState,
  }) async {
    final applied = await UnifiedSnapshotLifecycle.applyEnvelope(
      store: store,
      envelope: envelope,
      afterImport: (_) => markSnapshotApplied(),
    );
    await saveLanSettings(applied.cursor);
    await saveCursorAndState(applied.cursor, applied.sequence);
    // The LAN settings are persisted inside the pairing flow. Notify the
    // existing app/controller so it starts using the new Client transport
    // immediately instead of leaving subsequent changes pending locally.
    store.refreshUi();
    return UnifiedPairingSnapshotSuccess(
      identity: store.appIdentity,
      cursor: applied.cursor,
      sequence: applied.sequence,
      verificationOk: true,
      verificationMessage: '',
    );
  }
}
