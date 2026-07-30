import 'dart:convert';

import '../../data/app_store.dart';
import '../sync_unified/sync_contracts.dart';
import '../sync_unified/sync_device_state.dart';
import '../sync_unified/sync_transport_adapter.dart';
import '../sync_unified/unified_snapshot_lifecycle.dart';
import 'unified_sync_core_service.dart';
import 'direct_peer_protocol.dart';

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
    final changes =
        _core.filterOutLocalEchoes(_core.decodeRemoteChanges(rawChanges));
    if (_core.containsHostOnlyOperation(changes)) {
      throw StateError('Reset data can only be initiated on the Host device.');
    }
    final accepted = await _core.acceptClientChangesOnHost(
      changes,
      mirrorToCloud: false,
      verifyApplied: true,
    );
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
    final since = DateTime.tryParse(
      payload['since']?.toString() ?? payload['sinceAt']?.toString() ?? '',
    );
    if (sinceSequence <= 0 && since == null) {
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
    if (pending.isEmpty) {
      return const UnifiedSyncResult(
        ok: true,
        message: 'No Direct changes to push.',
      );
    }
    try {
      await _core.markPushInProgress(ids);
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
      return UnifiedSyncResultFactory.success(
        label: 'Direct',
        pushed: ackIds.length,
        pulled: 0,
        cursor: _cursor(),
        message: 'Direct push completed.',
      );
    } catch (error) {
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
      return rebuildFromHostSnapshot();
    }
    final changes = _core.normalizePulledChanges(
      response['changes'] as List<dynamic>? ?? const [],
    );
    await _core.applyAuthoritativeChanges(changes);
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
