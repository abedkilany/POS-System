import '../../models/app_identity.dart';

/// Shared role/transport policy for unified sync decisions.
///
/// Transport adapters should keep network details only. Decisions about whether
/// the current device may act as a Host/Client for a transport belong here so
/// LAN and Cloud follow the same role rules.
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

  static bool isCloudHostAllowed(AppIdentity identity) {
    return identity.isHost && identity.isCloudEnabled;
  }

  static bool isCloudClientAllowed(AppIdentity identity) {
    return identity.isClient &&
        identity.activeSyncTransportNormalized == 'cloud';
  }

  static bool isCloudAllowedForCurrentRole(AppIdentity identity) {
    return isCloudHostAllowed(identity) || isCloudClientAllowed(identity);
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

  static bool canCreateCloudPairingCode(
    AppIdentity identity, {
    required bool settingsEnabled,
    required bool hasApiBaseUrl,
  }) {
    return isCloudHostAllowed(identity) && settingsEnabled && hasApiBaseUrl;
  }

  static bool canClaimCloudPairingCode(AppIdentity identity) {
    return !identity.isHost;
  }

  static bool canCheckCloudPairingStatus(AppIdentity identity) {
    return identity.isHost;
  }

  static bool canUseCloudTransport(
    AppIdentity identity, {
    required bool isConfigured,
  }) {
    return isCloudAllowedForCurrentRole(identity) && isConfigured;
  }

  static bool canRequestCloudSnapshot(
    AppIdentity identity, {
    required bool isConfigured,
  }) {
    return isCloudClientAllowed(identity) && isConfigured;
  }

  static bool canRebuildFromCloudSnapshot(
    AppIdentity identity, {
    required bool isConfigured,
  }) {
    return isCloudClientAllowed(identity) && isConfigured;
  }

  static bool canSuspendCloudDevices(AppIdentity identity) {
    return identity.isHost;
  }

  static bool canRevokeCloudDevices(AppIdentity identity) {
    return identity.isHost;
  }

  static bool canRemoveCloudDevices(AppIdentity identity) {
    return identity.isHost;
  }

  static bool canRequestCloudHostTransfer(AppIdentity identity) {
    return identity.isClient;
  }

  static bool canApproveCloudHostTransfer(AppIdentity identity) {
    return identity.isHost;
  }

  static bool canRepairCloudDeviceLinks(AppIdentity identity) {
    return identity.isHost;
  }
}
