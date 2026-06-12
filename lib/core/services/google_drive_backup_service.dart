import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../data/app_store.dart';
import 'cloud_sync_service.dart';
import 'google_drive_browser_auth.dart';
import 'local_database_service.dart';

class GoogleDriveBackupSettings {
  const GoogleDriveBackupSettings({
    required this.enabled,
    required this.clientId,
    required this.clientSecret,
    required this.folderId,
    required this.refreshToken,
    required this.accessToken,
    required this.accessTokenExpiresAt,
    required this.dailyCount,
    required this.weeklyCount,
    required this.monthlyCount,
  });

  final bool enabled;
  final String clientId;
  final String clientSecret;
  final String folderId;
  final String refreshToken;
  final String accessToken;
  final DateTime? accessTokenExpiresAt;
  final int dailyCount;
  final int weeklyCount;
  final int monthlyCount;

  bool get hasClient => clientId.trim().isNotEmpty;
  bool get hasClientSecret => clientSecret.trim().isNotEmpty;
  bool get isAuthorized =>
      refreshToken.trim().isNotEmpty || accessToken.trim().isNotEmpty;

  GoogleDriveBackupSettings copyWith({
    bool? enabled,
    String? clientId,
    String? clientSecret,
    String? folderId,
    String? refreshToken,
    String? accessToken,
    DateTime? accessTokenExpiresAt,
    bool clearAccessTokenExpiresAt = false,
    int? dailyCount,
    int? weeklyCount,
    int? monthlyCount,
  }) {
    return GoogleDriveBackupSettings(
      enabled: enabled ?? this.enabled,
      clientId: clientId ?? this.clientId,
      clientSecret: clientSecret ?? this.clientSecret,
      folderId: folderId ?? this.folderId,
      refreshToken: refreshToken ?? this.refreshToken,
      accessToken: accessToken ?? this.accessToken,
      accessTokenExpiresAt: clearAccessTokenExpiresAt
          ? null
          : accessTokenExpiresAt ?? this.accessTokenExpiresAt,
      dailyCount: dailyCount ?? this.dailyCount,
      weeklyCount: weeklyCount ?? this.weeklyCount,
      monthlyCount: monthlyCount ?? this.monthlyCount,
    );
  }
}

