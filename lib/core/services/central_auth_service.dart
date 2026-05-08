import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/app_user.dart';
import 'cloud_sync_service.dart';
import 'local_database_service.dart';

class CentralAuthResult {
  const CentralAuthResult({
    required this.ok,
    required this.message,
    this.user,
    this.sessionToken = '',
    this.platformStore,
    this.storeMember,
    this.customerProfile,
    this.driverProfile,
    this.storeToken = '',
  });

  final bool ok;
  final String message;
  final AppUser? user;
  final String sessionToken;
  final Map<String, dynamic>? platformStore;
  final Map<String, dynamic>? storeMember;
  final Map<String, dynamic>? customerProfile;
  final Map<String, dynamic>? driverProfile;
  final String storeToken;
}


class CentralAuthService {
  CentralAuthService({http.Client? client}) : _client = client ?? http.Client();

  static const _authSessionTokenKey = 'central_auth_session_token_v1';
  final http.Client _client;

  static String get sessionToken => LocalDatabaseService.getString(_authSessionTokenKey) ?? '';
  static Future<void> saveSessionToken(String token) async => LocalDatabaseService.setString(_authSessionTokenKey, token.trim());
  static Future<void> clearSessionToken() async => LocalDatabaseService.setString(_authSessionTokenKey, '');

  Map<String, String> _headers(CloudSyncSettings settings) => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (settings.apiToken.trim().isNotEmpty) 'Authorization': 'Bearer ${settings.apiToken.trim()}',
      };

  Future<CentralAuthResult> login({
    required String username,
    required String password,
  }) async {
    final settings = CloudSyncSettings.load();
    if (settings.apiBaseUrl.trim().isEmpty) {
      return const CentralAuthResult(ok: false, message: 'Central auth API URL is not configured.');
    }
    try {
      final response = await _client
          .post(
            settings.endpoint('/api/auth/login'),
            headers: _headers(settings),
            body: jsonEncode({'username': username.trim(), 'password': password}),
          )
          .timeout(const Duration(seconds: 15));
      return _parseAuthResponse(response);
    } catch (error) {
      return CentralAuthResult(ok: false, message: 'Central login failed: $error');
    }
  }

  Future<CentralAuthResult> register({
    required String fullName,
    required String username,
    required String password,
    String accountType = 'platform_user',
    String phone = '',
    String email = '',
  }) async {
    final settings = CloudSyncSettings.load();
    if (settings.apiBaseUrl.trim().isEmpty) {
      return const CentralAuthResult(ok: false, message: 'Central auth API URL is not configured.');
    }
    try {
      final response = await _client
          .post(
            settings.endpoint('/api/auth/register'),
            headers: _headers(settings),
            body: jsonEncode({
              'fullName': fullName.trim(),
              'username': username.trim(),
              'password': password,
              'accountType': accountType,
              'phone': phone.trim(),
              'email': email.trim(),
            }),
          )
          .timeout(const Duration(seconds: 15));
      return _parseAuthResponse(response);
    } catch (error) {
      return CentralAuthResult(ok: false, message: 'Central registration failed: $error');
    }
  }


  Future<CentralAuthResult> createStore({
    required String userId,
    required String storeName,
    String phone = '',
    String address = '',
  }) async {
    final settings = CloudSyncSettings.load();
    if (settings.apiBaseUrl.trim().isEmpty) {
      return const CentralAuthResult(ok: false, message: 'Central auth API URL is not configured.');
    }
    try {
      final response = await _client
          .post(
            settings.endpoint('/api/store/create'),
            headers: _headers(settings),
            body: jsonEncode({'userId': userId, 'storeName': storeName.trim(), 'phone': phone.trim(), 'address': address.trim()}),
          )
          .timeout(const Duration(seconds: 15));
      return _parseAuthResponse(response);
    } catch (error) {
      return CentralAuthResult(ok: false, message: 'Central create store failed: $error');
    }
  }

  Future<CentralAuthResult> linkStore({
    required String userId,
    required String storeId,
    required String storeToken,
  }) async {
    final settings = CloudSyncSettings.load();
    if (settings.apiBaseUrl.trim().isEmpty) {
      return const CentralAuthResult(ok: false, message: 'Central auth API URL is not configured.');
    }
    try {
      final response = await _client
          .post(
            settings.endpoint('/api/store/link'),
            headers: _headers(settings),
            body: jsonEncode({'userId': userId, 'storeId': storeId.trim(), 'storeToken': storeToken.trim()}),
          )
          .timeout(const Duration(seconds: 15));
      return _parseAuthResponse(response);
    } catch (error) {
      return CentralAuthResult(ok: false, message: 'Central link store failed: $error');
    }
  }

  CentralAuthResult _parseAuthResponse(http.Response response) {
    Map<String, dynamic> decoded = <String, dynamic>{};
    try {
      decoded = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      return CentralAuthResult(ok: false, message: 'Central auth returned invalid JSON: ${response.statusCode}');
    }
    if (response.statusCode < 200 || response.statusCode >= 300 || decoded['ok'] != true) {
      return CentralAuthResult(ok: false, message: decoded['error']?.toString() ?? 'Central auth failed: ${response.statusCode}');
    }
    final rawUser = decoded['user'];
    if (rawUser is! Map) return const CentralAuthResult(ok: false, message: 'Central auth did not return a user.');
    return CentralAuthResult(
      ok: true,
      message: decoded['message']?.toString() ?? 'OK',
      user: AppUser.fromJson(Map<String, dynamic>.from(rawUser)),
      sessionToken: decoded['sessionToken']?.toString() ?? '',
      platformStore: decoded['platformStore'] is Map ? Map<String, dynamic>.from(decoded['platformStore'] as Map) : null,
      storeMember: decoded['storeMember'] is Map ? Map<String, dynamic>.from(decoded['storeMember'] as Map) : null,
      customerProfile: decoded['customerProfile'] is Map ? Map<String, dynamic>.from(decoded['customerProfile'] as Map) : null,
      driverProfile: decoded['driverProfile'] is Map ? Map<String, dynamic>.from(decoded['driverProfile'] as Map) : null,
      storeToken: decoded['storeToken']?.toString() ?? '',
    );
  }
}
