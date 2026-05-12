import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ventio/core/services/cloud_sync_service.dart';
import 'package:ventio/data/app_store.dart';

void main() {
  group('Offline/online behavior', () {
    const settings = CloudSyncSettings(enabled: true, apiBaseUrl: 'https://sync.test', apiToken: 'token');

    test('offline connection returns a failed result instead of throwing', () async {
      final service = CloudSyncService(
        AppStore(),
        client: MockClient((_) async => throw const SocketExceptionForTest('No internet')),
      );

      final result = await service.testConnection(settings);

      expect(result.ok, isFalse);
      expect(result.message, contains('failed'));
    });

    test('online connection can recover after an offline result', () async {
      var online = false;
      final service = CloudSyncService(
        AppStore(),
        client: MockClient((_) async {
          if (!online) throw TimeoutException('offline');
          return http.Response('{"ok":true}', 200);
        }),
      );

      final offlineResult = await service.testConnection(settings);
      online = true;
      final onlineResult = await service.testConnection(settings);

      expect(offlineResult.ok, isFalse);
      expect(onlineResult.ok, isTrue);
    });
  });
}

class SocketExceptionForTest implements Exception {
  const SocketExceptionForTest(this.message);
  final String message;
  @override
  String toString() => 'SocketException: $message';
}
