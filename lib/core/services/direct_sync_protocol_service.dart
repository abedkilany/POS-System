import 'dart:convert';

import '../../data/app_store.dart';
import '../../models/sync_change.dart';
import '../sync_unified/sync_contracts.dart';
import '../sync_unified/sync_device_state.dart';
import '../sync_unified/sync_transport_adapter.dart';
import '../sync_unified/unified_snapshot_lifecycle.dart';
import 'unified_sync_core_service.dart';
import 'direct_peer_protocol.dart';
import 'sync_diagnostics_log.dart';

class _DirectPullJob {
  _DirectPullJob({
    required this.id,
    required this.chunks,
    required this.generatedAt,
    required this.generatedSequence,
    required this.hasMoreChanges,
  });

  final String id;
  final List<List<dynamic>> chunks;
  final String generatedAt;
  final int generatedSequence;
  final bool hasMoreChanges;
}

/// Implements the Host-side Direct request protocol.
///
/// Only sync commands are handled here. The signaling server never sees these
/// frames because they are sent through the established data channel.
class DirectHostSyncEndpoint {
  static const int _maxChangePayloadBytes = 16 * 1024;
  static const int _maxPullChunkBytes = 8 * 1024;

  DirectHostSyncEndpoint(this.store) : _core = UnifiedSyncCoreService(store);

  final AppStore store;
  final UnifiedSyncCoreService _core;
  List<Map<String, dynamic>>? _snapshotChunks;
  final Map<String, _DirectPullJob> _pullJobs = <String, _DirectPullJob>{};

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
      case 'direct_client_pull_chunk':
        return _handlePullChunk(payload);
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
    final applyWatch = Stopwatch()..start();
    final accepted = await _core.acceptClientChangesOnHost(
      changes,
      mirrorToDirect: false,
      verifyApplied: true,
    );
    applyWatch.stop();
    SyncDiagnosticsLog.add(
        '[SYNC_TRACE] host push applied accepted=${accepted.ackIds.length} rejected=${accepted.rejected.length} applyMs=${applyWatch.elapsedMilliseconds} hostSequence=${store.latestStoredAuthoritativeSequence}');
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
    final exportWatch = Stopwatch()..start();
    final decoded = jsonDecode(
      store.exportSyncChangesJson(
        since: since,
        sinceSequence: sinceSequence,
        maxEncodedPayloadBytes: _maxChangePayloadBytes,
      ),
    ) as Map<String, dynamic>;
    exportWatch.stop();
    final changes = decoded['changes'] as List<dynamic>? ?? const <dynamic>[];
    final chunks = _splitPullChunks(changes);
    final pullId =
        'pull-${DateTime.now().microsecondsSinceEpoch}-${_pullJobs.length}';
    final job = _DirectPullJob(
      id: pullId,
      chunks: chunks,
      generatedAt: decoded['generatedAt']?.toString() ?? '',
      generatedSequence:
          int.tryParse(decoded['generatedSequence']?.toString() ?? '') ?? 0,
      hasMoreChanges: decoded['hasMoreChanges'] == true,
    );
    if (chunks.length > 1) {
      _pullJobs[pullId] = job;
      while (_pullJobs.length > 64) {
        _pullJobs.remove(_pullJobs.keys.first);
      }
    }
    SyncDiagnosticsLog.add(
        '[SYNC_TRACE] host pull response changes=${changes.length} chunks=${chunks.length} exportMs=${exportWatch.elapsedMilliseconds} generatedSequence=${decoded['generatedSequence'] ?? 0} hasMore=${decoded['hasMoreChanges'] == true}');
    return {
      'pullChunked': true,
      'pullId': pullId,
      'chunkIndex': 0,
      'totalChunks': chunks.length,
      'changes': chunks.first,
      'generatedAt': job.generatedAt,
      'generatedSequence': job.generatedSequence,
      'hasMoreChanges': job.hasMoreChanges,
      'needsSnapshot': false,
    };
  }

  Future<Map<String, dynamic>> _handlePullChunk(
    Map<String, dynamic> payload,
  ) async {
    final pullId = payload['pullId']?.toString().trim() ?? '';
    final index = int.tryParse(payload['chunkIndex']?.toString() ?? '') ?? -1;
    final job = _pullJobs[pullId];
    if (job == null) {
      throw StateError('Direct pull job is no longer available.');
    }
    if (index < 0 || index >= job.chunks.length) {
      throw StateError('Invalid Direct pull chunk index: $index.');
    }
    if (index == job.chunks.length - 1) {
      _pullJobs.remove(pullId);
    }
    return {
      'pullChunked': true,
      'pullId': pullId,
      'chunkIndex': index,
      'totalChunks': job.chunks.length,
      'changes': job.chunks[index],
    };
  }

  List<List<dynamic>> _splitPullChunks(List<dynamic> changes) {
    final chunks = <List<dynamic>>[];
    var chunk = <dynamic>[];
    var encodedBytes = utf8.encode('{"changes":[').length;
    for (final change in changes) {
      final changeBytes = utf8.encode(jsonEncode(change)).length;
      final separatorBytes = chunk.isEmpty ? 0 : 1;
      if (chunk.isNotEmpty &&
          encodedBytes + separatorBytes + changeBytes + 2 >
              _maxPullChunkBytes) {
        chunks.add(chunk);
        chunk = <dynamic>[];
        encodedBytes = utf8.encode('{"changes":[').length;
      }
      chunk.add(change);
      encodedBytes += (chunk.length == 1 ? 0 : 1) + changeBytes;
    }
    if (chunk.isNotEmpty || chunks.isEmpty) chunks.add(chunk);
    return chunks;
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
      final stateWatch = Stopwatch()..start();
      await SyncDeviceStateStore.recordPeerSyncResult(
        deviceId: deviceId,
        transport: 'direct',
        appliedSequence: appliedSequence,
        ackSequence: ackSequence,
        appliedCursor: appliedCursor,
        ackCursor: ackCursor,
      );
      await store.settleHostQueueThroughPeerAck();
      await store.compactSyncedSyncHistoryForMaintenance();
      stateWatch.stop();
      SyncDiagnosticsLog.add(
          '[SYNC_TRACE] host ack persisted device=$deviceId sequence=$ackSequence persistMs=${stateWatch.elapsedMilliseconds}');
    }
    return {
      'appliedSequence': appliedSequence,
      'ackSequence': ackSequence,
    };
  }
}

