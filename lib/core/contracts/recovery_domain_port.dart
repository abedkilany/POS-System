import '../../models/backup_models.dart';

abstract class RecoveryDomainPort {
  bool get hasLocalStoreData;
  BackupSummary get currentBackupSummary;
  BackupImportPlan inspectBackupJson(String rawJson);
  BackupValidationResult validateBackupJson(String rawJson);
  bool isEncryptedBackupJson(String rawJson);
  String extractBackupJsonFromLocalBackupArchiveBytes(List<int> bytes);
  String decryptBackupJson(String encryptedBackup, String password);
  Future<String> exportEncryptedBackupJson(String password);
  Future<String> exportBackupJson();
  Future<void> mergeBackupJson(
    String rawJson, {
    bool markSynced = false,
  });
  Future<void> importBackupJson(
    String rawJson, {
    Set<String>? selectedSectionIds,
  });
  String exportRecoveryFileJson({String controlPlaneApiUrl = ''});
  Future<Map<String, dynamic>> exportUnifiedSnapshotEnvelope({
    String kind = 'full_store',
    int maxItemsPerChunk = 250,
    int maxEncodedPayloadBytes = 900 * 1024,
  });
  Map<String, String> parseRecoveryFileJson(String rawJson);
  Future<void> factoryResetLocalDevice({
    bool enforcePermission = true,
    bool preserveAdminUsers = false,
  });
  Future<void> resetBusinessData({bool keepStoreProfile = true});
}
