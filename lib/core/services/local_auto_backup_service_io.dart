import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/app_store.dart';
import 'local_database_service.dart';

class LocalAutoBackupSettings {
  const LocalAutoBackupSettings({
    required this.enabled,
    required this.locationPath,
    required this.dailyCount,
    required this.weeklyCount,
    required this.monthlyCount,
  });

  final bool enabled;
  final String locationPath;
  final int dailyCount;
  final int weeklyCount;
  final int monthlyCount;

  LocalAutoBackupSettings copyWith({
    bool? enabled,
    String? locationPath,
    int? dailyCount,
    int? weeklyCount,
    int? monthlyCount,
  }) {
    return LocalAutoBackupSettings(
      enabled: enabled ?? this.enabled,
      locationPath: locationPath ?? this.locationPath,
      dailyCount: dailyCount ?? this.dailyCount,
      weeklyCount: weeklyCount ?? this.weeklyCount,
      monthlyCount: monthlyCount ?? this.monthlyCount,
    );
  }
}

class LocalAutoBackupStatus {
  const LocalAutoBackupStatus({
    this.isRunning = false,
    this.lastSuccessAt,
    this.lastError = '',
    this.message = '',
  });

  final bool isRunning;
  final DateTime? lastSuccessAt;
  final String lastError;
  final String message;
}

class LocalAutoBackupService {
  LocalAutoBackupService._();

  static const String _enabledKey = 'local_auto_backup_enabled_v1';
  static const String _locationKey = 'local_auto_backup_location_v1';
  static const String _dailyCountKey = 'local_auto_backup_daily_count_v1';
  static const String _weeklyCountKey = 'local_auto_backup_weekly_count_v1';
  static const String _monthlyCountKey = 'local_auto_backup_monthly_count_v1';
  static const String _lastSuccessKey = 'local_auto_backup_last_success_v1';
  static const int defaultDailyCount = 7;
  static const int defaultWeeklyCount = 4;
  static const int defaultMonthlyCount = 3;

  static final ValueNotifier<LocalAutoBackupStatus> status =
      ValueNotifier<LocalAutoBackupStatus>(const LocalAutoBackupStatus());

  static bool _isRunning = false;

  static Future<LocalAutoBackupSettings> loadSettings() async {
    return LocalAutoBackupSettings(
      enabled: LocalDatabaseService.getString(_enabledKey) == 'true',
      locationPath: LocalDatabaseService.getString(_locationKey) ?? await defaultLocationPath(),
      dailyCount: _readPositiveInt(_dailyCountKey, defaultDailyCount),
      weeklyCount: _readPositiveInt(_weeklyCountKey, defaultWeeklyCount),
      monthlyCount: _readPositiveInt(_monthlyCountKey, defaultMonthlyCount),
    );
  }

  static Future<void> saveSettings(LocalAutoBackupSettings settings) async {
    await LocalDatabaseService.setString(_enabledKey, settings.enabled ? 'true' : 'false');
    await LocalDatabaseService.setString(_locationKey, settings.locationPath.trim());
    await LocalDatabaseService.setString(_dailyCountKey, settings.dailyCount.clamp(1, 365).toString());
    await LocalDatabaseService.setString(_weeklyCountKey, settings.weeklyCount.clamp(1, 52).toString());
    await LocalDatabaseService.setString(_monthlyCountKey, settings.monthlyCount.clamp(1, 24).toString());
  }

  static Future<String> defaultLocationPath() async {
    if (kIsWeb) return 'Ventio/Backup';
    if (Platform.isWindows) {
      final programData = Platform.environment['ProgramData'];
      if (programData != null && programData.trim().isNotEmpty) {
        return '${programData.trim()}\\Ventio\\Backup';
      }
      return r'C:\ProgramData\Ventio\Backup';
    }
    final support = await getApplicationSupportDirectory();
    return '${support.path}${Platform.pathSeparator}Backup';
  }

  static Future<void> runDueBackup(AppStore store) async {
    if (_isRunning || kIsWeb) return;
    if (store.appIdentity.isClient) return;
    final settings = await loadSettings();
    if (!settings.enabled) return;
    final now = DateTime.now();
    final scheduled = DateTime(now.year, now.month, now.day, 2);
    if (now.isBefore(scheduled) && await _hasDailyForDate(settings, now)) return;
    await createBackupNow(store, settings: settings, reason: 'auto');
  }