class DirectClientSyncService {
  static const int _maxChangePayloadBytes = 16 * 1024;

  DirectClientSyncService(this.store, this.session)
      : _core = UnifiedSyncCoreService(store);

  final AppStore store;
  final DirectPeerRequestSession session;
  final UnifiedSyncCoreService _core;

  Future<UnifiedSyncResult> pushPending() async {
    final pending = _core.pendingChangesForTarget(UnifiedSyncQueueTarget.host);
    final batches = _splitIntoBatches(pending);
    final ids = _core.changeIds(pending);
    SyncDiagnosticsLog.add(
        '[SYNC_TRACE] client push prepare count=${pending.length} ids=${ids.take(20).join(',')}');
    if (pending.isEmpty) {
      return const UnifiedSyncResult(
        ok: true,
        message: 'No Direct changes to push.',
      );
    }
    var pushed = 0;
    var rejectedCount = 0;
    try {
      for (var index = 0; index < batches.length; index++) {
        final batch = batches[index];
        final batchIds = _core.changeIds(batch);
        try {
          await _core.markPushInProgress(batchIds);
          SyncDiagnosticsLog.add(
              '[SYNC_TRACE] client push batch=${index + 1}/${batches.length} count=${batch.length}');
          final response = await session.sendRequest('direct_client_push', {
            'deviceId': store.deviceId,
            'deviceName': store.appIdentity.deviceName,
            'sequence': SyncDeviceStateStore.lastAppliedSequenceForTransport(
              store.appIdentity,
              'direct',
            ),
            'changes': batch.map((item) => item.toJson()).toList(),
          });
          if (response['ok'] != true) {
            throw StateError(
                response['error']?.toString() ?? 'Direct push failed.');
          }
          final ackIds = (response['ackIds'] as List<dynamic>? ?? const [])
              .map((item) => item.toString())
              .toList();
          final rejected = <String, String>{};
          for (final item
              in response['rejected'] as List<dynamic>? ?? const []) {
            if (item is Map && item['id'] != null) {
              rejected[item['id'].toString()] =
                  item['reason']?.toString() ?? 'Rejected by Host.';
            }
          }
          if (rejected.isNotEmpty) {
            await _core.markPushRejected(rejected);
          }
          await _core.markPushAcknowledged(ackIds, fallbackIds: batchIds);
          pushed += ackIds.length;
          rejectedCount += rejected.length;
        } catch (error) {
          await _core.markPushFailed(batchIds, error.toString());
          rethrow;
        }
      }
      return UnifiedSyncResultFactory.success(
        label: 'Direct',
        pushed: pushed,
        pulled: 0,
        cursor: _cursor(),
        message:
            'Direct push completed in ${batches.length} batch(es); rejected=$rejectedCount.',
      );
    } catch (error) {
      SyncDiagnosticsLog.add('[SYNC_TRACE] client push failed error=$error');
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
    var currentSequence = state.lastAppliedSequence;
    var currentCursor = state.lastAppliedHostCursor;
    var totalPulled = 0;
    var batches = 0;
    while (true) {
      final response = await session.sendRequest('direct_client_pull', {
        'deviceId': store.deviceId,
        'since': currentCursor?.toIso8601String(),
        'sinceSequence': currentSequence,
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
        SyncDiagnosticsLog.add(
            '[SYNC_TRACE] client pull requiresSnapshot=true');
        return rebuildFromHostSnapshot();
      }
      final pullResponse = await _collectPullChunks(response);
      batches++;
      final previousSequence = currentSequence;
      final changes = _core.normalizePulledChanges(
        pullResponse['changes'] as List<dynamic>? ?? const [],
      );
      SyncDiagnosticsLog.add(
          '[SYNC_TRACE] client pull batch=$batches received count=${changes.length}');
      final applyWatch = Stopwatch()..start();
      await _core.applyAuthoritativeChanges(changes);
      applyWatch.stop();
      final generatedAt = DateTime.tryParse(
            pullResponse['generatedAt']?.toString() ?? '',
          ) ??
          DateTime.now().toUtc();
      final generatedSequence = int.tryParse(
            pullResponse['generatedSequence']?.toString() ?? '',
          ) ??
          currentSequence;
      if (generatedSequence < previousSequence) {
        throw StateError('Direct pull sequence moved backwards.');
      }
      currentCursor = generatedAt;
      currentSequence = generatedSequence;
      totalPulled += changes.length;
      final stateWatch = Stopwatch()..start();
      await _core.recordTransportSyncState(
        store,
        transport: 'direct',
        cursor: generatedAt,
        sequence: generatedSequence,
      );
      stateWatch.stop();
      SyncDiagnosticsLog.add(
          '[SYNC_TRACE] client pull applied batch=$batches count=${changes.length} applyMs=${applyWatch.elapsedMilliseconds} stateMs=${stateWatch.elapsedMilliseconds} sequence=$generatedSequence');
      final ackWatch = Stopwatch()..start();
      await session.sendRequest('direct_client_ack', {
        'deviceId': store.deviceId,
        'appliedCursor': generatedAt.toIso8601String(),
        'ackCursor': generatedAt.toIso8601String(),
        'appliedSequence': generatedSequence,
        'ackSequence': generatedSequence,
      });
      ackWatch.stop();
      SyncDiagnosticsLog.add(
          '[SYNC_TRACE] client ack sent sequence=$generatedSequence batch=$batches requestMs=${ackWatch.elapsedMilliseconds}');
      if (pullResponse['hasMoreChanges'] != true) break;
      if (changes.isEmpty || generatedSequence <= previousSequence) {
        throw StateError(
            'Direct pull did not advance while more changes exist.');
      }
    }
    return UnifiedSyncResultFactory.success(
      label: 'Direct',
      pushed: 0,
      pulled: totalPulled,
      cursor: UnifiedCursorEnvelope(
        value: currentCursor.toIso8601String(),
        generatedAt: currentCursor,
        source: 'device',
      ),
      message: 'Direct pull completed in $batches batch(es).',
    );
  }

  Future<Map<String, dynamic>> _collectPullChunks(
    Map<String, dynamic> response,
  ) async {
    if (response['pullChunked'] != true) return response;
    final pullId = response['pullId']?.toString().trim() ?? '';
    final totalChunks =
        int.tryParse(response['totalChunks']?.toString() ?? '') ?? 1;
    if (pullId.isEmpty || totalChunks < 1) {
      throw StateError('Invalid Direct pull chunk manifest.');
    }
    final changes = <dynamic>[
      ...(response['changes'] as List<dynamic>? ?? const <dynamic>[]),
    ];
    for (var index = 1; index < totalChunks; index++) {
      final chunk = await session.sendRequest('direct_client_pull_chunk', {
        'deviceId': store.deviceId,
        'pullId': pullId,
        'chunkIndex': index,
      });
      if (chunk['ok'] != true || chunk['pullId']?.toString() != pullId) {
        throw StateError(
            chunk['error']?.toString() ?? 'Direct pull chunk failed.');
      }
      final returnedIndex =
          int.tryParse(chunk['chunkIndex']?.toString() ?? '') ?? -1;
      if (returnedIndex != index) {
        throw StateError('Direct pull chunks arrived out of order.');
      }
      changes.addAll(chunk['changes'] as List<dynamic>? ?? const <dynamic>[]);
    }
    return <String, dynamic>{...response, 'changes': changes};
  }

  List<List<SyncChange>> _splitIntoBatches(List<SyncChange> changes) {
    final batches = <List<SyncChange>>[];
    var batch = <SyncChange>[];
    var encodedBytes = utf8.encode('{"changes":[').length;
    for (final change in changes) {
      final changeBytes = utf8.encode(jsonEncode(change.toJson())).length;
      final separatorBytes = batch.isEmpty ? 0 : 1;
      if (batch.isNotEmpty &&
          encodedBytes + separatorBytes + changeBytes + 2 >
              _maxChangePayloadBytes) {
        batches.add(batch);
        batch = <SyncChange>[];
        encodedBytes = utf8.encode('{"changes":[').length;
      }
      batch.add(change);
      encodedBytes += (batch.length == 1 ? 0 : 1) + changeBytes;
      if (encodedBytes + 2 > _maxChangePayloadBytes && batch.length == 1) {
        throw StateError(
            'A single Direct change exceeds the maximum message size.');
      }
    }
    if (batch.isNotEmpty) batches.add(batch);
    return batches;
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
