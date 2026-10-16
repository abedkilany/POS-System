part of 'app_store.dart';

final class _RecoveryDomain implements RecoveryDomainPort {
  _RecoveryDomain(this._store)
      : _recoveryFiles = RecoveryFileService(
          identityProvider: () => _store.runtime.identity,
        );
  final AppStore _store;
  final RecoveryFileService _recoveryFiles;

  @override
  bool get hasLocalStoreData =>
      _AppStoreSplitAccessAuth(_store).hasLocalStoreData;

  @override
  BackupSummary get currentBackupSummary => _store.currentBackupSummary;

  @override
  BackupImportPlan inspectBackupJson(String rawJson) =>
      _store.inspectBackupJson(rawJson);

  @override
  BackupValidationResult validateBackupJson(String rawJson) =>
      _store.validateBackupJson(rawJson);

  @override
  bool isEncryptedBackupJson(String rawJson) =>
      _store.isEncryptedBackupJson(rawJson);

  @override
  String extractBackupJsonFromLocalBackupArchiveBytes(List<int> bytes) =>
      _store.extractBackupJsonFromLocalBackupArchiveBytes(bytes);

  @override
  String decryptBackupJson(String encryptedBackup, String password) =>
      _store.decryptBackupJson(encryptedBackup, password);

  @override
  Future<String> exportEncryptedBackupJson(String password) =>
      _store._exportEncryptedBackupJson(password);

  @override
  Future<String> exportBackupJson() =>
      AppStoreRecoveryService(_store).exportBackupJson();

  @override
  Future<void> mergeBackupJson(
    String rawJson, {
    bool markSynced = false,
  }) =>
      _store._mergeBackupJson(rawJson, markSynced: markSynced);
  @override
  Future<void> importBackupJson(
    String rawJson, {
    Set<String>? selectedSectionIds,
  }) =>
      AppStoreRecoveryService(_store).importBackupJson(
        rawJson,
        selectedSectionIds: selectedSectionIds,
      );
  @override
  String exportRecoveryFileJson({String controlPlaneApiUrl = ''}) {
    _store.security.requirePermission(AppPermission.backupExport);
    return _recoveryFiles.exportRecoveryFileJson(
      controlPlaneApiUrl: controlPlaneApiUrl,
    );
  }

  @override
  Future<Map<String, dynamic>> exportUnifiedSnapshotEnvelope({
    String kind = 'full_store',
    int maxItemsPerChunk = 250,
    int maxEncodedPayloadBytes = 900 * 1024,
  }) =>
      _AppStoreSplitBackupRecoveryPart2(_store).exportUnifiedSnapshotEnvelope(
        kind: kind,
        maxItemsPerChunk: maxItemsPerChunk,
        maxEncodedPayloadBytes: maxEncodedPayloadBytes,
      );

  @override
  Map<String, String> parseRecoveryFileJson(String rawJson) =>
      _recoveryFiles.parseRecoveryFileJson(rawJson);

  @override
  Future<void> factoryResetLocalDevice({
    bool enforcePermission = true,
    bool preserveAdminUsers = false,
  }) =>
      _AppStoreSplitPersistenceSyncCorePart3(_store).factoryResetLocalDevice(
        enforcePermission: enforcePermission,
        preserveAdminUsers: preserveAdminUsers,
      );

  @override
  Future<void> resetBusinessData({bool keepStoreProfile = true}) =>
      _AppStoreSplitPersistenceSyncCorePart2(_store)
          .resetBusinessData(keepStoreProfile: keepStoreProfile);
}
