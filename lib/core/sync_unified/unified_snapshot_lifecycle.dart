import 'dart:convert';

import '../../data/app_store.dart';

class UnifiedSnapshotApplyResult {
  const UnifiedSnapshotApplyResult({
    required this.cursor,
    required this.sequence,
    required this.transferredChunks,
    required this.verificationOk,
    required this.verificationMessage,
  });

  final DateTime cursor;
  final int sequence;
  final int transferredChunks;
  final bool verificationOk;
  final String verificationMessage;
}

class UnifiedSnapshotLifecycle {
  const UnifiedSnapshotLifecycle._();

  static Future<UnifiedSnapshotApplyResult> applyEnvelope({
    required AppStore store,
    required Map<String, dynamic> envelope,
    Future<void> Function(String snapshotJson)? beforeImport,
    Future<void> Function(String snapshotJson)? afterImport,
    bool verifyLocalData = false,
    bool cleanupSoftDeleted = false,
    bool markAllSyncChangesSynced = false,
  }) async {
    final snapshotJson = jsonEncode(envelope);

    await beforeImport?.call(snapshotJson);
    await store.sync.importSnapshotJson(snapshotJson);

    if (markAllSyncChangesSynced) {
      await store.sync.markAllChangesSynced();
    }
    if (cleanupSoftDeleted) {
      await store.sync.cleanupSoftDeletedRecords();
    }

    var verificationOk = true;
    var verificationMessage = '';
    if (verifyLocalData) {
      final verification = await store.sync.verifyLocalBusinessDataIntegrity();
      verificationOk = verification.ok;
      verificationMessage = verification.message;
    }

    await afterImport?.call(snapshotJson);

    return UnifiedSnapshotApplyResult(
      cursor: store.sync.snapshotGeneratedAtFromJson(snapshotJson),
      sequence: store.sync.snapshotGeneratedSequenceFromJson(snapshotJson),
      transferredChunks: (envelope['totalChunks'] as num?)?.toInt() ?? 0,
      verificationOk: verificationOk,
      verificationMessage: verificationMessage,
    );
  }
}
