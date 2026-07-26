import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/snapshot/unified_snapshot_transfer.dart';

class _FakeSnapshotTransport implements UnifiedSnapshotChunkPullTransport {
  _FakeSnapshotTransport({required this.totalChunks, this.reportedTotalChunks});

  final int totalChunks;
  final int? reportedTotalChunks;
  int chunkCalls = 0;
  int ackCalls = 0;

  @override
  Future<UnifiedSnapshotManifestResponse> requestManifest(
      {bool force = false}) async {
    return UnifiedSnapshotManifestResponse(
      manifest: const <String, dynamic>{'collections': <String>['products']},
      totalChunks: totalChunks,
      snapshotFormat: 'unified_v1',
      snapshotVersion: 1,
    );
  }

  @override
  Future<UnifiedSnapshotChunkResponse> requestChunk(int ordinal) async {
    chunkCalls += 1;
    return UnifiedSnapshotChunkResponse(
      chunk: <String, dynamic>{'ordinal': ordinal},
      ordinal: ordinal,
      totalChunks: reportedTotalChunks ?? totalChunks,
    );
  }

  @override
  Future<void> ackChunk(int ordinal) async {
    ackCalls += 1;
  }
}

void main() {
  test('shared snapshot transfer validates and ACKs every chunk', () async {
    final transport = _FakeSnapshotTransport(totalChunks: 2);
    final envelope = await const UnifiedSnapshotTransferService()
        .downloadEnvelope(transport);

    expect(envelope['totalChunks'], 2);
    expect((envelope['snapshotChunks'] as List).length, 2);
    expect(transport.chunkCalls, 2);
    expect(transport.ackCalls, 2);
  });

  test('shared snapshot transfer rejects an empty manifest', () async {
    final transport = _FakeSnapshotTransport(totalChunks: 0);
    expect(
      () => const UnifiedSnapshotTransferService().downloadEnvelope(transport),
      throwsStateError,
    );
  });

  test('shared snapshot transfer rejects inconsistent chunk totals', () async {
    final transport = _FakeSnapshotTransport(
      totalChunks: 2,
      reportedTotalChunks: 3,
    );
    expect(
      () => const UnifiedSnapshotTransferService().downloadEnvelope(transport),
      throwsStateError,
    );
  });
}
