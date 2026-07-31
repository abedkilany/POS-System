import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/sync_unified/sync_transport_adapter.dart';
import 'package:ventio/core/services/direct_sync_settings.dart';
import 'package:ventio/models/app_identity.dart';

void main() {
  test('recognizes direct as a supported unified transport kind', () {
    expect(UnifiedSyncTransportKind.values,
        contains(UnifiedSyncTransportKind.direct));
  });

  test('preserves direct as the selected device transport', () {
    final identity = AppIdentity.defaults(
      deviceId: 'DV-DIRECT',
      platform: AppPlatformType.windows,
    ).copyWith(activeSyncTransport: 'direct');

    expect(identity.activeSyncTransportNormalized, 'direct');
    expect(identity.transportType, 'direct');
  });

  test('derives the runtime STUN host from the API URL', () {
    const settings = DirectSyncSettings(
      apiBaseUrl: 'https://api.example.test',
      peerDeviceId: 'DV-HOST',
    );

    expect(
      settings.iceServersForApiBaseUrl(settings.apiBaseUrl),
      equals(const [
        {'urls': 'stun:api.example.test:3478'},
      ]),
    );
  });

  test('builds multiple STUN and TURN ICE server entries', () {
    const settings = DirectSyncSettings(
      apiBaseUrl: 'https://api.example.test',
      peerDeviceId: 'DV-HOST',
      stunServers: <String>[
        'stun:one.example.test:3478',
        'stun:two.example.test:3478',
      ],
      turnServers: <DirectIceServer>[
        DirectIceServer(
          urls: <String>['turn:relay.example.test:3478?transport=udp'],
          username: 'turn-user',
          credential: 'turn-secret',
        ),
      ],
      iceTransportPolicy: 'relay',
      iceCandidatePoolSize: 4,
    );

    expect(settings.iceServers, hasLength(3));
    expect(settings.iceServers[0]['urls'], 'stun:one.example.test:3478');
    expect(settings.iceServers[1]['urls'], 'stun:two.example.test:3478');
    expect(settings.iceServers[2]['username'], 'turn-user');
    expect(settings.iceServers[2]['credential'], 'turn-secret');
    expect(
      settings.rtcConfigurationForApiBaseUrl(settings.apiBaseUrl),
      containsPair('iceTransportPolicy', 'relay'),
    );
  });

  test('keeps legacy stunServer settings compatible', () {
    const settings = DirectSyncSettings(
      apiBaseUrl: 'https://api.example.test',
      peerDeviceId: 'DV-HOST',
      stunServer: 'stun:legacy.example.test:3478',
    );

    expect(
        settings.iceServers,
        equals(const [
          {'urls': 'stun:legacy.example.test:3478'},
        ]));
  });
}
