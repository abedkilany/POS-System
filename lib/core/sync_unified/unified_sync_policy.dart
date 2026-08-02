import '../../models/app_identity.dart';

/// Shared role/transport policy for unified sync decisions.
///
/// Transport adapters should keep network details only. Decisions about whether
/// the current device may act as a Host/Client for a transport belong here so
/// LAN and Direct follow the same role rules.
class UnifiedSyncPolicy {
  const UnifiedSyncPolicy._();

  static bool isLanHostAllowed(
    AppIdentity identity, {
    required bool setupComplete,
    required bool isHostModeEnabled,
  }) {
    return identity.isHost && setupComplete && isHostModeEnabled;
  }

  static bool isLanClientAllowed(
    AppIdentity identity, {
    required bool setupComplete,
    required bool isClientModeEnabled,
  }) {
    return identity.isClient &&
        identity.activeSyncTransportNormalized == 'lan' &&
        setupComplete &&
        isClientModeEnabled;
  }

  static bool isLanAllowedForCurrentRole(
    AppIdentity identity, {
    required bool setupComplete,
    required bool isHostModeEnabled,
    required bool isClientModeEnabled,
  }) {
    if (isLanHostAllowed(
      identity,
      setupComplete: setupComplete,
      isHostModeEnabled: isHostModeEnabled,
    )) {
      return true;
    }
    return isLanClientAllowed(
      identity,
      setupComplete: setupComplete,
      isClientModeEnabled: isClientModeEnabled,
    );
  }

  static bool isDirectHostAllowed(AppIdentity identity) => identity.isHost;

  static bool isDirectClientAllowed(AppIdentity identity) {
    return identity.isClient &&
        identity.activeSyncTransportNormalized == 'direct';
  }

  static bool isDirectAllowedForCurrentRole(AppIdentity identity) {
    return isDirectHostAllowed(identity) || isDirectClientAllowed(identity);
  }

  static bool canCreateLanPairingCode(
    AppIdentity identity, {
    required bool setupComplete,
    required bool isHostModeEnabled,
  }) {
    return isLanHostAllowed(
      identity,
      setupComplete: setupComplete,
      isHostModeEnabled: isHostModeEnabled,
    );
  }

  static bool canClaimLanPairingCode(AppIdentity identity) {
    return !identity.isHost;
  }

  static bool canRebuildFromLanSnapshot(AppIdentity identity) {
    return !identity.isHost;
  }

  static bool shouldTrackRemoteSnapshotGeneration(AppIdentity identity) {
    return identity.isClient;
  }

  static bool canCreateDirectPairingCode(
    AppIdentity identity, {
    required bool settingsEnabled,
    required bool hasApiBaseUrl,
  }) {
    return identity.isHost && settingsEnabled && hasApiBaseUrl;
  }

  static bool canClaimDirectPairingCode(AppIdentity identity) {
    return identity.isClient;
  }

  static bool canCheckDirectPairingStatus(AppIdentity identity) {
    return false;
  }

  static bool canUseDirectTransport(
    AppIdentity identity, {
    required bool isConfigured,
  }) {
    return isDirectAllowedForCurrentRole(identity) && isConfigured;
  }

  static bool canRequestDirectSnapshot(
    AppIdentity identity, {
    required bool isConfigured,
  }) {
    return isDirectClientAllowed(identity) && isConfigured;
  }

  static bool canRebuildFromDirectSnapshot(
    AppIdentity identity, {
    required bool isConfigured,
  }) {
    return isDirectClientAllowed(identity) && isConfigured;
  }

  static bool canSuspendDirectDevices(AppIdentity identity) {
    return identity.isHost;
  }

  static bool canRevokeDirectDevices(AppIdentity identity) {
    return identity.isHost;
  }

  static bool canRemoveDirectDevices(AppIdentity identity) {
    return identity.isHost;
  }

  static bool canRequestDirectHostTransfer(AppIdentity identity) {
    return identity.isClient;
  }

  static bool canApproveDirectHostTransfer(AppIdentity identity) {
    return identity.isHost;
  }

  static bool canRepairDirectDeviceLinks(AppIdentity identity) {
    return identity.isHost;
  }
}
