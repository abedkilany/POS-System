part of 'app_store.dart';

extension _AppStoreSplitBackupRecoveryPart2 on AppStore {
  Future<List<Map<String, dynamic>>> exportDirectBootstrapSnapshotChunks({
    int maxItemsPerChunk = 250,
    int maxEncodedPayloadBytes = 900 * 1024,
  }) async {
    return await exportUnifiedSnapshotChunks(
      kind: 'full_store',
      maxItemsPerChunk: maxItemsPerChunk,
      maxEncodedPayloadBytes: maxEncodedPayloadBytes,
    );
  }

  String exportRecoveryFileJson({String controlPlaneApiUrl = ''}) {
    requirePermission(AppPermission.backupExport);
    final payload = <String, dynamic>{
      'format': 'ventio_store_recovery_file',
      'version': 2,
      'generatedAt': DateTime.now().toIso8601String(),
      'storeId': appIdentity.storeId,
      'branchId': appIdentity.branchId,
      'controlPlaneApiUrl': controlPlaneApiUrl.trim(),
      'recoveryKey': appIdentity.recoveryKey,
      'storeEpoch': appIdentity.storeEpoch,
    };
    payload['checksum'] = _recoveryChecksum(payload);
    payload['signature'] = _recoverySignature(payload);
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  Map<String, String> parseRecoveryFileJson(String rawJson) {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map) {
      throw ArgumentError('Invalid recovery file.');
    }
    final payload = Map<String, dynamic>.from(decoded);
    if (payload['format']?.toString() != 'ventio_store_recovery_file') {
      throw ArgumentError('Invalid recovery file format.');
    }
    final version = (payload['version'] as num? ?? 0).toInt();
    if (version < 1 || version > 2) {
      throw ArgumentError('Unsupported recovery file version.');
    }
    final expected = payload['checksum']?.toString() ?? '';
    if (expected.isEmpty || expected != _recoveryChecksum(payload)) {
      throw ArgumentError('Recovery file checksum failed.');
    }
    if (version >= 2) {
      final signature = payload['signature']?.toString() ?? '';
      if (signature.isEmpty || signature != _recoverySignature(payload)) {
        throw ArgumentError('Recovery file signature failed.');
      }
    }
    final storeId = payload['storeId']?.toString().trim().toUpperCase() ?? '';
    final branchId = payload['branchId']?.toString().trim().toUpperCase() ?? '';
    final recoveryKey =
        payload['recoveryKey']?.toString().trim().toUpperCase() ?? '';
    if (!storeId.startsWith('ST-') ||
        branchId.isEmpty ||
        !recoveryKey.startsWith('RK-')) {
      throw ArgumentError(
        'Recovery file is missing required store identity fields.',
      );
    }
    return {
      'storeId': storeId,
      'branchId': branchId,
      'controlPlaneApiUrl':
          payload['controlPlaneApiUrl']?.toString().trim() ?? '',
      'recoveryKey': recoveryKey,
    };
  }

