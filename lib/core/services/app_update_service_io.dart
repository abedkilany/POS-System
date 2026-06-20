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

class AppUpdateService {
  AppUpdateService({http.Client? client}) : _client = client ?? http.Client();

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
    final update = await fetchLatest();
    if (update == null) return null;
    return update.isNewerThan(AppBrand.versionName, AppBrand.buildNumber)
        ? update
        : null;
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
        if (total > 0) onProgress?.call(received / total);
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
        throw StateError('Downloaded update failed integrity verification.');
      }
    }

    await _saveDownloadedUpdate(update, file.path);
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

AppUpdateService getAppUpdateService() => AppUpdateService();

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
