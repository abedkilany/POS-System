import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../app_brand.dart';
import 'local_database_service.dart';

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

  bool get hasWindowsInstaller => windowsUrl.trim().isNotEmpty;

  bool isNewerThan(String currentVersion, int currentBuild) {
    final versionCompare =
        _compareSemanticVersion(version, currentVersion.trim());
    if (versionCompare != 0) return versionCompare > 0;
    return build > currentBuild;
  }

  static AppUpdateInfo fromJson(Map<String, dynamic> json) {
    final windows = json['windows'] is Map
        ? Map<String, dynamic>.from(json['windows'] as Map)
        : const <String, dynamic>{};
    final rawNotes = json['notes'];
    final notes = rawNotes is List
        ? rawNotes.map((item) => item.toString()).toList()
        : rawNotes == null || rawNotes.toString().trim().isEmpty
            ? const <String>[]
            : <String>[rawNotes.toString()];
    return AppUpdateInfo(
      version: (json['version'] ?? '').toString().trim(),
      build: int.tryParse((json['build'] ?? '').toString()) ?? 0,
      channel: (json['channel'] ?? 'stable').toString().trim(),
      notes: notes,
      windowsUrl: (windows['url'] ?? json['windowsUrl'] ?? '').toString(),
      sha256: (windows['sha256'] ?? json['sha256'] ?? '').toString().trim(),
      sizeBytes: int.tryParse(
              (windows['size'] ?? json['size'] ?? '').toString().trim()) ??
          0,
      required: json['required'] == true,
    );
  }
}

class AppUpdateDownloadRecord {
  const AppUpdateDownloadRecord({
    required this.version,
    required this.build,
    required this.installerPath,
    required this.sha256,
    required this.downloadedAt,
  });

  final String version;
  final int build;
  final String installerPath;
  final String sha256;
  final DateTime downloadedAt;

