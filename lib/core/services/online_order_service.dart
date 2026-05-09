import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/online_order.dart';
import '../app_config.dart';
import 'central_auth_service.dart';
import 'cloud_sync_service.dart';

class OnlineOrderApiResult {
  const OnlineOrderApiResult({required this.ok, required this.message, this.order, this.orders = const []});

  final bool ok;
  final String message;
  final OnlineOrder? order;
  final List<OnlineOrder> orders;
}

class OnlineOrderService {
  OnlineOrderService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  CloudSyncSettings _platformSettings() {
    final loaded = CloudSyncSettings.load();
    final base = loaded.apiBaseUrl.trim().isEmpty ? AppConfig.platformBaseUrl : loaded.apiBaseUrl.trim();
    return loaded.copyWith(apiBaseUrl: base);
  }

  Map<String, String> _headers() => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (CentralAuthService.sessionToken.trim().isNotEmpty) 'Authorization': 'Bearer ${CentralAuthService.sessionToken.trim()}',
      };

  Future<OnlineOrderApiResult> listStoreOrders(String storeId) async {
    final settings = _platformSettings();
    try {
      final uri = settings.endpoint('/api/orders').replace(queryParameters: {'storeId': storeId});
      final response = await _client.get(uri, headers: _headers()).timeout(const Duration(seconds: 15));
      return _parseOrderList(response);
    } catch (error) {
      return OnlineOrderApiResult(ok: false, message: 'تعذر جلب طلبات المتجر: $error');
    }
  }

  Future<OnlineOrderApiResult> listMyOrders() async {
    final settings = _platformSettings();
    try {
      final uri = settings.endpoint('/api/orders').replace(queryParameters: {'customer': 'me'});
      final response = await _client.get(uri, headers: _headers()).timeout(const Duration(seconds: 15));
      return _parseOrderList(response);
    } catch (error) {
      return OnlineOrderApiResult(ok: false, message: 'تعذر جلب طلباتي: $error');
    }
  }

  Future<OnlineOrderApiResult> placeOrder(OnlineOrder order) async {
    final settings = _platformSettings();
    try {
      final response = await _client
          .post(
            settings.endpoint('/api/orders'),
            headers: _headers(),
            body: jsonEncode(order.toJson()),
          )
          .timeout(const Duration(seconds: 15));
      return _parseSingleOrder(response);
    } catch (error) {
      return OnlineOrderApiResult(ok: false, message: 'تعذر إرسال الطلب: $error');
    }
  }

  Future<OnlineOrderApiResult> updateStatus({required String orderId, required String status}) async {
    final settings = _platformSettings();
    try {
      final response = await _client
          .post(
            settings.endpoint('/api/orders/status'),
            headers: _headers(),
            body: jsonEncode({'orderId': orderId, 'status': status}),
          )
          .timeout(const Duration(seconds: 15));
      return _parseSingleOrder(response);
    } catch (error) {
      return OnlineOrderApiResult(ok: false, message: 'تعذر تحديث حالة الطلب: $error');
    }
  }

  OnlineOrderApiResult _parseOrderList(http.Response response) {
    final decoded = _decode(response);
    if (decoded.$1 != null) return OnlineOrderApiResult(ok: false, message: decoded.$1!);
    final json = decoded.$2!;
    final rawOrders = json['orders'];
    final orders = rawOrders is List
        ? rawOrders.map((item) => OnlineOrder.fromJson(Map<String, dynamic>.from(item as Map))).toList()
        : <OnlineOrder>[];
    return OnlineOrderApiResult(ok: true, message: json['message']?.toString() ?? 'OK', orders: orders);
  }

  OnlineOrderApiResult _parseSingleOrder(http.Response response) {
    final decoded = _decode(response);
    if (decoded.$1 != null) return OnlineOrderApiResult(ok: false, message: decoded.$1!);
    final json = decoded.$2!;
    final rawOrder = json['order'];
    return OnlineOrderApiResult(
      ok: true,
      message: json['message']?.toString() ?? 'OK',
      order: rawOrder is Map ? OnlineOrder.fromJson(Map<String, dynamic>.from(rawOrder)) : null,
    );
  }

  (String?, Map<String, dynamic>?) _decode(http.Response response) {
    try {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300 || decoded['ok'] != true) {
        return (decoded['error']?.toString() ?? 'Request failed: ${response.statusCode}', null);
      }
      return (null, decoded);
    } catch (_) {
      return ('Server returned invalid JSON: ${response.statusCode}', null);
    }
  }
}
