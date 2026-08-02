import 'dart:convert';

import '../../data/app_store.dart';
import '../sync_unified/sync_contracts.dart';
import '../sync_unified/sync_device_state.dart';
import '../sync_unified/sync_transport_adapter.dart';
import '../sync_unified/unified_snapshot_lifecycle.dart';
import 'unified_sync_core_service.dart';
import 'direct_peer_protocol.dart';
import 'sync_diagnostics_log.dart';

/// Implements the Host-side Direct request protocol.
///
/// Only sync commands are handled here. The signaling server never sees these
/// frames because they are sent through the established data channel.
class DirectHostSyncEndpoint {
  DirectHostSyncEndpoint(this.store) : _core = UnifiedSyncCoreService(store);

  final AppStore store;
  final UnifiedSyncCoreService _core;
  List<Map<String, dynamic>>? _snapshotChunks;

  Future<Map<String, dynamic>> handleRequest(
    String requestKind,
    Map<String, dynamic> payload,
  ) async {
    SyncDiagnosticsLog.add(
        '[SYNC_TRACE] host protocol dispatch kind=$requestKind requestId=${payload['requestId'] ?? '-'}');
    switch (requestKind) {
      case 'direct_client_push':
        return _handlePush(payload);
      case 'direct_client_pull':
        return _handlePull(payload);
      case 'direct_client_ack':
        return _handleAck(payload);
      case 'direct_client_snapshot_manifest':
        return _handleSnapshotManifest();
      case 'direct_client_snapshot_chunk':
        return _handleSnapshotChunk(payload);
      default:
        throw StateError('Unknown Direct request kind: $requestKind');
    }
  }

  Future<Map<String, dynamic>> _handleSnapshotManifest() async {
    _snapshotChunks ??= await store.exportUnifiedSnapshotChunks(
      kind: 'full_store',
      // WebRTC data channels are not a good place for very large messages.
      // Keep each response small enough for mobile and desktop peers alike.
      maxEncodedPayloadBytes: 12 * 1024,
    );
    final chunks = _snapshotChunks!;
    return {
      'totalChunks': chunks.length,
      'jobId': chunks.isEmpty ? '' : chunks.first['jobId'],
      'generatedAt': chunks.isEmpty ? '' : chunks.first['generatedAt'],
      'snapshotKind': 'full_store',
    };
  }

  Future<Map<String, dynamic>> _handleSnapshotChunk(
    Map<String, dynamic> payload,
  ) async {
    final index = int.tryParse(payload['index']?.toString() ?? '') ?? -1;
    final chunks = _snapshotChunks;
    if (chunks == null) {
      throw StateError('Direct snapshot manifest must be requested first.');
    }
    if (index < 0 || index >= chunks.length) {
      throw StateError('Invalid Direct snapshot chunk index: $index.');
    }
    return {
      'chunk': chunks[index],
      'index': index,
      'totalChunks': chunks.length
    };
  }

  Future<Map<String, dynamic>> _handlePush(Map<String, dynamic> payload) async {
    final rawChanges = payload['changes'] as List<dynamic>? ?? const [];
    SyncDiagnosticsLog.add(
        '[SYNC_TRACE] host push received count=${rawChanges.length} device=${payload['deviceId'] ?? '-'}');
    final changes =
        _core.filterOutLocalEchoes(_core.decodeRemoteChanges(rawChanges));
    if (_core.containsHostOnlyOperation(changes)) {
      throw StateError('Reset data can only be initiated on the Host device.');
    }
    final accepted = await _core.acceptClientChangesOnHost(
      changes,
      mirrorToDirect: false,
      verifyApplied: true,
    );
    SyncDiagnosticsLog.add(
        '[SYNC_TRACE] host push applied accepted=${accepted.ackIds.length} rejected=${accepted.rejected.length}');
    final deviceId = payload['deviceId']?.toString().trim() ?? '';
    final sequence = int.tryParse(
          payload['sequence']?.toString() ??
              payload['lastAppliedSequence']?.toString() ??
              '',
        ) ??
        0;
    if (deviceId.isNotEmpty) {
      await SyncDeviceStateStore.recordPeerSyncResult(
        deviceId: deviceId,
        transport: 'direct',
        ackSequence: sequence,
        appliedSequence: sequence,
      );
    }
    return {
      'ackIds': accepted.ackIds,
      'rejected': accepted.rejected.entries
          .map((entry) => {'id': entry.key, 'reason': entry.value})
          .toList(),
      'latestSequence': store.latestStoredAuthoritativeSequence,
    };
  }

