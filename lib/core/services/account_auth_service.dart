import 'dart:convert';

import 'package:http/http.dart' as http;

import 'cloud_sync_service.dart';
import 'local_database_service.dart';

class AccountAuthResult {
  const AccountAuthResult({
    required this.ok,
    this.message = '',
    this.accountId = '',
    this.storeId = '',
    this.subscriptionStatus = '',
    this.trialEndsAt,
    this.devicesLimit,
  });

  final bool ok;
  final String message;
  final String accountId;
  final String storeId;
  final String subscriptionStatus;
  final DateTime? trialEndsAt;
  final int? devicesLimit;

  factory AccountAuthResult.fromJson(Map<String, dynamic> json) {
    return AccountAuthResult(
      ok: json['ok'] == true,
      message: (json['message'] ?? json['error'] ?? '').toString(),
      accountId: (json['accountId'] ?? json['account_id'] ?? '').toString(),
      storeId: (json['storeId'] ?? json['store_id'] ?? '').toString(),
      subscriptionStatus:
          (json['subscriptionStatus'] ?? json['subscription_status'] ?? '')
              .toString(),
      trialEndsAt: DateTime.tryParse(
        (json['trialEndsAt'] ?? json['trial_ends_at'] ?? '').toString(),
      ),
      devicesLimit: int.tryParse(
        (json['devicesLimit'] ?? json['devices_limit'] ?? '').toString(),
      ),
    );
  }
}

class AccountAuthCache {
  const AccountAuthCache({
    required this.mode,
    required this.accountId,
    required this.storeId,
    required this.subscriptionStatus,
    this.trialEndsAt,
    this.devicesLimit,
    this.lastVerifiedAt,
  });

  static const key = 'account_auth_cache_v1';

  final String mode;
  final String accountId;
  final String storeId;
  final String subscriptionStatus;
  final DateTime? trialEndsAt;
  final int? devicesLimit;
  final DateTime? lastVerifiedAt;

  Map<String, dynamic> toJson() => {
        'mode': mode,
        'accountId': accountId,
        'storeId': storeId,
        'subscriptionStatus': subscriptionStatus,
        'trialEndsAt': trialEndsAt?.toIso8601String() ?? '',
        'devicesLimit': devicesLimit,
        'lastVerifiedAt': lastVerifiedAt?.toIso8601String() ?? '',
      };

  static AccountAuthCache? load() {
    final raw = LocalDatabaseService.getString(key);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      return AccountAuthCache(
        mode: (json['mode'] ?? '').toString(),
        accountId: (json['accountId'] ?? '').toString(),
        storeId: (json['storeId'] ?? '').toString(),
        subscriptionStatus: (json['subscriptionStatus'] ?? '').toString(),
        trialEndsAt: DateTime.tryParse((json['trialEndsAt'] ?? '').toString()),
        devicesLimit: int.tryParse((json['devicesLimit'] ?? '').toString()),
        lastVerifiedAt:
            DateTime.tryParse((json['lastVerifiedAt'] ?? '').toString()),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(AccountAuthCache cache) async {
    await LocalDatabaseService.setString(key, jsonEncode(cache.toJson()));
  }
}

class AccountAuthService {
  AccountAuthService({http.Client? client}) : _client = client ?? http.Client();

  static const _defaultApiBaseUrl = String.fromEnvironment(
    'PUBLIC_API_BASE_URL',
    defaultValue: 'https://ventio.duckdns.org',
  );

  final http.Client _client;

  Uri _endpoint(String path) {
    final settings = CloudSyncSettings.load();
    final baseUrl = settings.apiBaseUrl.trim().isEmpty
        ? _defaultApiBaseUrl
        : settings.apiBaseUrl.trim();
    return settings.copyWith(apiBaseUrl: baseUrl).endpoint(path);
  }

  Future<AccountAuthResult> register({
    required String username,
    required String password,
    required String fullName,
    required String storeName,
  }) async {
    final response = await _client.post(
      _endpoint('/api/auth/register'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username.trim(),
        'password': password,
        'fullName': fullName.trim(),
        'storeName': storeName.trim().isEmpty ? 'My Store' : storeName.trim(),
        'trialDays': 14,
      }),
    );
    return _decode(response);
  }

  Future<AccountAuthResult> login({
    required String username,
    required String password,
  }) async {
    final response = await _client.post(
      _endpoint('/api/auth/login'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username.trim(),
        'password': password,
      }),
    );
    return _decode(response);
  }

  AccountAuthResult _decode(http.Response response) {
    Map<String, dynamic> body = <String, dynamic>{};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) body = Map<String, dynamic>.from(decoded);
    } catch (_) {
      body = {'ok': false, 'error': response.body};
    }
    final result = AccountAuthResult.fromJson(body);
    if (response.statusCode >= 200 && response.statusCode < 300 && result.ok) {
      return result;
    }
    return AccountAuthResult(
      ok: false,
      message: result.message.isEmpty
          ? 'Online account request failed (${response.statusCode}).'
          : result.message,
      accountId: result.accountId,
      storeId: result.storeId,
      subscriptionStatus: result.subscriptionStatus,
      trialEndsAt: result.trialEndsAt,
      devicesLimit: result.devicesLimit,
    );
  }

  static Future<void> cacheOnlineResult(
    AccountAuthResult result, {
    required String mode,
  }) async {
    await AccountAuthCache.save(
      AccountAuthCache(
        mode: mode,
        accountId: result.accountId,
        storeId: result.storeId,
        subscriptionStatus: result.subscriptionStatus,
        trialEndsAt: result.trialEndsAt,
        devicesLimit: result.devicesLimit,
        lastVerifiedAt: DateTime.now(),
      ),
    );
  }
}
