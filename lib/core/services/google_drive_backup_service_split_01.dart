part of 'google_drive_backup_service.dart';

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