  static Future<File> createBackupNow(
    AppStore store, {
    LocalAutoBackupSettings? settings,
    String reason = 'manual',
  }) async {
    if (_isRunning) throw StateError('Backup is already running.');
    if (kIsWeb) throw UnsupportedError('Local automatic backup is not supported on Web.');
    if (store.appIdentity.isClient) throw StateError('Local backup is only available on the Host device.');

    _isRunning = true;
    status.value = const LocalAutoBackupStatus(isRunning: true, message: 'Creating local backup...');
    try {
      final resolved = settings ?? await loadSettings();
      final root = Directory(resolved.locationPath.trim().isEmpty
          ? await defaultLocationPath()
          : resolved.locationPath.trim());
      final dailyDir = Directory('${root.path}${Platform.pathSeparator}Daily');
      final weeklyDir = Directory('${root.path}${Platform.pathSeparator}Weekly');
      final monthlyDir = Directory('${root.path}${Platform.pathSeparator}Monthly');
      final manualDir = Directory('${root.path}${Platform.pathSeparator}Backup now');
      await dailyDir.create(recursive: true);
      await weeklyDir.create(recursive: true);
      await monthlyDir.create(recursive: true);
      await manualDir.create(recursive: true);

      final now = DateTime.now();
      status.value = const LocalAutoBackupStatus(isRunning: true, message: 'Compressing backup...');
      final bytes = _buildZipBytes(store.exportBackupJson(), now, reason);

      if (reason == 'manual') {
        final manualFile = File('${manualDir.path}${Platform.pathSeparator}ventio_manual_${_dateTimeStamp(now)}.vtb');
        await manualFile.writeAsBytes(bytes, flush: true);
        await LocalDatabaseService.setString(_lastSuccessKey, now.toIso8601String());
        status.value = LocalAutoBackupStatus(lastSuccessAt: now, message: 'Manual local backup completed.');
        return manualFile;
      }

      final dailyFile = File('${dailyDir.path}${Platform.pathSeparator}ventio_daily_${_dateStamp(now)}.vtb');
      if (!await dailyFile.exists()) {
        await dailyFile.writeAsBytes(bytes, flush: true);
      }

      final weekStamp = _weekStamp(now);
      final weeklyFile = File('${weeklyDir.path}${Platform.pathSeparator}ventio_weekly_$weekStamp.vtb');
      if (!await weeklyFile.exists()) {
        await dailyFile.copy(weeklyFile.path);
      }

      final monthStamp = '${now.year.toString().padLeft(4, '0')}_${now.month.toString().padLeft(2, '0')}';
      final monthlyFile = File('${monthlyDir.path}${Platform.pathSeparator}ventio_monthly_$monthStamp.vtb');
      if (!await monthlyFile.exists()) {
        await dailyFile.copy(monthlyFile.path);
      }

      await _trimBackups(dailyDir, resolved.dailyCount);
      await _trimBackups(weeklyDir, resolved.weeklyCount);
      await _trimBackups(monthlyDir, resolved.monthlyCount);

      await LocalDatabaseService.setString(_lastSuccessKey, now.toIso8601String());
      status.value = LocalAutoBackupStatus(lastSuccessAt: now, message: 'Local backup completed.');
      return dailyFile;
    } catch (error) {
      status.value = LocalAutoBackupStatus(lastError: error.toString(), message: 'Local backup failed.');
      rethrow;
    } finally {
      _isRunning = false;
      Timer(const Duration(seconds: 5), () {
        if (!status.value.isRunning) {
          status.value = LocalAutoBackupStatus(lastSuccessAt: status.value.lastSuccessAt);
        }
      });
    }
  }

  static List<int> _buildZipBytes(String backupJson, DateTime generatedAt, String reason) {
    final backupBytes = utf8.encode(backupJson);
    final manifest = jsonEncode(<String, Object?>{
      'app': 'Ventio',
      'type': 'local-auto-backup',
      'reason': reason,
      'generatedAt': generatedAt.toIso8601String(),
      'content': 'backup.json',
    });
    final manifestBytes = utf8.encode(manifest);
    final archive = Archive()
      ..addFile(ArchiveFile('backup.json', backupBytes.length, backupBytes))
      ..addFile(ArchiveFile('manifest.json', manifestBytes.length, manifestBytes));
    return ZipEncoder().encode(archive);
  }

  static int _readPositiveInt(String key, int fallback) {
    final value = int.tryParse(LocalDatabaseService.getString(key) ?? '');
    if (value == null || value <= 0) return fallback;
    return value;
  }

  static String _dateStamp(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}_${value.month.toString().padLeft(2, '0')}_${value.day.toString().padLeft(2, '0')}';

  static String _dateTimeStamp(DateTime value) =>
      '${_dateStamp(value)}_${value.hour.toString().padLeft(2, '0')}_${value.minute.toString().padLeft(2, '0')}_${value.second.toString().padLeft(2, '0')}';

  static String _weekStamp(DateTime value) {
    final week = _isoWeekNumber(value).toString().padLeft(2, '0');
    return '${value.year.toString().padLeft(4, '0')}_W$week';
  }

  static int _isoWeekNumber(DateTime date) {
    final dayOfYear = date.difference(DateTime(date.year)).inDays + 1;
    final woy = ((dayOfYear - date.weekday + 10) / 7).floor();
    if (woy < 1) return _isoWeekNumber(DateTime(date.year - 1, 12, 31));
    if (woy == 53 && DateTime(date.year, 12, 31).weekday < DateTime.thursday) return 1;
    return woy;
  }

  static Future<bool> _hasDailyForDate(LocalAutoBackupSettings settings, DateTime date) async {
    final dir = Directory('${settings.locationPath}${Platform.pathSeparator}Daily');
    if (!await dir.exists()) return false;
    final stamp = _dateStamp(date);
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is File && entity.path.contains(stamp)) return true;
    }
    return false;
  }

  static Future<void> _trimBackups(Directory dir, int keep) async {
    if (!await dir.exists()) return;
    final files = <File>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is File && entity.path.toLowerCase().endsWith('.vtb')) files.add(entity);
    }
    files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    final limit = keep.clamp(1, 1000).toInt();
    for (final file in files.skip(limit)) {
      try {
        await file.delete();
      } catch (_) {}
    }
  }
}