class GoogleDriveBackupStatus {
  const GoogleDriveBackupStatus({
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

class GoogleDriveBackupFile {
  const GoogleDriveBackupFile({
    required this.id,
    required this.name,
    required this.category,
    this.createdAt,
    this.sizeBytes,
  });

  final String id;
  final String name;
  final String category;
  final DateTime? createdAt;
  final int? sizeBytes;

  String get displayName {
    final size = sizeBytes == null ? '' : ' - ${_formatSize(sizeBytes!)}';
    return '$category - $name$size';
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    return '${(kb / 1024).toStringAsFixed(1)} MB';
  }
}

class GoogleDriveAuthorizationChallenge {
  const GoogleDriveAuthorizationChallenge({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUrl,
    this.verificationUrlComplete = '',
    required this.expiresAt,
    required this.intervalSeconds,
  });

  final String deviceCode;
  final String userCode;
  final String verificationUrl;
  final String verificationUrlComplete;
  final DateTime expiresAt;
  final int intervalSeconds;
}

class _GoogleTokenResponse {
  const _GoogleTokenResponse({
    required this.statusCode,
    required this.decoded,
  });

  final int statusCode;
  final Map<String, dynamic> decoded;

  bool get isSuccess => statusCode >= 200 && statusCode < 300;
}

class GoogleDriveBackupService {
  GoogleDriveBackupService._();

  static const String _enabledKey = 'google_drive_backup_enabled_v1';
  static const String _clientIdKey = 'google_drive_backup_client_id_v1';
  static const String _clientSecretKey = 'google_drive_backup_client_secret_v1';
  static const String _folderIdKey = 'google_drive_backup_folder_id_v1';
  static const String _refreshTokenKey = 'google_drive_backup_refresh_token_v1';
  static const String _accessTokenKey = 'google_drive_backup_access_token_v1';
  static const String _accessTokenExpiresAtKey =
      'google_drive_backup_access_token_expires_at_v1';
  static const String _dailyCountKey = 'google_drive_backup_daily_count_v1';
  static const String _weeklyCountKey = 'google_drive_backup_weekly_count_v1';
  static const String _monthlyCountKey = 'google_drive_backup_monthly_count_v1';
  static const String _lastSuccessKey = 'google_drive_backup_last_success_v1';
  static const int defaultDailyCount = 7;
  static const int defaultWeeklyCount = 4;
  static const int defaultMonthlyCount = 3;
  static const String _scope = 'https://www.googleapis.com/auth/drive.file';
  static const String _defaultClientId =
      '462649203125-beloepij0c32pr231qbn3jm07uss4mr9.apps.googleusercontent.com';
  static const String bundledClientId = String.fromEnvironment(
      'GOOGLE_DRIVE_CLIENT_ID',
      defaultValue: _defaultClientId);
  static const String bundledClientSecret =
      String.fromEnvironment('GOOGLE_DRIVE_CLIENT_SECRET');
  static bool get hasBundledClient => bundledClientId.trim().isNotEmpty;

  static final ValueNotifier<GoogleDriveBackupStatus> status =
      ValueNotifier<GoogleDriveBackupStatus>(const GoogleDriveBackupStatus());

  static bool _isRunning = false;

  static Future<GoogleDriveBackupSettings> loadSettings() async {
    final savedClientId = LocalDatabaseService.getString(_clientIdKey) ?? '';
    final savedClientSecret =
        LocalDatabaseService.getString(_clientSecretKey) ?? '';
    return GoogleDriveBackupSettings(
      enabled: LocalDatabaseService.getString(_enabledKey) == 'true',
      clientId: savedClientId.trim().isEmpty ? bundledClientId : savedClientId,
      clientSecret: savedClientSecret.trim().isEmpty
          ? bundledClientSecret
          : savedClientSecret,
      folderId: LocalDatabaseService.getString(_folderIdKey) ?? '',
      refreshToken: LocalDatabaseService.getString(_refreshTokenKey) ?? '',
      accessToken: LocalDatabaseService.getString(_accessTokenKey) ?? '',
      accessTokenExpiresAt: DateTime.tryParse(
          LocalDatabaseService.getString(_accessTokenExpiresAtKey) ?? ''),
      dailyCount: _readPositiveInt(_dailyCountKey, defaultDailyCount),
      weeklyCount: _readPositiveInt(_weeklyCountKey, defaultWeeklyCount),
      monthlyCount: _readPositiveInt(_monthlyCountKey, defaultMonthlyCount),
    );
  }

  static Future<void> saveSettings(GoogleDriveBackupSettings settings) async {
    await LocalDatabaseService.setString(
        _enabledKey, settings.enabled ? 'true' : 'false');
    await LocalDatabaseService.setString(
        _clientIdKey, settings.clientId.trim());
    await LocalDatabaseService.setString(
        _clientSecretKey, settings.clientSecret.trim());
    await LocalDatabaseService.setString(
        _folderIdKey, settings.folderId.trim());
    await LocalDatabaseService.setString(
        _refreshTokenKey, settings.refreshToken.trim());
    await LocalDatabaseService.setString(
        _accessTokenKey, settings.accessToken.trim());
    await LocalDatabaseService.setString(_accessTokenExpiresAtKey,
        settings.accessTokenExpiresAt?.toIso8601String() ?? '');
    await LocalDatabaseService.setString(
        _dailyCountKey, settings.dailyCount.clamp(1, 365).toString());
    await LocalDatabaseService.setString(
        _weeklyCountKey, settings.weeklyCount.clamp(1, 52).toString());
    await LocalDatabaseService.setString(
        _monthlyCountKey, settings.monthlyCount.clamp(1, 24).toString());
  }

  static Future<void> disconnect() async {
    final settings = await loadSettings();
    await saveSettings(settings.copyWith(
      enabled: false,
      refreshToken: '',
      accessToken: '',
      clearAccessTokenExpiresAt: true,
    ));
  }

  static Future<GoogleDriveAuthorizationChallenge> startAuthorization(
      GoogleDriveBackupSettings settings) async {
    if (kIsWeb) {
      throw UnsupportedError(
          'Google Drive backup authorization is not supported on Web.');
    }
    if (!settings.hasClient) {
      throw StateError('Google Drive Client ID is required.');
    }

    final response = await http.post(
      Uri.parse('https://oauth2.googleapis.com/device/code'),
      headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
      body: <String, String>{
        'client_id': settings.clientId.trim(),
        'scope': _scope,
      },
    );
    final decoded = _decodeResponse(response);
    return GoogleDriveAuthorizationChallenge(
      deviceCode: decoded['device_code'] as String,
      userCode: decoded['user_code'] as String,
      verificationUrl: (decoded['verification_url'] ??
          decoded['verification_uri']) as String,
      verificationUrlComplete:
          (decoded['verification_url_complete'] ?? '').toString(),
      expiresAt: DateTime.now()
          .add(Duration(seconds: (decoded['expires_in'] as num).toInt())),
      intervalSeconds:
          ((decoded['interval'] as num?)?.toInt() ?? 5).clamp(1, 30).toInt(),
    );
  }

  static Future<GoogleDriveBackupSettings> finishAuthorization(
    GoogleDriveBackupSettings settings,
    GoogleDriveAuthorizationChallenge challenge,
  ) async {
    final decoded = await _requestDeviceToken(settings, challenge);
    final next = settings.copyWith(
      refreshToken:
          (decoded['refresh_token'] as String?) ?? settings.refreshToken,
      accessToken: decoded['access_token'] as String,
      accessTokenExpiresAt: DateTime.now().add(Duration(
          seconds: ((decoded['expires_in'] as num?)?.toInt() ?? 3600) - 60)),
    );
    await saveSettings(next);
    return next;
  }

  static Future<GoogleDriveBackupSettings> connectWithBrowser(
      GoogleDriveBackupSettings settings) async {
    if (kIsWeb) {
      throw UnsupportedError(
          'Browser Google authorization is not supported on Web.');
    }
    if (!settings.hasClient) {
      throw StateError('Google Drive Client ID is required.');
    }
    final challenge = await startAuthorization(settings);
    await GoogleDriveBrowserAuth.openUrl(
      challenge.verificationUrlComplete.isNotEmpty
          ? challenge.verificationUrlComplete
          : challenge.verificationUrl,
    );
    final decoded = await _pollDeviceAuthorization(settings, challenge);
    final next = settings.copyWith(
      refreshToken:
          (decoded['refresh_token'] as String?) ?? settings.refreshToken,
      accessToken: decoded['access_token'] as String,
      accessTokenExpiresAt: DateTime.now().add(Duration(
          seconds: ((decoded['expires_in'] as num?)?.toInt() ?? 3600) - 60)),
    );
    await saveSettings(next);
    return next;
  }

  static Future<GoogleDriveBackupSettings> connectWithServer(
      GoogleDriveBackupSettings settings) async {
    final cloud = CloudSyncSettings.load();
    final apiBaseUrl = cloud.apiBaseUrl.trim();
    if (apiBaseUrl.isEmpty) {
      throw StateError(
          'Cloud API URL is required for Google Drive connection.');
    }
    final sessionId = _randomSessionId();
    final base = CloudSyncSettings.normalizeApiBaseUrl(apiBaseUrl);
    final authUrl = Uri.parse('$base/api/google-drive/auth-start')
        .replace(queryParameters: {'session_id': sessionId});
    await GoogleDriveBrowserAuth.openUrl(authUrl.toString());

    final statusUrl = Uri.parse('$base/api/google-drive/status')
        .replace(queryParameters: {'session_id': sessionId});
    final deadline = DateTime.now().add(const Duration(minutes: 5));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 2));
      final response = await http.get(statusUrl);
      final decoded = response.body.trim().isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(decoded['error']?.toString() ??
            'Google Drive connection failed (${response.statusCode}).');
      }
      final status = decoded['status']?.toString() ?? '';
      if (status == 'pending') continue;
      if (status == 'error' || decoded['ok'] == false) {
        throw StateError(
            decoded['error']?.toString() ?? 'Google Drive connection failed.');
      }
      if (status == 'complete') {
        final next = settings.copyWith(
          refreshToken: decoded['refreshToken']?.toString() ?? '',
          accessToken: decoded['accessToken']?.toString() ?? '',
          accessTokenExpiresAt: DateTime.tryParse(
              decoded['accessTokenExpiresAt']?.toString() ?? ''),
        );
        await saveSettings(next);
        return next;
      }
    }
    throw StateError('Google Drive connection timed out.');
  }

  static Future<void> openAuthorizationChallenge(
      GoogleDriveAuthorizationChallenge challenge) {
    return GoogleDriveBrowserAuth.openUrl(
      challenge.verificationUrlComplete.isNotEmpty
          ? challenge.verificationUrlComplete
          : challenge.verificationUrl,
    );
  }

  static Future<GoogleDriveBackupSettings> finishBrowserAuthorization(
    GoogleDriveBackupSettings settings,
    GoogleDriveAuthorizationChallenge challenge,
  ) async {
    final decoded = await _pollDeviceAuthorization(settings, challenge);
    final next = settings.copyWith(
      refreshToken:
          (decoded['refresh_token'] as String?) ?? settings.refreshToken,
      accessToken: decoded['access_token'] as String,
      accessTokenExpiresAt: DateTime.now().add(Duration(
          seconds: ((decoded['expires_in'] as num?)?.toInt() ?? 3600) - 60)),
    );
    await saveSettings(next);
    return next;
  }

  static Future<Map<String, dynamic>> _pollDeviceAuthorization(
    GoogleDriveBackupSettings settings,
    GoogleDriveAuthorizationChallenge challenge,
  ) async {
    var interval = Duration(seconds: challenge.intervalSeconds);
    while (DateTime.now().isBefore(challenge.expiresAt)) {
      await Future<void>.delayed(interval);
      final result = await _requestDeviceTokenRaw(settings, challenge);
      final decoded = result.decoded;
      if (result.isSuccess) {
        return decoded;
      }
      final error = decoded['error']?.toString() ?? '';
      if (error == 'authorization_pending') {
        continue;
      }
      if (error == 'slow_down') {
        interval += const Duration(seconds: 5);
        continue;
      }
      if (error == 'access_denied') {
        throw StateError('Google Drive access was denied.');
      }
      if (error == 'expired_token') {
        throw StateError('Google authorization expired. Try again.');
      }
      final description = decoded['error_description'];
      throw StateError(description?.toString() ??
          (error.isEmpty ? 'Google authorization failed.' : error));
    }
    throw StateError('Google authorization expired. Try again.');
  }

  static Future<Map<String, dynamic>> _requestDeviceToken(
    GoogleDriveBackupSettings settings,
    GoogleDriveAuthorizationChallenge challenge,
  ) async {
    final result = await _requestDeviceTokenRaw(settings, challenge);
    if (result.isSuccess) return result.decoded;
    final description = result.decoded['error_description']?.toString();
    if (description != null && description.isNotEmpty) {
      throw StateError(description);
    }
    final error = result.decoded['error'];
    if (error is Map && error['message'] != null) {
      throw StateError(error['message'].toString());
    }
    if (error != null) {
      if (error.toString() == 'invalid_request' && !settings.hasClientSecret) {
        throw StateError(
            'Google requires the OAuth client secret for this connection. Import Client secret.json once from Developer setup.');
      }
      throw StateError(error.toString());
    }
    throw StateError('Google authorization failed.');
  }

  static Future<_GoogleTokenResponse> _requestDeviceTokenRaw(
    GoogleDriveBackupSettings settings,
    GoogleDriveAuthorizationChallenge challenge,
  ) async {
    final first = await _postDeviceToken(settings, challenge,
        includeSecret: settings.hasClientSecret);
    if (first.isSuccess) return first;
    final error = first.decoded['error']?.toString() ?? '';
    if (error == 'invalid_request' && settings.hasClientSecret) {
      return _postDeviceToken(settings, challenge, includeSecret: false);
    }
    return first;
  }

  static Future<_GoogleTokenResponse> _postDeviceToken(
    GoogleDriveBackupSettings settings,
    GoogleDriveAuthorizationChallenge challenge, {
    required bool includeSecret,
  }) async {
    final body = <String, String>{
      'client_id': settings.clientId.trim(),
      'device_code': challenge.deviceCode,
      'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
    };
    if (includeSecret && settings.clientSecret.trim().isNotEmpty) {
      body['client_secret'] = settings.clientSecret.trim();
    }
    final response = await http.post(
      Uri.parse('https://oauth2.googleapis.com/token'),
      headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
      body: body,
    );
    final decoded = response.body.trim().isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;
    return _GoogleTokenResponse(
      statusCode: response.statusCode,
      decoded: decoded,
    );
  }

  static Future<void> runDueBackup(AppStore store) async {
    if (_isRunning || kIsWeb) return;
    if (store.appIdentity.isClient) return;
    final settings = await loadSettings();
    if (!settings.enabled || !settings.hasClient || !settings.isAuthorized) {
      return;
    }
    final now = DateTime.now();
    final scheduled = DateTime(now.year, now.month, now.day, 2, 15);
    if (now.isBefore(scheduled) && await _hasDailyForDate(settings, now)) {
      return;
    }
    await createBackupNow(store, settings: settings, reason: 'auto');
  }

  static Future<String> createBackupNow(
    AppStore store, {
    GoogleDriveBackupSettings? settings,
    String reason = 'manual',
  }) async {
    if (_isRunning) throw StateError('Google Drive backup is already running.');
    if (kIsWeb) {
      throw UnsupportedError('Google Drive backup is not supported on Web.');
    }
    if (store.appIdentity.isClient) {
      throw StateError(
          'Google Drive backup is only available on the Host device.');
    }

    _isRunning = true;
    status.value = const GoogleDriveBackupStatus(
        isRunning: true, message: 'Creating Google Drive backup...');
    try {
      var resolved = settings ?? await loadSettings();
      if (!resolved.hasClient) {
        throw StateError('Google Drive Client ID is required.');
      }
      if (!resolved.isAuthorized) {
        throw StateError('Google Drive is not authorized yet.');
      }

      final token = await _accessToken(resolved);
      resolved = await loadSettings();
      final folderId = resolved.folderId.trim().isEmpty
          ? await _ensureFolder(token, 'Ventio Backups')
          : resolved.folderId.trim();
      if (folderId != resolved.folderId.trim()) {
        resolved = resolved.copyWith(folderId: folderId);
        await saveSettings(resolved);
      }

      final now = DateTime.now();
      status.value = const GoogleDriveBackupStatus(
          isRunning: true, message: 'Compressing backup...');
      final bytes = _buildZipBytes(store.exportBackupJson(), now, reason);
      final fileName = reason == 'manual'
          ? 'ventio_manual_${_dateTimeStamp(now)}.vtb'
          : 'ventio_daily_${_dateStamp(now)}.vtb';
      final category = reason == 'manual' ? 'Backup now' : 'Daily';
      final categoryFolderId =
          await _ensureFolder(token, category, parentId: folderId);

      status.value = const GoogleDriveBackupStatus(
          isRunning: true, message: 'Uploading to Google Drive...');
      final uploadedId =
          await _uploadFile(token, categoryFolderId, fileName, bytes);

      if (reason != 'manual') {
        final weeklyId =
            await _ensureFolder(token, 'Weekly', parentId: folderId);
        final monthlyId =
            await _ensureFolder(token, 'Monthly', parentId: folderId);
        final weekName = 'ventio_weekly_${_weekStamp(now)}.vtb';
        final monthName =
            'ventio_monthly_${now.year.toString().padLeft(4, '0')}_${now.month.toString().padLeft(2, '0')}.vtb';
        if (!await _fileExists(token, weeklyId, weekName)) {
          await _uploadFile(token, weeklyId, weekName, bytes);
        }
        if (!await _fileExists(token, monthlyId, monthName)) {
          await _uploadFile(token, monthlyId, monthName, bytes);
        }
        await _trimBackups(token, categoryFolderId, resolved.dailyCount);
        await _trimBackups(token, weeklyId, resolved.weeklyCount);
        await _trimBackups(token, monthlyId, resolved.monthlyCount);
      }

      await LocalDatabaseService.setString(
          _lastSuccessKey, now.toIso8601String());
      status.value = GoogleDriveBackupStatus(
          lastSuccessAt: now, message: 'Google Drive backup completed.');
      return uploadedId;
    } catch (error) {
      status.value = GoogleDriveBackupStatus(
          lastError: error.toString(), message: 'Google Drive backup failed.');
      rethrow;
    } finally {
      _isRunning = false;
      Timer(const Duration(seconds: 5), () {
        if (!status.value.isRunning) {
          status.value = GoogleDriveBackupStatus(
              lastSuccessAt: status.value.lastSuccessAt);
        }
      });
    }
  }

  static Future<List<GoogleDriveBackupFile>> listBackupFiles({
    GoogleDriveBackupSettings? settings,
  }) async {
    final resolved = settings ?? await loadSettings();
    if (!resolved.isAuthorized) {
      throw StateError('Google Drive is not authorized yet.');
    }
    final token = await _accessToken(resolved);
    final rootFolderId = resolved.folderId.trim();
    if (rootFolderId.isEmpty) return const <GoogleDriveBackupFile>[];

    final backups = <GoogleDriveBackupFile>[];
    for (final category in const ['Backup now', 'Daily', 'Weekly', 'Monthly']) {
      final folderId =
          await _findFolder(token, category, parentId: rootFolderId);
      if (folderId == null) continue;
      final query =
          "'$folderId' in parents and trashed = false and name contains '.vtb'";
      final list = await _driveGet(token, 'files', <String, String>{
        'q': query,
        'fields': 'files(id,name,createdTime,size)',
        'pageSize': '1000',
        'orderBy': 'createdTime desc',
      });
      for (final raw in (list['files'] as List?) ?? const []) {
        final file = Map<String, dynamic>.from(raw as Map);
        backups.add(GoogleDriveBackupFile(
          id: file['id']?.toString() ?? '',
          name: file['name']?.toString() ?? 'backup.vtb',
          category: category,
          createdAt: DateTime.tryParse(file['createdTime']?.toString() ?? ''),
          sizeBytes: int.tryParse(file['size']?.toString() ?? ''),
        ));
      }
    }
    backups.removeWhere((file) => file.id.trim().isEmpty);
    backups.sort((a, b) {
      final aTime = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });
    return backups;
  }

  static Future<List<int>> downloadBackupFile(
    GoogleDriveBackupFile file, {
    GoogleDriveBackupSettings? settings,
  }) async {
    final resolved = settings ?? await loadSettings();
    if (!resolved.isAuthorized) {
      throw StateError('Google Drive is not authorized yet.');
    }
    final token = await _accessToken(resolved);
    final response = await http.get(
      Uri.https('www.googleapis.com', '/drive/v3/files/${file.id}', {
        'alt': 'media',
      }),
      headers: <String, String>{'Authorization': 'Bearer $token'},
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.bodyBytes;
    }
    final body = response.body.trim();
    if (body.isNotEmpty) {
      try {
        final decoded = jsonDecode(body) as Map<String, dynamic>;
        final error = decoded['error'];
        if (error is Map && error['message'] != null) {
          final message = error['message'].toString();
          throw StateError(message);
        }
      } on FormatException {
        // Fall through to the generic status-code message below.
      }
    }
    throw StateError('Google Drive download failed (${response.statusCode}).');
  }

  static Future<String> _accessToken(GoogleDriveBackupSettings settings) async {
    final expiresAt = settings.accessTokenExpiresAt;
    if (settings.accessToken.trim().isNotEmpty &&
        expiresAt != null &&
        expiresAt.isAfter(DateTime.now().add(const Duration(minutes: 2)))) {
      return settings.accessToken.trim();
    }
    if (settings.refreshToken.trim().isEmpty) {
      throw StateError(
          'Google Drive authorization expired. Connect Google Drive again.');
    }
    final cloud = CloudSyncSettings.load();
    if (cloud.apiBaseUrl.trim().isNotEmpty &&
        settings.clientSecret.trim().isEmpty) {
      final base = CloudSyncSettings.normalizeApiBaseUrl(cloud.apiBaseUrl);
      final response = await http.post(
        Uri.parse('$base/api/google-drive/refresh'),
        headers: const {'Content-Type': 'application/json; charset=utf-8'},
        body: jsonEncode({'refreshToken': settings.refreshToken.trim()}),
      );
      final decoded = response.body.trim().isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(decoded['error']?.toString() ??
            'Google Drive token refresh failed.');
      }
      final next = settings.copyWith(
        accessToken: decoded['accessToken']?.toString() ?? '',
        accessTokenExpiresAt: DateTime.tryParse(
            decoded['accessTokenExpiresAt']?.toString() ?? ''),
      );
      await saveSettings(next);
      return next.accessToken;
    }
    final body = <String, String>{
      'client_id': settings.clientId.trim(),
      'refresh_token': settings.refreshToken.trim(),
      'grant_type': 'refresh_token',
    };
    final response = await http.post(
      Uri.parse('https://oauth2.googleapis.com/token'),
      headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
      body: body,
    );
    var decoded = response.body.trim().isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;
    if ((response.statusCode < 200 || response.statusCode >= 300) &&
        decoded['error']?.toString() == 'invalid_request' &&
        settings.clientSecret.trim().isNotEmpty) {
      body['client_secret'] = settings.clientSecret.trim();
      final retry = await http.post(
        Uri.parse('https://oauth2.googleapis.com/token'),
        headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
        body: body,
      );
      decoded = _decodeResponse(retry);
    } else if (response.statusCode < 200 || response.statusCode >= 300) {
      decoded = _decodeResponse(response);
    }
    final next = settings.copyWith(
      accessToken: decoded['access_token'] as String,
      accessTokenExpiresAt: DateTime.now().add(Duration(
          seconds: ((decoded['expires_in'] as num?)?.toInt() ?? 3600) - 60)),
    );
    await saveSettings(next);
    return next.accessToken;
  }

  static Future<String> _ensureFolder(String token, String name,
      {String? parentId}) async {
    final existing = await _findFolder(token, name, parentId: parentId);
    if (existing != null) return existing;
    final metadata = <String, Object?>{
      'name': name,
      'mimeType': 'application/vnd.google-apps.folder',
      if (parentId != null) 'parents': <String>[parentId],
    };
    final created = await _drivePostJson(token, 'files', metadata,
        query: const {'fields': 'id'});
    return created['id'] as String;
  }

  static Future<String?> _findFolder(String token, String name,
      {String? parentId}) async {
    final escapedName = _driveQueryEscape(name);
    final parent = parentId == null ? '' : " and '$parentId' in parents";
    final query =
        "mimeType = 'application/vnd.google-apps.folder' and name = '$escapedName' and trashed = false$parent";
    final list = await _driveGet(token, 'files', <String, String>{
      'q': query,
      'fields': 'files(id,name)',
      'pageSize': '1',
    });
    final files = (list['files'] as List?) ?? const [];
    if (files.isNotEmpty) {
      return (files.first as Map)['id'] as String;
    }
    return null;
  }

  static Future<bool> _fileExists(
      String token, String folderId, String name) async {
    final query =
        "name = '${_driveQueryEscape(name)}' and '$folderId' in parents and trashed = false";
    final list = await _driveGet(token, 'files', <String, String>{
      'q': query,
      'fields': 'files(id)',
      'pageSize': '1',
    });
    return ((list['files'] as List?) ?? const []).isNotEmpty;
  }

  static Future<bool> _hasDailyForDate(
      GoogleDriveBackupSettings settings, DateTime date) async {
    try {
      final token = await _accessToken(settings);
      final folderId = settings.folderId.trim();
      if (folderId.isEmpty) return false;
      final dailyId = await _ensureFolder(token, 'Daily', parentId: folderId);
      return _fileExists(
          token, dailyId, 'ventio_daily_${_dateStamp(date)}.vtb');
    } catch (_) {
      return false;
    }
  }

  static Future<String> _uploadFile(
      String token, String folderId, String fileName, List<int> bytes) async {
    final boundary = 'ventio_${DateTime.now().microsecondsSinceEpoch}';
    final metadata = jsonEncode(<String, Object?>{
      'name': fileName,
      'parents': <String>[folderId],
    });
    final body = <int>[
      ...utf8.encode(
          '--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n$metadata\r\n'),
      ...utf8.encode('--$boundary\r\nContent-Type: application/zip\r\n\r\n'),
      ...bytes,
      ...utf8.encode('\r\n--$boundary--\r\n'),
    ];
    final response = await http.post(
      Uri.parse(
          'https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id'),
      headers: <String, String>{
        'Authorization': 'Bearer $token',
        'Content-Type': 'multipart/related; boundary=$boundary',
      },
      body: body,
    );
    return _decodeResponse(response)['id'] as String;
  }

  static Future<void> _trimBackups(
      String token, String folderId, int keep) async {
    final query =
        "'$folderId' in parents and trashed = false and name contains '.vtb'";
    final list = await _driveGet(token, 'files', <String, String>{
      'q': query,
      'fields': 'files(id,name,createdTime)',
      'pageSize': '1000',
      'orderBy': 'createdTime desc',
    });
    final files =
        List<Map<String, dynamic>>.from((list['files'] as List?) ?? const []);
    final limit = keep.clamp(1, 1000).toInt();
    for (final file in files.skip(limit)) {
      await http.delete(
        Uri.parse('https://www.googleapis.com/drive/v3/files/${file['id']}'),
        headers: <String, String>{'Authorization': 'Bearer $token'},
      );
    }
  }

  static Future<Map<String, dynamic>> _driveGet(
      String token, String path, Map<String, String> query) async {
    final response = await http.get(
      Uri.https('www.googleapis.com', '/drive/v3/$path', query),
      headers: <String, String>{'Authorization': 'Bearer $token'},
    );
    return _decodeResponse(response);
  }

  static Future<Map<String, dynamic>> _drivePostJson(
    String token,
    String path,
    Map<String, Object?> body, {
    Map<String, String> query = const {},
  }) async {
    final response = await http.post(
      Uri.https('www.googleapis.com', '/drive/v3/$path', query),
      headers: <String, String>{
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json; charset=utf-8',
      },
      body: jsonEncode(body),
    );
    return _decodeResponse(response);
  }

  static Map<String, dynamic> _decodeResponse(http.Response response) {
    final decoded = response.body.trim().isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }
    final error = decoded['error'];
    if (error is Map && error['message'] != null) {
      throw StateError(error['message'].toString());
    }
    if (error is String) {
      throw StateError(error);
    }
    throw StateError('Google Drive request failed (${response.statusCode}).');
  }

  static List<int> _buildZipBytes(
      String backupJson, DateTime generatedAt, String reason) {
    final backupBytes = utf8.encode(backupJson);
    final manifest = jsonEncode(<String, Object?>{
      'app': 'Ventio',
      'type': 'google-drive-backup',
      'reason': reason,
      'generatedAt': generatedAt.toIso8601String(),
      'content': 'backup.json',
    });
    final manifestBytes = utf8.encode(manifest);
    final archive = Archive()
      ..addFile(ArchiveFile('backup.json', backupBytes.length, backupBytes))
      ..addFile(
          ArchiveFile('manifest.json', manifestBytes.length, manifestBytes));
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
    if (woy == 53 && DateTime(date.year, 12, 31).weekday < DateTime.thursday) {
      return 1;
    }
    return woy;
  }

  static String _driveQueryEscape(String value) =>
      value.replaceAll(r'\', r'\\').replaceAll("'", r"\'");

  static String _randomSessionId() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}
