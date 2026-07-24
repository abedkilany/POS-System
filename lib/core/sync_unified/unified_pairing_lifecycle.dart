import '../../models/app_identity.dart';

class UnifiedPairingClaimPayload {
  const UnifiedPairingClaimPayload({
    required this.storeId,
    required this.branchId,
    required this.hostDeviceId,
    this.deviceId = '',
    this.deviceToken = '',
    this.transport = '',
  });

  final String storeId;
  final String branchId;
  final String hostDeviceId;
  final String deviceId;
  final String deviceToken;
  final String transport;
}

class UnifiedPairingLifecycle {
  const UnifiedPairingLifecycle._();

  static String? validateSameStoreClaim(
    AppIdentity current,
    UnifiedPairingClaimPayload claim, {
    String label = 'Pairing code',
  }) {
    if (!current.isClient || current.hostDeviceId.trim().isEmpty) return null;

    final mismatches = <String>[];
    if (current.storeId.trim().toUpperCase() !=
        claim.storeId.trim().toUpperCase()) {
      mismatches.add('Store ID');
    }
    if (current.branchId.trim().toUpperCase() !=
        claim.branchId.trim().toUpperCase()) {
      mismatches.add('Branch ID');
    }
    if (current.hostDeviceId.trim().toUpperCase() !=
        claim.hostDeviceId.trim().toUpperCase()) {
      mismatches.add('Host ID');
    }
    if (mismatches.isEmpty) return null;
    return '$label belongs to a different Store (${mismatches.join(', ')}). Use the current Host pairing code.';
  }

  static AppIdentity buildClientIdentity(
    AppIdentity current, {
    required UnifiedPairingClaimPayload claim,
    required SyncMode syncMode,
    required String activeTransport,
  }) {
    return current.copyWith(
      storeId: claim.storeId,
      branchId: claim.branchId,
      deviceId: claim.deviceId.trim().isNotEmpty
          ? claim.deviceId.trim()
          : current.deviceId,
      hostDeviceId: claim.hostDeviceId,
      deviceRole: DeviceRole.client,
      syncMode: syncMode,
      activeSyncTransport: activeTransport,
      deviceToken: claim.deviceToken.trim().isNotEmpty
          ? claim.deviceToken.trim()
          : current.deviceToken,
      updatedAt: DateTime.now(),
    );
  }
}
