import 'dart:async';

/// Progress callback used by the unified snapshot transfer pipeline.
typedef UnifiedSnapshotTransferProgress = void Function(
    double value, String label);

/// A transport-neutral snapshot chunk response.
class UnifiedSnapshotChunkResponse {
  const UnifiedSnapshotChunkResponse({
    required this.chunk,
    required this.ordinal,
    required this.totalChunks,
  });

  final Map<String, dynamic> chunk;
  final int ordinal;
  final int totalChunks;
}

/// A transport-neutral snapshot manifest response.
class UnifiedSnapshotManifestResponse {
  const UnifiedSnapshotManifestResponse({
    required this.manifest,
    required this.totalChunks,
    this.snapshotFormat,
    this.snapshotVersion,
    this.snapshotKind,
    this.syncGeneratedAt,
    this.syncGeneratedSequence,
    this.hostSnapshotGeneration,
    this.snapshotGeneration,
    this.hostRestoreCommandId,
    this.restoreCommandId,
  });

  final Map<String, dynamic> manifest;
  final int totalChunks;
  final String? snapshotFormat;
  final Object? snapshotVersion;
  final String? snapshotKind;
  final String? syncGeneratedAt;
  final int? syncGeneratedSequence;
  final String? hostSnapshotGeneration;
  final String? snapshotGeneration;
  final String? hostRestoreCommandId;
  final String? restoreCommandId;
}

/// Transport adapter implemented by LAN and Cloud only for IO.
/// The transfer algorithm below is intentionally shared by both transports.
abstract class UnifiedSnapshotChunkPullTransport {
  Future<UnifiedSnapshotManifestResponse> requestManifest({bool force = false});
  Future<UnifiedSnapshotChunkResponse> requestChunk(int ordinal);
  Future<void> ackChunk(int ordinal) async {}
}

/// Shared downloader for Snapshot phase 2.
///
/// It is responsible for manifest -> chunk loop -> retry -> ack -> envelope.
/// LAN and Cloud only provide requestManifest/requestChunk implementations.
class UnifiedSnapshotTransferService {
  const UnifiedSnapshotTransferService({
    this.maxRetries = 3,
    this.retryDelay = const Duration(milliseconds: 350),
  });

  final int maxRetries;
  final Duration retryDelay;

  Future<Map<String, dynamic>> downloadEnvelope(
    UnifiedSnapshotChunkPullTransport transport, {
    bool force = false,
    int resumeFromOrdinal = 0,
    UnifiedSnapshotTransferProgress? onProgress,
    String labelPrefix = 'Snapshot',
  }) async {
    onProgress?.call(0.12, '$labelPrefix: requesting manifest...');
    final manifest = await transport.requestManifest(force: force);
    final totalChunks = manifest.totalChunks;
    final chunks = <Map<String, dynamic>>[];

    for (var ordinal = resumeFromOrdinal; ordinal < totalChunks; ordinal += 1) {
      final progress =
          (0.18 + (totalChunks == 0 ? 0 : (ordinal / totalChunks) * 0.52))
              .clamp(0.18, 0.70)
              .toDouble();
      onProgress?.call(progress,
          '$labelPrefix: downloading chunk ${ordinal + 1}/$totalChunks...');

      UnifiedSnapshotChunkResponse? response;
      Object? lastError;
      for (var attempt = 1; attempt <= maxRetries; attempt += 1) {
        try {
          response = await transport.requestChunk(ordinal);
          break;
        } catch (error) {
          lastError = error;
          if (attempt < maxRetries) {
            await Future<void>.delayed(retryDelay * attempt);
          }
        }
      }
      if (response == null) {
        throw StateError(
            '$labelPrefix chunk ${ordinal + 1}/$totalChunks failed after retry: $lastError');
      }
      if (response.ordinal != ordinal) {
        throw StateError(
            '$labelPrefix returned chunk ${response.ordinal}, expected $ordinal.');
      }
      chunks.add(response.chunk);
      await transport.ackChunk(ordinal);
    }

    onProgress?.call(0.74, '$labelPrefix: rebuilding local envelope...');
    return <String, dynamic>{
      'snapshotFormat': manifest.snapshotFormat,
      'snapshotVersion': manifest.snapshotVersion,
      'snapshotKind': manifest.snapshotKind,
      'snapshotManifest': manifest.manifest,
      'snapshotChunks': chunks,
      'totalChunks': totalChunks,
      'syncGeneratedAt': manifest.syncGeneratedAt,
      'syncGeneratedSequence': manifest.syncGeneratedSequence,
      'hostSnapshotGeneration':
          manifest.hostSnapshotGeneration ?? manifest.snapshotGeneration ?? '',
      'snapshotGeneration':
          manifest.snapshotGeneration ?? manifest.hostSnapshotGeneration ?? '',
      'hostRestoreCommandId':
          manifest.hostRestoreCommandId ?? manifest.restoreCommandId ?? '',
      'restoreCommandId':
          manifest.restoreCommandId ?? manifest.hostRestoreCommandId ?? '',
    };
  }
}

/// Transport adapter for uploading Host snapshot chunks.
abstract class UnifiedSnapshotChunkPushTransport {
  Future<void> uploadChunk(Map<String, dynamic> chunk,
      {required bool force, required bool preserveExisting});
}

extension UnifiedSnapshotTransferUploader on UnifiedSnapshotTransferService {
  Future<int> uploadChunks(
    UnifiedSnapshotChunkPushTransport transport,
    List<Map<String, dynamic>> chunks, {
    bool force = false,
    bool preserveExisting = false,
    UnifiedSnapshotTransferProgress? onProgress,
    String labelPrefix = 'Snapshot',
  }) async {
    for (var i = 0; i < chunks.length; i += 1) {
      final chunk = Map<String, dynamic>.from(chunks[i]);
      await transport.uploadChunk(
        chunk,
        force: force && i == 0,
        preserveExisting: preserveExisting,
      );
      onProgress?.call(
        (0.10 + ((i + 1) / chunks.length) * 0.70).clamp(0.10, 0.80).toDouble(),
        '$labelPrefix: uploading chunk ${i + 1}/${chunks.length}...',
      );
    }
    return chunks.length;
  }
}