  String _recoveryChecksum(Map<String, dynamic> payload) {
    final copy = Map<String, dynamic>.from(payload)
      ..remove('checksum')
      ..remove('signature');
    final canonical = jsonEncode(
      Map.fromEntries(
        copy.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
      ),
    );
    var hash = 2166136261;
    for (final unit in canonical.codeUnits) {
      hash ^= unit;
      hash = (hash * 16777619) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  Future<String> exportBackupJson() async {
    requirePermission(AppPermission.backupExport);
    final payload = await _backupPayload(includeDeviceAndSyncState: true);
    return compute(_encodePrettyBackupPayload, payload);
  }

  String currentHostSnapshotGeneration() {
    if (!appIdentity.isHost) return '';
    final stored =
        LocalDatabaseService.getString(AppStore._hostSnapshotGenerationKey);
    if (stored != null && stored.trim().isNotEmpty) return stored.trim();
    final markers = _syncChanges.where(
      (item) =>
          item.entityType == 'system' &&
          item.operation == 'restore_snapshot_ready',
    );
    if (markers.isEmpty) return '';
    final latest = markers.reduce(
      (a, b) => a.createdAt.isAfter(b.createdAt) ? a : b,
    );
    final payload = latest.payload;
    final generation = (payload['snapshotGeneration'] ??
            payload['restoreGeneration'] ??
            payload['restoredAt'] ??
            latest.createdAt.toIso8601String())
        .toString();
    return generation.trim();
  }

  String currentHostRestoreCommandId() {
    if (!appIdentity.isHost) return '';
    final stored =
        LocalDatabaseService.getString(AppStore._hostRestoreCommandIdKey);
    if (stored != null && stored.trim().isNotEmpty) return stored.trim();
    final markers = _syncChanges.where(
      (item) =>
          item.entityType == 'system' &&
          item.operation == 'restore_snapshot_ready',
    );
    if (markers.isEmpty) return '';
    final latest = markers.reduce(
      (a, b) => a.createdAt.isAfter(b.createdAt) ? a : b,
    );
    final payload = latest.payload;
    final commandId = (payload['commandId'] ??
            payload['restoreCommandId'] ??
            payload['rebuildCommandId'] ??
            payload['snapshotGeneration'] ??
            payload['restoreGeneration'] ??
            '')
        .toString();
    return commandId.trim();
  }

  Future<Map<String, dynamic>> exportUnifiedSnapshotEnvelope({
    String kind = 'full_store',
    int maxItemsPerChunk = 250,
    int maxEncodedPayloadBytes = 900 * 1024,
  }) async {
    final chunks = await exportUnifiedSnapshotChunks(
      kind: kind,
      maxItemsPerChunk: maxItemsPerChunk,
      maxEncodedPayloadBytes: maxEncodedPayloadBytes,
    );
    final manifest =
        chunks.isNotEmpty && chunks.first['snapshotManifest'] is Map
            ? Map<String, dynamic>.from(chunks.first['snapshotManifest'] as Map)
            : _unifiedSnapshotManifestJson(
                jobId: '',
                generatedAt: DateTime.now().toIso8601String(),
                kind: kind,
                totalChunks: chunks.length,
              );
    final generatedAt = chunks.isEmpty
        ? DateTime.now().toIso8601String()
        : (chunks.first['generatedAt'] ?? DateTime.now().toIso8601String())
            .toString();
    final generatedSequence = _syncChanges.isEmpty
        ? 0
        : _syncChanges
            .map((item) => item.sequence)
            .reduce((a, b) => a > b ? a : b);
    return <String, dynamic>{
      'snapshotFormat': UnifiedSnapshotManifest.format,
      'snapshotVersion': UnifiedSnapshotManifest.version,
      'snapshotKind': kind,
      'snapshotManifest': manifest,
      'snapshotChunks': chunks,
      'totalChunks': chunks.length,
      'syncGeneratedAt': generatedAt,
      'syncGeneratedSequence': generatedSequence,
      'snapshotGeneration': currentHostSnapshotGeneration(),
      'hostSnapshotGeneration': currentHostSnapshotGeneration(),
      'restoreCommandId': currentHostRestoreCommandId(),
      'hostRestoreCommandId': currentHostRestoreCommandId(),
    };
  }

  Future<String> exportSyncSnapshotJson() async {
    return const JsonEncoder.withIndent(
      '  ',
    ).convert(await exportUnifiedSnapshotEnvelope(kind: 'full_store'));
  }

  DateTime syncSnapshotGeneratedAtFromJson(String rawJson) {
    try {
      final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
      return DateTime.tryParse(decoded['syncGeneratedAt']?.toString() ?? '') ??
          DateTime.now();
    } catch (_) {
      return DateTime.now();
    }
  }

  int syncSnapshotGeneratedSequenceFromJson(String rawJson) {
    try {
      final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
      return int.tryParse(decoded['syncGeneratedSequence']?.toString() ?? '') ??
          0;
    } catch (_) {
      return 0;
    }
  }

  String exportSyncChangesJson({
    DateTime? since,
    int? sinceSequence,
    int? maxEncodedPayloadBytes,
  }) {
    final sequenceFloor = sinceSequence ?? 0;
    final earliestSequence = _earliestStoredAuthoritativeSequence();
    final latestSequence = _latestStoredAuthoritativeSequence();
    final hasHostRestoreMarker = _syncChanges.any(
      (item) =>
          item.entityType == 'system' &&
          item.operation == 'restore_snapshot_ready',
    );

    // If a client asks for an old sequence that has already been compacted,
    // incremental delivery cannot be trusted. The client must rebuild from a
    // full Host snapshot instead of silently accepting a partial event stream.
    //
    // Restore-specific guard: a manual Host backup restore can replace the
    // local sync log with a fresh, shorter log while existing Clients still
    // remember a higher lastAppliedSequence from the previous dataset. In that
    // case the normal `sequence > sinceSequence` query returns nothing, so the
    // Client never sees the restore marker. Treat `client sequence > latest
    // Host sequence` as a snapshot-required condition whenever a Host restore
    // marker is present.
    final needsSnapshot = sequenceFloor > 0 &&
        ((latestSequence > sequenceFloor &&
                earliestSequence > 0 &&
                sequenceFloor < earliestSequence - 1) ||
            (hasHostRestoreMarker &&
                latestSequence > 0 &&
                sequenceFloor > latestSequence));

    final allChanges = needsSnapshot
        ? <SyncChange>[]
        : (_syncChanges.where((item) {
            if (sequenceFloor > 0) return item.sequence > sequenceFloor;
            if (since != null) return !item.createdAt.isBefore(since);
            return true;
          }).toList()
          ..sort((a, b) => a.sequence.compareTo(b.sequence)));
    var changes = allChanges;
    var hasMoreChanges = false;
    final maxPayloadBytes = maxEncodedPayloadBytes ?? 0;
    if (!needsSnapshot && maxPayloadBytes > 0 && allChanges.isNotEmpty) {
      final limited = <SyncChange>[];
      var encodedBytes = utf8.encode('{"changes":[').length;
      for (final change in allChanges) {
        final changeBytes = utf8.encode(jsonEncode(change.toJson())).length;
        final separatorBytes = limited.isEmpty ? 0 : 1;
        if (limited.isNotEmpty &&
            encodedBytes + separatorBytes + changeBytes + 2 > maxPayloadBytes) {
          hasMoreChanges = true;
          break;
        }
        limited.add(change);
        encodedBytes += separatorBytes + changeBytes;
        if (encodedBytes + 2 > maxPayloadBytes) {
          hasMoreChanges = limited.length < allChanges.length;
          break;
        }
      }
      changes = limited;
    }
    final cursor = changes.isEmpty
        ? (since ?? DateTime.fromMillisecondsSinceEpoch(0))
        : changes
            .map((item) => item.createdAt)
            .reduce((a, b) => a.isAfter(b) ? a : b);
    final generatedSequence = needsSnapshot
        ? latestSequence
        : (changes.isEmpty
            ? sequenceFloor
            : changes
                .map((item) => item.sequence)
                .reduce((a, b) => a > b ? a : b));
    return jsonEncode({
      'ok': true,
      'deviceId': _deviceId,
      'generatedAt': cursor.toIso8601String(),
      'generatedSequence': generatedSequence,
      'earliestSequence': earliestSequence,
      'latestSequence': latestSequence,
      'requestedSinceSequence': sequenceFloor,
      'hostSnapshotGeneration': currentHostSnapshotGeneration(),
      'snapshotGeneration': currentHostSnapshotGeneration(),
      'restoreCommandId': currentHostRestoreCommandId(),
      'hostRestoreCommandId': currentHostRestoreCommandId(),
      'needsSnapshot': needsSnapshot,
      'hasMoreChanges': hasMoreChanges,
      'changes': changes.map((item) => item.toJson()).toList(),
    });
  }

  String _recoverySignature(Map<String, dynamic> payload) {
    final copy = Map<String, dynamic>.from(payload)
      ..remove('checksum')
      ..remove('signature');
    final canonical = jsonEncode(
      Map.fromEntries(
        copy.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
      ),
    );
    final storeSecret =
        "${copy['storeId'] ?? ''}|${copy['branchId'] ?? ''}|${copy['recoveryKey'] ?? ''}|${copy['storeEpoch'] ?? ''}";
    return Hmac(
      sha256,
      utf8.encode(storeSecret),
    ).convert(utf8.encode(canonical)).toString();
  }

  List<int> _deriveBackupKey(String password, String salt) {
    final derivator = pc.PBKDF2KeyDerivator(pc.HMac(pc.SHA256Digest(), 64));
    derivator.init(
      pc.Pbkdf2Parameters(Uint8List.fromList(utf8.encode(salt)), 200000, 32),
    );
    return derivator.process(
      Uint8List.fromList(utf8.encode('store_manager_pro|backup_v3|$password')),
    );
  }

  List<int> _deriveBackupKeyV2(String password, String salt) {
    List<int> digest = utf8.encode(
      'store_manager_pro|backup_v2|$salt|$password',
    );
    for (var i = 0; i < 100000; i++) {
      digest = sha256.convert(digest).bytes;
    }
    return digest;
  }

  String _generateNonce() {
    final random = Random.secure();
    final bytes = List<int>.generate(12, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  List<int> _aesGcmDecrypt(
    List<int> encrypted,
    List<int> key,
    List<int> nonce,
  ) {
    final cipher = pc.GCMBlockCipher(pc.AESEngine())
      ..init(
        false,
        pc.AEADParameters(
          pc.KeyParameter(Uint8List.fromList(key)),
          128,
          Uint8List.fromList(nonce),
          Uint8List(0),
        ),
      );
    return cipher.process(Uint8List.fromList(encrypted));
  }

  List<int> _deriveBackupKeyV1(String password, String salt) {
    List<int> digest = utf8.encode(
      'store_manager_pro|backup_v1|$salt|$password',
    );
    for (var i = 0; i < 25000; i++) {
      digest = sha256.convert(digest).bytes;
    }
    return digest;
  }

  List<int> _xorWithSha256Stream(List<int> input, List<int> key, String nonce) {
    final output = <int>[];
    var counter = 0;
    while (output.length < input.length) {
      final block = sha256.convert([
        ...key,
        ...utf8.encode(nonce),
        ...utf8.encode(counter.toString()),
      ]).bytes;
      for (final byte in block) {
        if (output.length >= input.length) break;
        output.add(input[output.length] ^ byte);
      }
      counter += 1;
    }
    return output;
  }

  bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
