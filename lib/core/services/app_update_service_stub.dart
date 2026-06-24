import 'package:flutter/foundation.dart';

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.version,
    required this.build,
    this.channel = 'stable',
    this.notes = const <String>[],
    this.windowsUrl = '',
    this.sha256 = '',
    this.sizeBytes = 0,
    this.required = false,
  });

  final String version;
  final int build;
  final String channel;
  final List<String> notes;
  final String windowsUrl;
  final String sha256;
  final int sizeBytes;
  final bool required;

  String get displayVersion => '$version+$build';

  bool isNewerThan(String currentVersion, int currentBuild) {
    final versionCompare =
        _compareSemanticVersion(version, currentVersion.trim());
    if (versionCompare != 0) return versionCompare > 0;
    return build > currentBuild;
  }
}

class AppUpdateUiState {
  const AppUpdateUiState({
    this.latest,
    this.lastCheckedAt,
    this.checking = false,
    this.downloading = false,
    this.installing = false,
    this.downloadProgress,
    this.downloadedInstallerPath,
    this.lastError = '',
  });

  final AppUpdateInfo? latest;
  final DateTime? lastCheckedAt;
  final bool checking;
  final bool downloading;
  final bool installing;
  final double? downloadProgress;
  final String? downloadedInstallerPath;
  final String lastError;

  bool get hasUpdate =>
      latest?.isNewerThan('0.0.0', 0) ?? false;

  AppUpdateUiState copyWith({
    AppUpdateInfo? latest,
    bool clearLatest = false,
    DateTime? lastCheckedAt,
    bool clearLastCheckedAt = false,
    bool? checking,
    bool? downloading,
    bool? installing,
    double? downloadProgress,
    bool clearDownloadProgress = false,
    String? downloadedInstallerPath,
    bool clearDownloadedInstallerPath = false,
    String? lastError,
    bool clearLastError = false,
  }) {
    return AppUpdateUiState(
      latest: clearLatest ? null : latest ?? this.latest,
      lastCheckedAt:
          clearLastCheckedAt ? null : lastCheckedAt ?? this.lastCheckedAt,
      checking: checking ?? this.checking,
      downloading: downloading ?? this.downloading,
      installing: installing ?? this.installing,
      downloadProgress:
          clearDownloadProgress ? null : downloadProgress ?? this.downloadProgress,
      downloadedInstallerPath: clearDownloadedInstallerPath
          ? null
          : downloadedInstallerPath ?? this.downloadedInstallerPath,
      lastError: clearLastError ? '' : lastError ?? this.lastError,
    );
  }
}

class AppUpdateService {
  const AppUpdateService();

  static final ValueNotifier<AppUpdateUiState> status =
      ValueNotifier<AppUpdateUiState>(const AppUpdateUiState());

  bool get isSupported => false;

  Future<AppUpdateInfo?> fetchLatest() async => null;

  Future<AppUpdateInfo?> checkForUpdate() async => null;

  Future<String> downloadUpdate(
    AppUpdateInfo update, {
    void Function(double progress)? onProgress,
    void Function(void Function())? registerCancel,
  }) async {
    throw UnsupportedError('Ventio updates are only supported on Windows.');
  }

  Future<String?> getDownloadedInstallerPath(AppUpdateInfo update) async =>
      null;

  Future<void> clearDownloadedUpdate() async {}

  Future<void> launchInstaller(String installerPath) async {
    throw UnsupportedError('Ventio updates are only supported on Windows.');
  }

  Future<String> downloadAndInstall(
    AppUpdateInfo update, {
    void Function(double progress)? onProgress,
  }) async {
    throw UnsupportedError('Ventio updates are only supported on Windows.');
  }
}

AppUpdateService getAppUpdateService() => const AppUpdateService();

int _compareSemanticVersion(String a, String b) {
  final left = _semanticParts(a);
  final right = _semanticParts(b);
  for (var i = 0; i < 3; i += 1) {
    final diff = left[i].compareTo(right[i]);
    if (diff != 0) return diff;
  }
  return 0;
}

List<int> _semanticParts(String value) {
  final clean = value.split('+').first.trim();
  final parts = clean.split('.');
  return List<int>.generate(
    3,
    (index) => index < parts.length ? int.tryParse(parts[index]) ?? 0 : 0,
  );
}
