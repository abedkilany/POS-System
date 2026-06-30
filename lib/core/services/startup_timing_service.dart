import 'dart:async';
import 'dart:convert';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'startup_timing_service_stub.dart'
    if (dart.library.io) 'startup_timing_service_io.dart' as impl;

class StartupTimingRecord {
  const StartupTimingRecord({
    required this.label,
    required this.category,
    required this.startedAtMs,
    required this.endedAtMs,
    required this.failed,
    required this.details,
  });

  final String label;
  final String category;
  final int startedAtMs;
  final int endedAtMs;
  final bool failed;
  final String details;

  int get durationMs => endedAtMs - startedAtMs;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'label': label,
        'category': category,
        'startedAtMs': startedAtMs,
        'endedAtMs': endedAtMs,
        'durationMs': durationMs,
        'failed': failed,
        'details': details,
      };
}

class PageTimingRecord {
  PageTimingRecord({
    required this.pageKey,
    required this.registeredAtMs,
    this.pageLabel = '',
  });

  final String pageKey;
  String pageLabel;
  final int registeredAtMs;
  int entryCount = 0;
  int? firstEnteredAtMs;
  int? firstBuiltAtMs;
  int? firstReadyAtMs;
  int? lastExitedAtMs;

  bool get wasEntered => entryCount > 0;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'pageKey': pageKey,
        'pageLabel': pageLabel,
        'registeredAtMs': registeredAtMs,
        'entryCount': entryCount,
        'firstEnteredAtMs': firstEnteredAtMs,
        'firstBuiltAtMs': firstBuiltAtMs,
        'firstReadyAtMs': firstReadyAtMs,
        'lastExitedAtMs': lastExitedAtMs,
      };
}

class StartupTimingService {
  StartupTimingService._();

  static final Stopwatch _watch = Stopwatch()..start();
  static final DateTime _sessionStartedAtUtc = DateTime.now().toUtc();
  static final List<StartupTimingRecord> _records = <StartupTimingRecord>[];
  static final Map<String, PageTimingRecord> _pageRecords =
      LinkedHashMap<String, PageTimingRecord>();

  static DateTime get sessionStartedAtUtc => _sessionStartedAtUtc;

  static int _nowMs() => _watch.elapsedMicroseconds ~/ 1000;

  static void registerPage({
    required String pageKey,
    required String pageLabel,
  }) {
    _pageRecords.putIfAbsent(
      pageKey,
      () => PageTimingRecord(
        pageKey: pageKey,
        pageLabel: pageLabel,
        registeredAtMs: _nowMs(),
      ),
    );
  }

  static void markPageEntered(
    String pageKey, {
    String pageLabel = '',
    String details = '',
  }) {
    final now = _nowMs();
    final record = _pageRecords.putIfAbsent(
      pageKey,
      () => PageTimingRecord(
        pageKey: pageKey,
        pageLabel: pageLabel.isEmpty ? pageKey : pageLabel,
        registeredAtMs: now,
      ),
    );
    record.entryCount += 1;
    record.pageLabel = pageLabel.isEmpty ? record.pageLabel : pageLabel;
    record.firstEnteredAtMs ??= now;
    debugPrint(
        '[PAGE][$pageKey] entered @ ${now}ms${details.isEmpty ? '' : ' - $details'}');
  }

  static void markPageBuilt(
    String pageKey, {
    String pageLabel = '',
    String details = '',
  }) {
    final now = _nowMs();
    final record = _pageRecords.putIfAbsent(
      pageKey,
      () => PageTimingRecord(
        pageKey: pageKey,
        pageLabel: pageLabel.isEmpty ? pageKey : pageLabel,
        registeredAtMs: now,
      ),
    );
    record.pageLabel = pageLabel.isEmpty ? record.pageLabel : pageLabel;
    record.firstBuiltAtMs ??= now;
    debugPrint(
        '[PAGE][$pageKey] first_build @ ${now}ms${details.isEmpty ? '' : ' - $details'}');
  }

  static void markPageReady(
    String pageKey, {
    String pageLabel = '',
    String details = '',
  }) {
    final now = _nowMs();
    final record = _pageRecords.putIfAbsent(
      pageKey,
      () => PageTimingRecord(
        pageKey: pageKey,
        pageLabel: pageLabel.isEmpty ? pageKey : pageLabel,
        registeredAtMs: now,
      ),
    );
    record.pageLabel = pageLabel.isEmpty ? record.pageLabel : pageLabel;
    record.firstReadyAtMs ??= now;
    debugPrint(
        '[PAGE][$pageKey] ready @ ${now}ms${details.isEmpty ? '' : ' - $details'}');
  }

  static void markPageExited(
    String pageKey, {
    String pageLabel = '',
    String details = '',
  }) {
    final now = _nowMs();
    final record = _pageRecords.putIfAbsent(
      pageKey,
      () => PageTimingRecord(
        pageKey: pageKey,
        pageLabel: pageLabel.isEmpty ? pageKey : pageLabel,
        registeredAtMs: now,
      ),
    );
    record.pageLabel = pageLabel.isEmpty ? record.pageLabel : pageLabel;
    record.lastExitedAtMs = now;
    debugPrint(
        '[PAGE][$pageKey] exited @ ${now}ms${details.isEmpty ? '' : ' - $details'}');
  }

