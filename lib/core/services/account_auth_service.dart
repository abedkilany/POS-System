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
    this.branchId = '',
    this.subscriptionStatus = '',
    this.username = '',
    this.storeSlug = '',
    this.storeName = '',
    this.loginName = '',
    this.accountType = '',
    this.trialEndsAt,
    this.devicesLimit,
    this.adminToken = '',
  });

  final bool ok;
  final String message;
  final String accountId;
  final String storeId;
  final String branchId;
  final String subscriptionStatus;
  final String username;
  final String storeSlug;
  final String storeName;
  final String loginName;
  final String accountType;
  final DateTime? trialEndsAt;
  final int? devicesLimit;
  final String adminToken;

  factory AccountAuthResult.fromJson(Map<String, dynamic> json) {
    return AccountAuthResult(
      ok: json['ok'] == true,
      message: (json['message'] ?? json['error'] ?? '').toString(),
      accountId: (json['accountId'] ?? json['account_id'] ?? '').toString(),
      storeId: (json['storeId'] ?? json['store_id'] ?? '').toString(),
      branchId: (json['branchId'] ?? json['branch_id'] ?? '').toString(),
      subscriptionStatus:
          (json['subscriptionStatus'] ?? json['subscription_status'] ?? '')
              .toString(),
      username: (json['username'] ?? '').toString(),
      storeSlug: (json['storeSlug'] ?? json['store_slug'] ?? '').toString(),
      storeName: (json['storeName'] ?? json['store_name'] ?? '').toString(),
      loginName: (json['loginName'] ?? json['login_name'] ?? '').toString(),
      accountType:
          (json['accountType'] ?? json['account_type'] ?? '').toString(),
      trialEndsAt: DateTime.tryParse(
        (json['trialEndsAt'] ?? json['trial_ends_at'] ?? '').toString(),
      ),
      devicesLimit: int.tryParse(
        (json['devicesLimit'] ?? json['devices_limit'] ?? '').toString(),
      ),
      adminToken: (json['adminToken'] ?? json['admin_token'] ?? '').toString(),
    );
  }
}

class AccountAuthCache {
  const AccountAuthCache({
    required this.mode,
    required this.accountId,
    required this.storeId,
    required this.branchId,
    required this.subscriptionStatus,
    this.username = '',
    this.storeSlug = '',
    this.storeName = '',
    this.loginName = '',
    this.accountType = '',
    this.trialEndsAt,
    this.devicesLimit,
    this.adminToken = '',
    this.lastVerifiedAt,
  });

  static const key = 'account_auth_cache_v1';

  final String mode;
  final String accountId;
  final String storeId;
  final String branchId;
  final String subscriptionStatus;
  final String username;
  final String storeSlug;
  final String storeName;
  final String loginName;
  final String accountType;
  final DateTime? trialEndsAt;
  final int? devicesLimit;
  final String adminToken;
  final DateTime? lastVerifiedAt;

  Map<String, dynamic> toJson() => {
        'mode': mode,
        'accountId': accountId,
        'storeId': storeId,
        'branchId': branchId,
        'subscriptionStatus': subscriptionStatus,
        'username': username,
        'storeSlug': storeSlug,
        'storeName': storeName,
        'loginName': loginName,
        'accountType': accountType,
        'trialEndsAt': trialEndsAt?.toIso8601String() ?? '',
        'devicesLimit': devicesLimit,
        'lastVerifiedAt': lastVerifiedAt?.toIso8601String() ?? '',
        'adminToken': adminToken,
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
        branchId: (json['branchId'] ?? '').toString(),
        subscriptionStatus: (json['subscriptionStatus'] ?? '').toString(),
        username: (json['username'] ?? '').toString(),
        storeSlug: (json['storeSlug'] ?? '').toString(),
        storeName: (json['storeName'] ?? '').toString(),
        loginName: (json['loginName'] ?? '').toString(),
        accountType: (json['accountType'] ?? '').toString(),
        trialEndsAt: DateTime.tryParse((json['trialEndsAt'] ?? '').toString()),
        devicesLimit: int.tryParse((json['devicesLimit'] ?? '').toString()),
        lastVerifiedAt:
            DateTime.tryParse((json['lastVerifiedAt'] ?? '').toString()),
        adminToken: (json['adminToken'] ?? '').toString(),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(AccountAuthCache cache) async {
    await LocalDatabaseService.setString(key, jsonEncode(cache.toJson()));
  }

  static Future<void> clear() async {
    await LocalDatabaseService.deleteString(key);
  }
}

class AdminSubscribersResult {
  const AdminSubscribersResult({
    required this.ok,
    this.message = '',
    this.summary = const <String, dynamic>{},
    this.subscribers = const <AdminSubscriber>[],
  });

