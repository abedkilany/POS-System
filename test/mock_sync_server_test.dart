import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ventio/core/services/cloud_sync_service.dart';
import 'package:ventio/data/app_store.dart';

void main() {
  group('Mock cloud sync server', () {
    CloudSyncSettings settings() => const CloudSyncSettings(
          enabled: true,
          apiBaseUrl: 'https://sync.test',
          apiToken: 'token',
        );

    test('reports healthy cloud API responses as online', () async {
      final service = CloudSyncService(
        AppStore(),
        client: MockClient((request) async {
          expect(request.url.path, '/api/health');
          expect(request.headers['Authorization'], 'Bearer token');
          return http.Response('{"ok":true}', 200);
        }),
      );

      final result = await service.testConnection(settings());

      expect(result.ok, isTrue);
      expect(result.message, isNotEmpty);
    });

    test('reports server errors as offline/unhealthy', () async {
      final service = CloudSyncService(
        AppStore(),
        client:
            MockClient((request) async => http.Response('maintenance', 503)),
      );

      final result = await service.testConnection(settings());

      expect(result.ok, isFalse);
      expect(result.message, contains('503'));
    });

    test('reports network exceptions without crashing', () async {
      final service = CloudSyncService(
        AppStore(),
        client:
            MockClient((request) async => throw TimeoutException('offline')),
      );

      final result = await service.testConnection(settings());

      expect(result.ok, isFalse);
      expect(result.message, isNotEmpty);
    });

    test('parses online device list from mock server', () async {
      final now = DateTime.now().toUtc().toIso8601String();
      final service = CloudSyncService(
        AppStore(),
        client: MockClient((request) async {
          expect(request.url.path, '/api/sync/devices');
          return http.Response(
            jsonEncode({
              'devices': [
                {
                  'deviceId': 'host-1',
                  'deviceName': 'Main PC',
                  'platform': 'windows',
                  'role': 'host',
                  'transport': 'cloud',
                  'lastSeenAt': now,
                  'appVersion': 'test',
                }
              ]
            }),
            200,
          );
        }),
      );

      final devices = await service.listDevices(settings());

      expect(devices, hasLength(1));
      expect(devices.single.deviceId, 'host-1');
      expect(devices.single.isOnline, isTrue);
    });

    test('detects stale host heartbeat', () async {
      final stale = DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 5))
          .toIso8601String();
      final service = CloudSyncService(
        AppStore(),
        client: MockClient((request) async => http.Response(
              jsonEncode({
                'lastSeenAt': stale,
                'hostDeviceId': 'host-1',
                'hostDeviceName': 'Main PC'
              }),
              200,
            )),
      );

      final status = await service.getHostHeartbeatStatus(settings());

      expect(status.cloudReachable, isTrue);
      expect(status.hostReachable, isFalse);
      expect(status.message, isNotEmpty);
    });
  });
}
