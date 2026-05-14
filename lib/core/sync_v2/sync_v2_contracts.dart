/// Sync V2 shared terminology used by the app and API layer.
///
/// This file intentionally has no Flutter dependency so it can be reused by
/// tests and future LAN/Cloud transport adapters.
enum SyncV2CommandStatus { pending, accepted, rejected }

enum SyncV2Transport { lan, cloud }

class DraftCommand {
  const DraftCommand({
    required this.id,
    required this.type,
    required this.entityId,
    required this.payload,
    required this.clientMutationId,
    required this.deviceId,
    required this.createdAt,
    this.baseVersion = 0,
  });

  final String id;
  final String type;
  final String entityId;
  final Map<String, dynamic> payload;
  final String clientMutationId;
  final String deviceId;
  final DateTime createdAt;
  final int baseVersion;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'entityId': entityId,
        'payload': payload,
        'clientMutationId': clientMutationId,
        'deviceId': deviceId,
        'createdAt': createdAt.toIso8601String(),
        'baseVersion': baseVersion,
      };

  factory DraftCommand.fromJson(Map<String, dynamic> json) => DraftCommand(
        id: json['id']?.toString() ?? '',
        type: json['type']?.toString() ?? '',
        entityId: json['entityId']?.toString() ?? '',
        payload: Map<String, dynamic>.from(json['payload'] as Map? ?? const {}),
        clientMutationId: json['clientMutationId']?.toString() ?? '',
        deviceId: json['deviceId']?.toString() ?? '',
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
        baseVersion: (json['baseVersion'] as num?)?.toInt() ?? 0,
      );
}

class AuthoritativeEvent {
  const AuthoritativeEvent({
    required this.id,
    required this.type,
    required this.entityId,
    required this.payload,
    required this.hostDeviceId,
    required this.createdAt,
    required this.serverSequence,
    this.sourceCommandId = '',
  });

  final String id;
  final String type;
  final String entityId;
  final Map<String, dynamic> payload;
  final String hostDeviceId;
  final DateTime createdAt;
  final int serverSequence;
  final String sourceCommandId;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'entityId': entityId,
        'payload': payload,
        'hostDeviceId': hostDeviceId,
        'createdAt': createdAt.toIso8601String(),
        'serverSequence': serverSequence,
        'sourceCommandId': sourceCommandId,
      };
}
