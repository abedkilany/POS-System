import 'package:flutter/foundation.dart';

import '../../data/app_store.dart';

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

  static const int defaultDailyCount = 7;
  static const int defaultWeeklyCount = 4;
  static const int defaultMonthlyCount = 3;

  static final ValueNotifier<LocalAutoBackupStatus> status =
      ValueNotifier<LocalAutoBackupStatus>(const LocalAutoBackupStatus());

  static Future<LocalAutoBackupSettings> loadSettings() async {
    return const LocalAutoBackupSettings(
      enabled: false,
      locationPath: 'Ventio/Backup',
      dailyCount: defaultDailyCount,
      weeklyCount: defaultWeeklyCount,
      monthlyCount: defaultMonthlyCount,
    );
  }

  static DateTime? lastSuccessAt() => null;

  static Future<void> saveSettings(LocalAutoBackupSettings settings) async {}

  static Future<String> defaultLocationPath() async => 'Ventio/Backup';

  static Future<void> runDueBackup(AppStore store) async {}

  static Future<Object> createBackupNow(
    AppStore store, {
    LocalAutoBackupSettings? settings,
    String reason = 'manual',
  }) async {
    throw UnsupportedError('Local automatic backup is not supported on Web.');
  }
}
