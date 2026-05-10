import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/online_order.dart';
import '../../models/platform_store.dart';
import '../../models/product.dart';
import '../app_config.dart';
import 'cloud_sync_service.dart';

class MarketplaceApiException implements Exception {
  const MarketplaceApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class MarketplaceApiService {
  MarketplaceApiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Uri _endpoint(String path, [Map<String, String>? query]) {
    final loaded = CloudSyncSettings.load();
    var base = loaded.apiBaseUrl.trim().isEmpty ? AppConfig.platformBaseUrl : loaded.apiBaseUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    final normalized = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$base$normalized');
    return query == null ? uri : uri.replace(queryParameters: {...uri.queryParameters, ...query});
  }


  Future<Map<String, dynamic>> publishStore({
    required String storeId,
    required String branchId,
    required Map<String, dynamic> store,
    required List<Product> products,
  }) async {
    final response = await _client
        .post(
          _endpoint('/marketplace/publish-store'),
          headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
          body: jsonEncode({
            'storeId': storeId,
            'branchId': branchId,
            'store': store,
            'products': products.map((p) => {
                  ...p.toJson(),
                  'storeId': storeId,
                  'branchId': branchId,
                  'isPublic': true,
                  'isAvailableOnline': p.isActive && !p.isDeleted,
                }).toList(),
          }),
        )
        .timeout(const Duration(seconds: 30));
    return _decode(response);
  }

  Future<List<PlatformStore>> fetchStores() async {
    final response = await _client.get(_endpoint('/marketplace/stores')).timeout(const Duration(seconds: 15));
    final decoded = _decode(response);
    final list = decoded['stores'];
    if (list is! List) return const <PlatformStore>[];
    return list.whereType<Map>().map((e) => PlatformStore.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<List<Product>> fetchStoreProducts(String storeId, {String branchId = 'main'}) async {
    final response = await _client.get(_endpoint('/marketplace/stores/${Uri.encodeComponent(storeId)}/products', {'branchId': branchId})).timeout(const Duration(seconds: 15));
    final decoded = _decode(response);
    final list = decoded['products'];
    if (list is! List) return const <Product>[];
    return list.whereType<Map>().map((e) => Product.fromJson(Map<String, dynamic>.from(e))).where((p) => p.isActive && !p.isDeleted).toList();
  }

  Future<OnlineOrder> createOrder({
    required String storeId,
    required String customerUserId,
    required String customerName,
    required String customerPhone,
    required String deliveryAddress,
    required List<OnlineOrderItem> items,
    String notes = '',
  }) async {
    final response = await _client
        .post(
          _endpoint('/marketplace/orders'),
          headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
          body: jsonEncode({
            'storeId': storeId,
            'customerUserId': customerUserId,
            'customerName': customerName,
            'customerPhone': customerPhone,
            'deliveryAddress': deliveryAddress,
            'notes': notes,
            'items': items.map((e) => e.toJson()).toList(),
            'paymentMethod': 'cash_on_delivery',
          }),
        )
        .timeout(const Duration(seconds: 15));
    final decoded = _decode(response);
    final raw = decoded['order'];
    if (raw is! Map) throw const MarketplaceApiException('لم يرجع السيرفر تفاصيل الطلب.');
    return OnlineOrder.fromJson(Map<String, dynamic>.from(raw));
  }



  Future<List<OnlineOrder>> fetchStoreOrders(String storeId) async {
    final response = await _client.get(_endpoint('/marketplace/orders', {'storeId': storeId})).timeout(const Duration(seconds: 15));
    final decoded = _decode(response);
    final list = decoded['orders'];
    if (list is! List) return const <OnlineOrder>[];
    return list.whereType<Map>().map((e) => OnlineOrder.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<OnlineOrder> updateOrderStatus({
    required String orderId,
    required String status,
  }) async {
    final response = await _client
        .post(
          _endpoint('/marketplace/orders/${Uri.encodeComponent(orderId)}/status'),
          headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
          body: jsonEncode({'status': status}),
        )
        .timeout(const Duration(seconds: 15));
    final decoded = _decode(response);
    final raw = decoded['order'];
    if (raw is! Map) throw const MarketplaceApiException('لم يرجع السيرفر تفاصيل الطلب.');
    return OnlineOrder.fromJson(Map<String, dynamic>.from(raw));
  }

  Future<List<OnlineOrder>> fetchCustomerOrders(String customerUserId) async {
    final response = await _client.get(_endpoint('/marketplace/orders', {'customerUserId': customerUserId})).timeout(const Duration(seconds: 15));
    final decoded = _decode(response);
    final list = decoded['orders'];
    if (list is! List) return const <OnlineOrder>[];
    return list.whereType<Map>().map((e) => OnlineOrder.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> decoded = <String, dynamic>{};
    try {
      decoded = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw MarketplaceApiException('استجابة غير مفهومة من السيرفر: ${response.statusCode}');
    }
    if (response.statusCode < 200 || response.statusCode >= 300 || decoded['ok'] != true) {
      throw MarketplaceApiException(decoded['error']?.toString() ?? 'خطأ من السيرفر: ${response.statusCode}');
    }
    return decoded;
  }
}