  Future<Map<String, dynamic>> _handlePull(Map<String, dynamic> payload) async {
    final sinceSequence = int.tryParse(
          payload['sinceSequence']?.toString() ??
              payload['since_sequence']?.toString() ??
              '0',
        ) ??
        0;
    SyncDiagnosticsLog.add(
        '[SYNC_TRACE] host pull received device=${payload['deviceId'] ?? '-'} sinceSequence=$sinceSequence');
    final since = DateTime.tryParse(
      payload['since']?.toString() ?? payload['sinceAt']?.toString() ?? '',
    );
    if (sinceSequence <= 0 && since == null) {
      SyncDiagnosticsLog.add('[SYNC_TRACE] host pull requiresSnapshot=true');
      return {
        'needsSnapshot': true,
        'changes': const <dynamic>[],
        'generatedSequence': store.latestStoredAuthoritativeSequence,
      };
    }
    final decoded = jsonDecode(
      store.exportSyncChangesJson(
        since: since,
        sinceSequence: sinceSequence,
      ),
    ) as Map<String, dynamic>;
    SyncDiagnosticsLog.add(
        '[SYNC_TRACE] host pull response changes=${(decoded['changes'] as List?)?.length ?? 0} generatedSequence=${decoded['generatedSequence'] ?? 0}');
    return {
      ...decoded,
      'needsSnapshot': false,
    };
  }

  Future<Map<String, dynamic>> _handleAck(Map<String, dynamic> payload) async {
    final deviceId = payload['deviceId']?.toString().trim() ?? '';
    final appliedSequence = int.tryParse(
          payload['appliedSequence']?.toString() ??
              payload['applied_sequence']?.toString() ??
              '0',
        ) ??
        0;
    final ackSequence = int.tryParse(
          payload['ackSequence']?.toString() ??
              payload['ack_sequence']?.toString() ??
              '',
        ) ??
        appliedSequence;
    final appliedCursor = DateTime.tryParse(
      payload['appliedCursor']?.toString() ?? '',
    );
    final ackCursor = DateTime.tryParse(
      payload['ackCursor']?.toString() ?? '',
    );
    SyncDiagnosticsLog.add(
        '[SYNC_TRACE] host ack received device=$deviceId appliedSequence=$appliedSequence ackSequence=$ackSequence');
    if (deviceId.isNotEmpty) {
      await SyncDeviceStateStore.recordPeerSyncResult(
        deviceId: deviceId,
        transport: 'direct',
        appliedSequence: appliedSequence,
        ackSequence: ackSequence,
        appliedCursor: appliedCursor,
        ackCursor: ackCursor,
      );
    }
    return {
      'appliedSequence': appliedSequence,
      'ackSequence': ackSequence,
    };
  }
}

class DirectClientSyncService {
  DirectClientSyncService(this.store, this.session)
      : _core = UnifiedSyncCoreService(store);

  final AppStore store;
  final DirectPeerRequestSession session;
  final UnifiedSyncCoreService _core;

