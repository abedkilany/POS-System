import 'package:flutter/foundation.dart';

class SyncDiagnosticsLog {
  SyncDiagnosticsLog._();

  static const int _maxLines = 700;
  static final ValueNotifier<List<String>> lines =
      ValueNotifier<List<String>>(<String>[]);

  static void add(String message) {
    if (!kDebugMode) return;
    final timestamp = DateTime.now().toIso8601String();
    final line = '[$timestamp] $message';
    final next = <String>[...lines.value, line];
    if (next.length > _maxLines) {
      next.removeRange(0, next.length - _maxLines);
    }
    lines.value = List.unmodifiable(next);
  }

  static void clear() {
    lines.value = const <String>[];
  }

  static String dump() => lines.value.join('\n');

  static String summarizeChange(dynamic change) {
    try {
      final payload = change.payload is Map
          ? Map<String, dynamic>.from(change.payload as Map)
          : const <String, dynamic>{};
      final syncV2 = payload['_syncV2'] is Map
          ? Map<String, dynamic>.from(payload['_syncV2'] as Map)
          : const <String, dynamic>{};
      return 'id=${change.id} entity=${change.entityType} '
          'entityId=${change.entityId} op=${change.operation} '
          'seq=${change.sequence} device=${change.deviceId} '
          'name=${payload['name'] ?? payload['nameEn'] ?? ''} '
          'deletedAt=${payload['deletedAt'] ?? ''} '
          'syncKind=${syncV2['kind'] ?? ''} '
          'sourceRole=${syncV2['sourceRole'] ?? ''} '
          'sourceDevice=${syncV2['sourceDeviceId'] ?? ''} '
          'requestId=${syncV2['requestId'] ?? ''} '
          'eventId=${syncV2['eventId'] ?? ''}';
    } catch (error) {
      return 'changeSummaryError=$error change=$change';
    }
  }
}
