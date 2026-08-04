import 'package:flutter/foundation.dart';

class SyncDiagnosticsLog {
  SyncDiagnosticsLog._();

  // Stress Lab can generate several trace lines per request. Keep enough
  // history to reconstruct a run involving multiple Direct clients.
  static const int _maxLines = 5000;
  static final ValueNotifier<List<String>> lines =
      ValueNotifier<List<String>>(<String>[]);

  static void add(String message) {
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

  static void clearSyncTrace() {
    lines.value = List.unmodifiable(
      lines.value.where((line) => !line.contains('[SYNC_TRACE]')),
    );
  }

  static List<String> get syncTraceLines =>
      lines.value.where((line) => line.contains('[SYNC_TRACE]')).toList();

  static String dump() => lines.value.join('\n');

  static DirectDiagnosticsSummary directSummary() {
    var state = '';
    var iceState = '';
    var path = '';
    var restartAttempts = 0;
    for (final line in lines.value.reversed) {
      if (state.isEmpty) {
        final match = RegExp(r'\[DIRECT_WEBRTC\] (?:client|host) state=([^ ]+)')
            .firstMatch(line);
        if (match != null) state = match.group(1)!;
      }
      if (iceState.isEmpty) {
        final match =
            RegExp(r'\[DIRECT_WEBRTC\] (?:client|host) ice state=([^ ]+)')
                .firstMatch(line);
        if (match != null) iceState = match.group(1)!;
      }
      if (path.isEmpty && line.contains(' path state=')) {
        path = line.substring(line.indexOf(' path ') + 1);
      }
      final restart =
          RegExp(r'ice restart offer sent attempt=(\d+)').firstMatch(line);
      if (restart != null && restartAttempts == 0) {
        restartAttempts = int.tryParse(restart.group(1)!) ?? 0;
      }
    }
    return DirectDiagnosticsSummary(
      connectionState: state,
      iceState: iceState,
      path: path,
      restartAttempts: restartAttempts,
    );
  }

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

class DirectDiagnosticsSummary {
  const DirectDiagnosticsSummary({
    required this.connectionState,
    required this.iceState,
    required this.path,
    required this.restartAttempts,
  });

  final String connectionState;
  final String iceState;
  final String path;
  final int restartAttempts;

  bool get hasConnection =>
      connectionState.toLowerCase().contains('connected') ||
      iceState.toLowerCase().contains('completed');
}