  bool matches(AppUpdateInfo update) =>
      version == update.version &&
      build == update.build &&
      sha256 == update.sha256.trim().toLowerCase();

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': version,
        'build': build,
        'installerPath': installerPath,
        'sha256': sha256,
        'downloadedAt': downloadedAt.toIso8601String(),
      };

  static AppUpdateDownloadRecord? fromJson(Map<String, dynamic> json) {
    final version = (json['version'] ?? '').toString().trim();
    final build = int.tryParse((json['build'] ?? '').toString()) ?? 0;
    final path = (json['installerPath'] ?? '').toString().trim();
    final sha256 = (json['sha256'] ?? '').toString().trim().toLowerCase();
    final downloadedAt =
        DateTime.tryParse((json['downloadedAt'] ?? '').toString()) ??
            DateTime.fromMillisecondsSinceEpoch(0);
    if (version.isEmpty || build <= 0 || path.isEmpty) return null;
    return AppUpdateDownloadRecord(
      version: version,
      build: build,
      installerPath: path,
      sha256: sha256,
      downloadedAt: downloadedAt,
    );
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
      latest?.isNewerThan(AppBrand.versionName, AppBrand.buildNumber) ?? false;

  bool get readyToInstall =>
      hasUpdate &&
      downloadedInstallerPath != null &&
      downloadedInstallerPath!.trim().isNotEmpty;

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
  AppUpdateService({http.Client? client}) : _client = client ?? http.Client();

  static final ValueNotifier<AppUpdateUiState> status =
      ValueNotifier<AppUpdateUiState>(const AppUpdateUiState());
  static const _downloadRecordKey = 'ventio_update_download_record_v1';

  static const _manifestUrl = String.fromEnvironment(
    'VENTIO_UPDATE_URL',
    defaultValue: 'https://ventioapp.com/releases/latest.json',
  );

  final http.Client _client;

  bool get isSupported => !kIsWeb && Platform.isWindows;

  Future<AppUpdateInfo?> fetchLatest() async {
    if (!isSupported || _manifestUrl.trim().isEmpty) return null;
    final response = await _client
        .get(Uri.parse(_manifestUrl.trim()))
        .timeout(const Duration(seconds: 8));
    if (response.statusCode == 404) return null;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Update manifest returned HTTP ${response.statusCode}.');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) throw StateError('Update manifest is invalid.');
    final update = AppUpdateInfo.fromJson(Map<String, dynamic>.from(decoded));
    if (update.version.isEmpty || !update.hasWindowsInstaller) return null;
    return update;
  }

  Future<AppUpdateInfo?> checkForUpdate() async {
    status.value = status.value.copyWith(
      checking: true,
      clearLastError: true,
    );
    try {
      final update = await fetchLatest();
      if (update == null) {
        await clearDownloadedUpdate();
        status.value = status.value.copyWith(
          clearLatest: true,
          clearLastCheckedAt: true,
          checking: false,
          downloading: false,
          installing: false,
          clearDownloadProgress: true,
          clearDownloadedInstallerPath: true,
        );
        return null;
      }

      final latest = update.isNewerThan(AppBrand.versionName, AppBrand.buildNumber)
          ? update
          : null;
      final restoredPath = latest == null
          ? null
          : await getDownloadedInstallerPath(update);
      status.value = status.value.copyWith(
        latest: latest,
        lastCheckedAt: DateTime.now(),
        checking: false,
        downloading: false,
        installing: false,
        downloadProgress: latest == null || restoredPath == null ? null : status.value.downloadProgress,
        downloadedInstallerPath: restoredPath,
        clearDownloadedInstallerPath: restoredPath == null,
      );
      return latest;
    } catch (error) {
      status.value = status.value.copyWith(
        checking: false,
        lastCheckedAt: DateTime.now(),
        lastError: error.toString(),
      );
      rethrow;
    }
  }

  Future<String> downloadUpdate(
    AppUpdateInfo update, {
    void Function(double progress)? onProgress,
    void Function(void Function())? registerCancel,
  }) async {
    if (!isSupported) {
      throw UnsupportedError('Ventio updates are only supported on Windows.');
    }
    final uri = Uri.parse(update.windowsUrl.trim());
    final client = HttpClient();
    var cancelled = false;
    registerCancel?.call(() {
      cancelled = true;
      client.close(force: true);
    });

    final filename = uri.pathSegments.isNotEmpty
        ? uri.pathSegments.last
        : 'VentioSetup-${update.version}.exe';
    final file = File('${Directory.systemTemp.path}${Platform.pathSeparator}'
        '${filename.trim().isEmpty ? 'VentioSetup-${update.version}.exe' : filename}');
    final sink = file.openWrite();
    final bytes = <int>[];
    var received = 0;
    status.value = status.value.copyWith(
      latest: update,
      downloading: true,
      installing: false,
      downloadProgress: 0,
      clearLastError: true,
    );
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
            'Update download failed: HTTP ${response.statusCode}.');
      }
      final responseLength = response.contentLength;
      final total = responseLength > 0
          ? responseLength
          : update.sizeBytes > 0
              ? update.sizeBytes
              : 0;
      await for (final chunk in response) {
        if (cancelled) {
          throw StateError('Update download cancelled.');
        }
        bytes.addAll(chunk);
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          final progress = received / total;
          status.value = status.value.copyWith(downloadProgress: progress);
          onProgress?.call(progress);
        }
      }
    } on HttpException {
      if (cancelled) {
        throw StateError('Update download cancelled.');
      }
      rethrow;
    } catch (error) {
      if (cancelled) {
        throw StateError('Update download cancelled.');
      }
      rethrow;
    } finally {
      await sink.close();
      client.close(force: true);
    }

    final expectedHash = update.sha256.trim().toLowerCase();
    if (expectedHash.isNotEmpty) {
      final actualHash = sha256.convert(bytes).toString().toLowerCase();
      if (actualHash != expectedHash) {
        await file.delete().catchError((_) => file);
        status.value = status.value.copyWith(
          downloading: false,
          installing: false,
          clearDownloadProgress: true,
          clearDownloadedInstallerPath: true,
          lastError: 'Downloaded update failed integrity verification.',
        );
        throw StateError('Downloaded update failed integrity verification.');
      }
    }

    await _saveDownloadedUpdate(update, file.path);
    status.value = status.value.copyWith(
      downloading: false,
      installing: false,
      downloadProgress: 1,
      downloadedInstallerPath: file.path,
      clearLastError: true,
    );
    return file.path;
  }

  Future<String?> getDownloadedInstallerPath(AppUpdateInfo update) async {
    final raw = LocalDatabaseService.getString(_downloadRecordKey);
    if (raw == null || raw.trim().isEmpty) return null;
    Map<String, dynamic>? decoded;
    try {
      final parsed = jsonDecode(raw);
      if (parsed is Map) {
        decoded = Map<String, dynamic>.from(parsed);
      }
    } catch (_) {
      decoded = null;
    }
    if (decoded == null) {
      await clearDownloadedUpdate();
      return null;
    }
    final record = AppUpdateDownloadRecord.fromJson(decoded);
    if (record == null || !record.matches(update)) {
      await clearDownloadedUpdate();
      return null;
    }
    final file = File(record.installerPath);
    if (!await file.exists()) {
      await clearDownloadedUpdate();
      return null;
    }
    return file.path;
  }

  Future<void> clearDownloadedUpdate() async {
    await LocalDatabaseService.deleteString(_downloadRecordKey);
    status.value = status.value.copyWith(clearDownloadedInstallerPath: true);
  }

  Future<void> _saveDownloadedUpdate(
    AppUpdateInfo update,
    String installerPath,
  ) async {
    final record = AppUpdateDownloadRecord(
      version: update.version,
      build: update.build,
      installerPath: installerPath,
      sha256: update.sha256.trim().toLowerCase(),
      downloadedAt: DateTime.now(),
    );
    await LocalDatabaseService.setString(
        _downloadRecordKey, jsonEncode(record.toJson()));
  }

  Future<void> launchInstaller(String installerPath) async {
    if (!isSupported) {
      throw UnsupportedError('Ventio updates are only supported on Windows.');
    }
    final file = File(installerPath);
    if (!await file.exists()) {
      throw StateError('Downloaded update installer was not found.');
    }
    status.value = status.value.copyWith(
      installing: true,
      downloading: false,
      clearDownloadProgress: true,
      clearLastError: true,
    );
    await Process.start(
      file.path,
      const <String>[
        '/VERYSILENT',
        '/SUPPRESSMSGBOXES',
        '/NOCANCEL',
        '/SP-',
        '/CLOSEAPPLICATIONS',
        '/RESTARTAPPLICATIONS',
        '/NORESTART',
      ],
      mode: ProcessStartMode.detached,
    );
  }

  Future<String> downloadAndInstall(
    AppUpdateInfo update, {
    void Function(double progress)? onProgress,
  }) async {
    final installerPath = await downloadUpdate(
      update,
      onProgress: onProgress,
    );
    await launchInstaller(installerPath);
    return installerPath;
  }
}

final AppUpdateService _appUpdateServiceSingleton = AppUpdateService();

AppUpdateService getAppUpdateService() => _appUpdateServiceSingleton;

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