  Future<UnifiedSyncResult> pushPending() async {
    final pending = _core.pendingChangesForTarget(UnifiedSyncQueueTarget.host);
    final ids = _core.changeIds(pending);
    SyncDiagnosticsLog.add(
        '[SYNC_TRACE] client push prepare count=${pending.length} ids=${ids.take(20).join(',')}');
    if (pending.isEmpty) {
      return const UnifiedSyncResult(
        ok: true,
        message: 'No Direct changes to push.',
      );
    }
    try {
      await _core.markPushInProgress(ids);
      SyncDiagnosticsLog.add(
          '[SYNC_TRACE] client push markedInProgress count=${ids.length}');
      final response = await session.sendRequest('direct_client_push', {
        'deviceId': store.deviceId,
        'deviceName': store.appIdentity.deviceName,
        'sequence': SyncDeviceStateStore.lastAppliedSequenceForTransport(
          store.appIdentity,
          'direct',
        ),
        'changes': pending.map((item) => item.toJson()).toList(),
      });
      if (response['ok'] != true) {
        throw StateError(
            response['error']?.toString() ?? 'Direct push failed.');
      }
      final ackIds = (response['ackIds'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList();
      final rejected = <String, String>{};
      for (final item in response['rejected'] as List<dynamic>? ?? const []) {
        if (item is Map && item['id'] != null) {
          rejected[item['id'].toString()] =
              item['reason']?.toString() ?? 'Rejected by Host.';
        }
      }
      if (rejected.isNotEmpty) await _core.markPushRejected(rejected);
      await _core.markPushAcknowledged(ackIds, fallbackIds: ids);
      SyncDiagnosticsLog.add(
          '[SYNC_TRACE] client push finalized acknowledged=${ackIds.length} rejected=${rejected.length}');
      return UnifiedSyncResultFactory.success(
        label: 'Direct',
        pushed: ackIds.length,
        pulled: 0,
        cursor: _cursor(),
        message: 'Direct push completed.',
      );
    } catch (error) {
      SyncDiagnosticsLog.add('[SYNC_TRACE] client push failed error=$error');
      await _core.markPushFailed(ids, error.toString());
      return UnifiedSyncResult(
        ok: false,
        message: 'Direct push failed: $error',
        error: const UnifiedSyncError(
          code: UnifiedSyncErrorCode.networkUnavailable,
        ),
        cursor: _cursor(),
      );
    }
  }

  Future<UnifiedSyncResult> pullChanges() async {
    final state = SyncDeviceStateStore.load(store.appIdentity);
    SyncDiagnosticsLog.add(
        '[SYNC_TRACE] client pull prepare sinceSequence=${state.lastAppliedSequence} cursor=${state.lastAppliedHostCursor?.toIso8601String() ?? '-'}');
    final response = await session.sendRequest('direct_client_pull', {
      'deviceId': store.deviceId,
      'since': state.lastAppliedHostCursor?.toIso8601String(),
      'sinceSequence': state.lastAppliedSequence,
    });
    if (response['ok'] != true) {
      return UnifiedSyncResult(
        ok: false,
        message: response['error']?.toString() ?? 'Direct pull failed.',
        error: const UnifiedSyncError(
          code: UnifiedSyncErrorCode.networkUnavailable,
        ),
        cursor: _cursor(),
      );
    }
    if (response['needsSnapshot'] == true) {
      SyncDiagnosticsLog.add('[SYNC_TRACE] client pull requiresSnapshot=true');
      return rebuildFromHostSnapshot();
    }
    final changes = _core.normalizePulledChanges(
      response['changes'] as List<dynamic>? ?? const [],
    );
    SyncDiagnosticsLog.add(
        '[SYNC_TRACE] client pull received count=${changes.length}');
    await _core.applyAuthoritativeChanges(changes);
    SyncDiagnosticsLog.add(
        '[SYNC_TRACE] client pull applied count=${changes.length}');
    final generatedAt = DateTime.tryParse(
          response['generatedAt']?.toString() ?? '',
        ) ??
        DateTime.now().toUtc();
    final generatedSequence = int.tryParse(
          response['generatedSequence']?.toString() ?? '',
        ) ??
        0;
    await _core.recordTransportSyncState(
      store,
      transport: 'direct',
      cursor: generatedAt,
      sequence: generatedSequence,
    );
    await session.sendRequest('direct_client_ack', {
      'deviceId': store.deviceId,
      'appliedCursor': generatedAt.toIso8601String(),
      'ackCursor': generatedAt.toIso8601String(),
      'appliedSequence': generatedSequence,
      'ackSequence': generatedSequence,
    });
    SyncDiagnosticsLog.add(
        '[SYNC_TRACE] client ack sent sequence=$generatedSequence');
    return UnifiedSyncResultFactory.success(
      label: 'Direct',
      pushed: 0,
      pulled: changes.length,
      cursor: UnifiedCursorEnvelope(
        value: generatedAt.toIso8601String(),
        generatedAt: generatedAt,
        source: 'device',
      ),
      message: 'Direct pull completed.',
    );
  }

  Future<UnifiedSyncResult> rebuildFromHostSnapshot({
    void Function(double value, String label)? onProgress,
  }) async {
    try {
      SyncDiagnosticsLog.add('[SYNC_TRACE] client snapshot start');
      final manifest = await session.sendRequest(
        'direct_client_snapshot_manifest',
        {'deviceId': store.deviceId},
      );
      final total =
          int.tryParse(manifest['totalChunks']?.toString() ?? '') ?? 0;
      if (total <= 0) {
        throw StateError('Host returned an empty Direct snapshot.');
      }
      final chunks = <Map<String, dynamic>>[];
      for (var index = 0; index < total; index++) {
        final response = await session.sendRequest(
          'direct_client_snapshot_chunk',
          {'deviceId': store.deviceId, 'index': index},
        );
        final chunk = response['chunk'];
        if (chunk is! Map) throw StateError('Invalid Direct snapshot chunk.');
        chunks.add(Map<String, dynamic>.from(chunk));
        SyncDiagnosticsLog.add(
            '[SYNC_TRACE] client snapshot chunk index=$index total=$total');
        onProgress?.call((index + 1) / total, 'Receiving Direct snapshot');
      }
      final envelope = store.unifiedSnapshotPayloadFromChunks(chunks);
      final applied = await UnifiedSnapshotLifecycle.applyEnvelope(
        store: store,
        envelope: envelope,
        verifyLocalData: true,
      );
      if (!applied.verificationOk) {
        throw StateError(applied.verificationMessage);
      }
      await _core.recordTransportSyncState(
        store,
        transport: 'direct',
        cursor: applied.cursor,
        sequence: applied.sequence,
      );
      await session.sendRequest('direct_client_ack', {
        'deviceId': store.deviceId,
        'appliedCursor': applied.cursor.toIso8601String(),
        'ackCursor': applied.cursor.toIso8601String(),
        'appliedSequence': applied.sequence,
        'ackSequence': applied.sequence,
      });
      SyncDiagnosticsLog.add(
          '[SYNC_TRACE] client snapshot complete sequence=${applied.sequence}');
      return UnifiedSyncResultFactory.success(
        label: 'Direct',
        pushed: 0,
        pulled: 0,
        cursor: UnifiedCursorEnvelope(
          value: applied.cursor.toIso8601String(),
          generatedAt: applied.cursor,
          source: 'device',
        ),
        message: 'Direct initial snapshot completed.',
      );
    } catch (error) {
      SyncDiagnosticsLog.add(
          '[SYNC_TRACE] client snapshot failed error=$error');
      return UnifiedSyncResult(
        ok: false,
        message: 'Direct snapshot failed: $error',
        error: const UnifiedSyncError(
          code: UnifiedSyncErrorCode.snapshotUnavailable,
        ),
        cursor: _cursor(),
      );
    }
  }

  UnifiedCursorEnvelope _cursor() {
    final cursor = SyncDeviceStateStore.cursorForTransport(
      store.appIdentity,
      'direct',
      null,
    );
    return UnifiedCursorEnvelope(
      value: cursor?.toIso8601String() ?? '',
      generatedAt: cursor,
      source: 'device',
    );
  }
}
