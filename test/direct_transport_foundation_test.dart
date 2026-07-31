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
}