  final bool ok;
  final String message;
  final Map<String, dynamic> summary;
  final List<AdminSubscriber> subscribers;
}

class AdminSubscriber {
  const AdminSubscriber({
    required this.accountId,
    required this.storeId,
    required this.subscriptionId,
    required this.username,
    required this.fullName,
    required this.storeSlug,
    required this.storeName,
    required this.plan,
    required this.subscriptionStatus,
    required this.accountStatus,
    required this.devicesLimit,
    required this.deviceCount,
    this.trialEndsAt,
    this.createdAt,
    this.lastSeenAt,
  });

  final String accountId;
  final String storeId;
  final String subscriptionId;
  final String username;
  final String fullName;
  final String storeSlug;
  final String storeName;
  final String plan;
  final String subscriptionStatus;
  final String accountStatus;
  final int devicesLimit;
  final int deviceCount;
  final DateTime? trialEndsAt;
  final DateTime? createdAt;
  final DateTime? lastSeenAt;

  String get loginName => storeSlug.isEmpty ? username : '$username@$storeSlug';

  factory AdminSubscriber.fromJson(Map<String, dynamic> json) {
    return AdminSubscriber(
      accountId: (json['account_id'] ?? json['accountId'] ?? '').toString(),
      storeId: (json['store_id'] ?? json['storeId'] ?? '').toString(),
      subscriptionId:
          (json['subscription_id'] ?? json['subscriptionId'] ?? '').toString(),
      username: (json['username'] ?? '').toString(),
      fullName: (json['full_name'] ?? json['fullName'] ?? '').toString(),
      storeSlug: (json['store_slug'] ?? json['storeSlug'] ?? '').toString(),
      storeName: (json['store_name'] ?? json['storeName'] ?? '').toString(),
      plan: (json['plan'] ?? '').toString(),
      subscriptionStatus:
          (json['subscription_status'] ?? json['subscriptionStatus'] ?? '')
              .toString(),
      accountStatus:
          (json['account_status'] ?? json['accountStatus'] ?? '').toString(),
      devicesLimit: int.tryParse(
              (json['devices_limit'] ?? json['devicesLimit'] ?? '0')
                  .toString()) ??
          0,
      deviceCount: int.tryParse(
              (json['device_count'] ?? json['deviceCount'] ?? '0')
                  .toString()) ??
          0,
      trialEndsAt: DateTime.tryParse(
          (json['trial_ends_at'] ?? json['trialEndsAt'] ?? '').toString()),
      createdAt: DateTime.tryParse(
          (json['account_created_at'] ?? json['createdAt'] ?? '').toString()),
      lastSeenAt: DateTime.tryParse(
          (json['last_seen_at'] ?? json['lastSeenAt'] ?? '').toString()),
    );
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
        'username': username.trim().toLowerCase(),
        'password': password,
        'fullName': fullName.trim(),
        'storeName': storeName.trim().toLowerCase(),
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
        'username': username.trim().toLowerCase(),
        'password': password,
      }),
    );
    return _decode(response);
  }

  Future<AdminSubscribersResult> fetchAdminSubscribers(
      {required String adminToken}) async {
    if (adminToken.trim().isEmpty) {
      return const AdminSubscribersResult(
          ok: false,
          message: 'Admin token is missing. Sign in as admin@ventio.');
    }
    final response = await _client.get(
      _endpoint('/api/admin/subscribers'),
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer ${adminToken.trim()}',
      },
    );
    Map<String, dynamic> body = <String, dynamic>{};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) body = Map<String, dynamic>.from(decoded);
    } catch (_) {
      body = {'ok': false, 'error': response.body};
    }
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        body['ok'] != true) {
      return AdminSubscribersResult(
        ok: false,
        message: (body['error'] ??
                body['message'] ??
                'Failed to load subscribers (${response.statusCode}).')
            .toString(),
      );
    }
    final rawSubscribers = body['subscribers'];
    final subscribers = rawSubscribers is List
        ? rawSubscribers
            .whereType<Map>()
            .map((item) =>
                AdminSubscriber.fromJson(Map<String, dynamic>.from(item)))
            .toList(growable: false)
        : const <AdminSubscriber>[];
    final summary = body['summary'] is Map
        ? Map<String, dynamic>.from(body['summary'] as Map)
        : const <String, dynamic>{};
    return AdminSubscribersResult(
        ok: true, summary: summary, subscribers: subscribers);
  }

  Future<AccountAuthResult> updateAdminSubscriber({
    required String adminToken,
    required AdminSubscriber subscriber,
    required String username,
    required String fullName,
    required String storeName,
    required String storeSlug,
    required String accountStatus,
    required String plan,
    required String subscriptionStatus,
    required int devicesLimit,
    required DateTime? trialEndsAt,
  }) async {
    if (adminToken.trim().isEmpty) {
      return const AccountAuthResult(
          ok: false,
          message: 'Admin token is missing. Sign in as admin@ventio.');
    }
    final response = await _client.patch(
      _endpoint('/api/admin/subscribers'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${adminToken.trim()}',
      },
      body: jsonEncode({
        'accountId': subscriber.accountId,
        'username': username.trim().toLowerCase(),
        'fullName': fullName.trim(),
        'storeName': storeName.trim(),
        'storeSlug': storeSlug.trim().toLowerCase(),
        'accountStatus': accountStatus.trim().toLowerCase(),
        'plan': plan.trim().toLowerCase(),
        'subscriptionStatus': subscriptionStatus.trim().toLowerCase(),
        'devicesLimit': devicesLimit,
        'trialEndsAt': trialEndsAt?.toUtc().toIso8601String() ?? '',
      }),
    );
    return _decode(response);
  }

  Future<AccountAuthResult> deleteAdminSubscriber({
    required String adminToken,
    required AdminSubscriber subscriber,
  }) async {
    if (adminToken.trim().isEmpty) {
      return const AccountAuthResult(
          ok: false,
          message: 'Admin token is missing. Sign in as admin@ventio.');
    }
    final response = await _client.delete(
      _endpoint('/api/admin/subscribers'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${adminToken.trim()}',
      },
      body: jsonEncode({'accountId': subscriber.accountId}),
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
      branchId: result.branchId,
      subscriptionStatus: result.subscriptionStatus,
      username: result.username,
      storeSlug: result.storeSlug,
      storeName: result.storeName,
      loginName: result.loginName,
      accountType: result.accountType,
      trialEndsAt: result.trialEndsAt,
      devicesLimit: result.devicesLimit,
      adminToken: result.adminToken,
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
        branchId: result.branchId,
        subscriptionStatus: result.subscriptionStatus,
        username: result.username,
        storeSlug: result.storeSlug,
        storeName: result.storeName,
        loginName: result.loginName,
        accountType: result.accountType,
        trialEndsAt: result.trialEndsAt,
        devicesLimit: result.devicesLimit,
        adminToken: result.adminToken,
        lastVerifiedAt: DateTime.now(),
      ),
    );
  }
}