  static void event(
    String label, {
    String category = 'startup',
    String details = '',
  }) {
    final now = _nowMs();
    _records.add(
      StartupTimingRecord(
        label: label,
        category: category,
        startedAtMs: now,
        endedAtMs: now,
        failed: false,
        details: details,
      ),
    );
    debugPrint(
        '[STARTUP][$category] $label @ ${now}ms${details.isEmpty ? '' : ' - $details'}');
  }

  static Future<T> measure<T>(
    String label,
    FutureOr<T> Function() action, {
    String category = 'startup',
    String details = '',
  }) async {
    final startedAt = _nowMs();
    debugPrint(
        '[STARTUP][$category] $label started @ ${startedAt}ms${details.isEmpty ? '' : ' - $details'}');
    try {
      final result = await Future<T>.sync(action);
      final endedAt = _nowMs();
      _records.add(
        StartupTimingRecord(
          label: label,
          category: category,
          startedAtMs: startedAt,
          endedAtMs: endedAt,
          failed: false,
          details: details,
        ),
      );
      debugPrint(
        '[STARTUP][$category] $label completed in ${endedAt - startedAt}ms${details.isEmpty ? '' : ' - $details'}',
      );
      return result;
    } catch (error, stackTrace) {
      final endedAt = _nowMs();
      _records.add(
        StartupTimingRecord(
          label: label,
          category: category,
          startedAtMs: startedAt,
          endedAtMs: endedAt,
          failed: true,
          details:
              details.isEmpty ? error.toString() : '$details | error=$error',
        ),
      );
      debugPrint(
        '[STARTUP][$category] $label failed after ${endedAt - startedAt}ms: $error\n$stackTrace',
      );
      rethrow;
    }
  }

  static List<StartupTimingRecord> snapshot() =>
      List<StartupTimingRecord>.unmodifiable(_records);

  static Map<String, dynamic> snapshotJson() => <String, dynamic>{
        'sessionStartedAtUtc': sessionStartedAtUtc.toIso8601String(),
        'totalElapsedMs': _nowMs(),
        'records':
            _records.map((item) => item.toJson()).toList(growable: false),
        'pageTimings':
            _pageRecords.values.map((item) => item.toJson()).toList(growable: false),
      };

  static String buildPageReport() {
    final buffer = StringBuffer()
      ..writeln('Page timing report')
      ..writeln('pageCount: ${_pageRecords.length}');

    var index = 0;
    for (final record in _pageRecords.values) {
      index += 1;
      if (!record.wasEntered) {
        buffer.writeln(
          '$index. ${record.pageKey} :: ${record.pageLabel} '
          'status=not_entered | لم يتم دخول الصفحة',
        );
        continue;
      }
      final enteredAt = record.firstEnteredAtMs ?? 0;
      final builtAt = record.firstBuiltAtMs;
      final readyAt = record.firstReadyAtMs;
      final exitedAt = record.lastExitedAtMs;
      final buildDelay = builtAt == null ? null : builtAt - enteredAt;
      final readyDelay = readyAt == null ? null : readyAt - enteredAt;
      final totalVisible = readyAt == null
          ? 'pending'
          : '${((exitedAt ?? _nowMs()) - readyAt).clamp(0, 1 << 31)}ms';
      buffer.writeln(
        '$index. ${record.pageKey} :: ${record.pageLabel} '
        'entries=${record.entryCount} '
        'entered=${enteredAt}ms '
        'firstBuild=${builtAt == null ? 'pending' : '${builtAt}ms'} '
        'ready=${readyAt == null ? 'pending' : '${readyAt}ms'} '
        'buildDelay=${buildDelay == null ? 'pending' : '${buildDelay}ms'} '
        'readyDelay=${readyDelay == null ? 'pending' : '${readyDelay}ms'} '
        'visibleAfterReady=$totalVisible '
        'status=ok',
      );
    }
    return buffer.toString();
  }

  static String buildTextReport() {
    final buffer = StringBuffer()
      ..writeln('Startup timing report')
      ..writeln('sessionStartedAtUtc: ${sessionStartedAtUtc.toIso8601String()}')
      ..writeln('totalElapsedMs: ${_nowMs()}')
      ..writeln('recordCount: ${_records.length}');

    var previousEnd = 0;
    for (var index = 0; index < _records.length; index += 1) {
      final record = _records[index];
      final delta = record.startedAtMs - previousEnd;
      buffer.writeln(
        '${index + 1}. ${record.category} :: ${record.label} '
        'start=${record.startedAtMs}ms '
        'end=${record.endedAtMs}ms '
        'duration=${record.durationMs}ms '
        'gap=${delta < 0 ? 0 : delta}ms '
        'status=${record.failed ? 'failed' : 'ok'}'
        '${record.details.isEmpty ? '' : ' | ${record.details}'}',
      );
      previousEnd = record.endedAtMs;
    }
    buffer.writeln();
    buffer.write(buildPageReport());
    return buffer.toString();
  }

  static Future<String?> saveTextReport() {
    return impl.saveTextReport(buildTextReport());
  }
}
