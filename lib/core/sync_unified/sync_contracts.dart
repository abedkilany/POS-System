import '../../models/app_identity.dart';

/// Fix 10B canonical sync contracts.
///
/// These contracts intentionally sit above the existing LAN and Cloud services.
/// They normalize the language used by both transports without forcing the
/// runtime migration that belongs to Fix 10C.
enum UnifiedSyncErrorCode {
  none,
  networkUnavailable,
  unauthorized,
  forbiddenRole,
  invalidPairingCode,
  expiredPairingCode,
  snapshotUnavailable,
  conflict,
  validationFailed,
  serverError,
  unsupported,
  unknown,
}

extension UnifiedSyncErrorCodeWire on UnifiedSyncErrorCode {
  String get wireName => name;

  static UnifiedSyncErrorCode fromWire(String? value) {
    final normalized = (value ?? '').trim();
    return UnifiedSyncErrorCode.values.firstWhere(
      (item) => item.name == normalized,
      orElse: () => UnifiedSyncErrorCode.unknown,
    );
  }
}

class UnifiedSyncError {
  const UnifiedSyncError({
    this.code = UnifiedSyncErrorCode.none,
    this.userMessage = '',
    this.debugMessage = '',
    this.httpStatus,
  });

  final UnifiedSyncErrorCode code;
  final String userMessage;
  final String debugMessage;
  final int? httpStatus;

  bool get hasError => code != UnifiedSyncErrorCode.none;

  Map<String, dynamic> toJson() => {
        'code': code.wireName,
        'userMessage': userMessage,
        if (debugMessage.trim().isNotEmpty) 'debugMessage': debugMessage,
        if (httpStatus != null) 'httpStatus': httpStatus,
      };

  factory UnifiedSyncError.fromJson(Map<String, dynamic> json) => UnifiedSyncError(
        code: UnifiedSyncErrorCodeWire.fromWire(json['code']?.toString()),
        userMessage: json['userMessage']?.toString() ?? '',
        debugMessage: json['debugMessage']?.toString() ?? '',
        httpStatus: json['httpStatus'] is int ? json['httpStatus'] as int : int.tryParse('${json['httpStatus']}'),
      );

  static const none = UnifiedSyncError();
}

class UnifiedSyncEnvelope<T> {
  const UnifiedSyncEnvelope({
    required this.ok,
    required this.message,
    this.payload,
    this.error = UnifiedSyncError.none,
    this.transport = '',
    this.contractVersion = 1,
  });

  final bool ok;
  final String message;
  final T? payload;
  final UnifiedSyncError error;
  final String transport;
  final int contractVersion;

  Map<String, dynamic> toJson(Object? Function(T value) encodePayload) => {
        'ok': ok,
        'message': message,
        'contractVersion': contractVersion,
        if (transport.trim().isNotEmpty) 'transport': transport,
        if (payload != null) 'payload': encodePayload(payload as T),
        if (error.hasError) 'error': error.toJson(),
      };
}

class UnifiedCursorEnvelope {
  const UnifiedCursorEnvelope({
    this.value = '',
    this.generatedAt,
    this.source = '',
  });

  final String value;
  final DateTime? generatedAt;
  final String source;

  bool get isEmpty => value.trim().isEmpty && generatedAt == null;

  Map<String, dynamic> toJson() => {
        'value': value,
        'generatedAt': generatedAt?.toIso8601String(),
        if (source.trim().isNotEmpty) 'source': source,
      };

  factory UnifiedCursorEnvelope.fromJson(Map<String, dynamic> json) => UnifiedCursorEnvelope(
        value: json['value']?.toString() ?? '',
        generatedAt: DateTime.tryParse(json['generatedAt']?.toString() ?? ''),
        source: json['source']?.toString() ?? '',
      );
}

class UnifiedPairingContract {
  const UnifiedPairingContract({
    required this.code,
    required this.expiresAt,
    required this.transport,
    this.storeId = '',
    this.branchId = '',
    this.hostDeviceId = '',
    this.host = '',
    this.port,
    this.apiBaseUrl = '',
  });

  final String code;
  final DateTime expiresAt;
  final String transport;
  final String storeId;
  final String branchId;
  final String hostDeviceId;
  final String host;
  final int? port;
  final String apiBaseUrl;

  Map<String, dynamic> toJson() => {
        'code': code,
        'expiresAt': expiresAt.toIso8601String(),
        'transport': transport,
        if (storeId.trim().isNotEmpty) 'storeId': storeId,
        if (branchId.trim().isNotEmpty) 'branchId': branchId,
        if (hostDeviceId.trim().isNotEmpty) 'hostDeviceId': hostDeviceId,
        if (host.trim().isNotEmpty) 'host': host,
        if (port != null) 'port': port,
        if (apiBaseUrl.trim().isNotEmpty) 'apiBaseUrl': apiBaseUrl,
      };

