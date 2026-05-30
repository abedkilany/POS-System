import 'package:flutter_test/flutter_test.dart';

import 'package:ventio/models/app_identity.dart';
import 'package:ventio/models/sync_change.dart';
import 'package:ventio/models/sync_queue_item.dart';

void main() {
  group('Stage 5 Host-authoritative sync contract', () {
    test('Client may store both configs but exposes one active transport', () {
      final identity = AppIdentity.defaults(
        deviceId: 'client-1',
        platform: AppPlatformType.windows,
      ).copyWith(
        deviceRole: DeviceRole.client,
        syncMode: SyncMode.cloudConnected,
        hostDeviceId: 'host-1',
        activeSyncTransport: 'lan',
      );

      expect(identity.isClient, isTrue);
      expect(identity.activeSyncTransportNormalized, 'lan');
      expect(identity.transportType, 'lan');
    });

    test('Cloud Client relay ACK state is submitted, not confirmed', () {
      final now = DateTime.utc(2026, 1, 1);
      final item = SyncQueueItem(
        id: 'cmd-1-cloud_host',
        changeId: 'cmd-1',
        target: 'cloud_host',
        status: 'submitted',
        attempts: 1,
        createdAt: now,
        updatedAt: now,
      );

      expect(item.isSubmitted, isTrue);
      expect(item.isSynced, isFalse);
      expect(item.isReadyToSend, isFalse);
    });

    test('Host authoritative event has a different eventId and sourceCommandId', () {
      final acceptedAt = DateTime.utc(2026, 1, 1, 12);
      final clientDraft = SyncChange(
        id: 'cmd-client-123',
        entityType: 'product',
        entityId: 'p1',
        operation: 'create',
        deviceId: 'client-1',
        createdAt: acceptedAt.subtract(const Duration(minutes: 1)),
        payload: const {
          'id': 'p1',
          'code': 'P-1',
          '_syncV2': {
            'kind': 'draftCommand',
            'requestId': 'cmd-client-123',
            'eventId': '',
            'sourceDeviceId': 'client-1',
          },
        },
        sequence: 0,
      );
      final authoritative = clientDraft.copyWith(
        id: 'evt-host-456',
        deviceId: 'host-1',
        createdAt: acceptedAt,
        sequence: 42,
        payload: const {
          'id': 'p1',
          'code': 'P-1',
          '_syncV2': {
            'kind': 'authoritativeEvent',
            'requestId': 'cmd-client-123',
            'eventId': 'evt-host-456',
            'sourceCommandId': 'cmd-client-123',
            'acceptedByHostDeviceId': 'host-1',
          },
        },
      );

      final meta = Map<String, dynamic>.from(authoritative.payload['_syncV2'] as Map);
      expect(authoritative.id, isNot(clientDraft.id));
      expect(authoritative.sequence, greaterThan(0));
      expect(meta['kind'], 'authoritativeEvent');
      expect(meta['eventId'], authoritative.id);
      expect(meta['sourceCommandId'], clientDraft.id);
      expect(meta['requestId'], clientDraft.id);
    });

    test('received ACK is separate from Host confirmation state', () {
      final now = DateTime.utc(2026, 1, 1);
      final delivered = SyncQueueItem(
        id: 'evt-1-cloud',
        changeId: 'evt-1',
        target: 'cloud',
        status: 'synced',
        attempts: 1,
        createdAt: now,
        updatedAt: now,
      );
      final submittedDraft = SyncQueueItem(
        id: 'cmd-1-cloud_host',
        changeId: 'cmd-1',
        target: 'cloud_host',
        status: 'submitted',
        attempts: 1,
        createdAt: now,
        updatedAt: now,
      );

      expect(delivered.isSynced, isTrue);
      expect(submittedDraft.isSubmitted, isTrue);
      expect(submittedDraft.isSynced, isFalse);
    });
  });
}