  factory UnifiedPairingContract.fromJson(Map<String, dynamic> json) => UnifiedPairingContract(
        code: json['code']?.toString() ?? '',
        expiresAt: DateTime.tryParse(json['expiresAt']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
        transport: json['transport']?.toString() ?? '',
        storeId: json['storeId']?.toString() ?? '',
        branchId: json['branchId']?.toString() ?? '',
        hostDeviceId: json['hostDeviceId']?.toString() ?? '',
        host: json['host']?.toString() ?? '',
        port: json['port'] is int ? json['port'] as int : int.tryParse('${json['port']}'),
        apiBaseUrl: json['apiBaseUrl']?.toString() ?? '',
      );
}

class UnifiedPairingClaimContract {
  const UnifiedPairingClaimContract({
    this.identity,
    this.storeId = '',
    this.branchId = '',
    this.hostDeviceId = '',
    this.deviceToken = '',
    this.snapshotAvailable = false,
  });

  final AppIdentity? identity;
  final String storeId;
  final String branchId;
  final String hostDeviceId;
  final String deviceToken;
  final bool snapshotAvailable;

  Map<String, dynamic> toJson() => {
        if (identity != null) 'identity': identity!.toJson(),
        if (storeId.trim().isNotEmpty) 'storeId': storeId,
        if (branchId.trim().isNotEmpty) 'branchId': branchId,
        if (hostDeviceId.trim().isNotEmpty) 'hostDeviceId': hostDeviceId,
        if (deviceToken.trim().isNotEmpty) 'deviceToken': deviceToken,
        'snapshotAvailable': snapshotAvailable,
      };
}

class UnifiedSnapshotContract {
  const UnifiedSnapshotContract({
    required this.snapshot,
    required this.generatedAt,
    required this.storeId,
    required this.branchId,
    required this.hostDeviceId,
    this.schemaVersion = 1,
  });

  final Map<String, dynamic> snapshot;
  final DateTime generatedAt;
  final String storeId;
  final String branchId;
  final String hostDeviceId;
  final int schemaVersion;

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'generatedAt': generatedAt.toIso8601String(),
        'storeId': storeId,
        'branchId': branchId,
        'hostDeviceId': hostDeviceId,
        'snapshot': snapshot,
      };

  factory UnifiedSnapshotContract.fromJson(Map<String, dynamic> json) => UnifiedSnapshotContract(
        snapshot: Map<String, dynamic>.from((json['snapshot'] as Map?) ?? const <String, dynamic>{}),
        generatedAt: DateTime.tryParse(json['generatedAt']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
        storeId: json['storeId']?.toString() ?? '',
        branchId: json['branchId']?.toString() ?? '',
        hostDeviceId: json['hostDeviceId']?.toString() ?? '',
        schemaVersion: json['schemaVersion'] is int ? json['schemaVersion'] as int : int.tryParse('${json['schemaVersion']}') ?? 1,
      );
}

enum UnifiedSyncCommandType { push, pull, rebuild, repair, heartbeat, hostTransfer }

class UnifiedSyncCommandContract {
  const UnifiedSyncCommandContract({
    required this.type,
    required this.deviceId,
    required this.deviceToken,
    this.cursor = const UnifiedCursorEnvelope(),
    this.payload = const <String, dynamic>{},
  });

  final UnifiedSyncCommandType type;
  final String deviceId;
  final String deviceToken;
  final UnifiedCursorEnvelope cursor;
  final Map<String, dynamic> payload;

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'deviceId': deviceId,
        'deviceToken': deviceToken,
        'cursor': cursor.toJson(),
        'payload': payload,
      };
}

class UnifiedSyncBatchContract {
  const UnifiedSyncBatchContract({
    this.cursor = const UnifiedCursorEnvelope(),
    this.changes = const <Map<String, dynamic>>[],
    this.pushed = 0,
    this.pulled = 0,
    this.restoredSnapshot = false,
  });

  final UnifiedCursorEnvelope cursor;
  final List<Map<String, dynamic>> changes;
  final int pushed;
  final int pulled;
  final bool restoredSnapshot;

  Map<String, dynamic> toJson() => {
        'cursor': cursor.toJson(),
        'changes': changes,
        'pushed': pushed,
        'pulled': pulled,
        'restoredSnapshot': restoredSnapshot,
      };
}
