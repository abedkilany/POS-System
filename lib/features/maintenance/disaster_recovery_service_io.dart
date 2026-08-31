import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

import '../../core/services/app_logging_service.dart';
import '../../core/services/local_auto_backup_service.dart';
import '../../core/services/local_database_service.dart';
import '../../data/app_store.dart';
import '../../models/user_role.dart';
import 'phase10_health_service.dart';

class DisasterRecoveryVerificationResult {
  const DisasterRecoveryVerificationResult({
    required this.ok,
    required this.message,
    this.path = '',
    this.generatedAt,
    this.backupVersion = 0,
  });

  final bool ok;
  final String message;
  final String path;
  final DateTime? generatedAt;
  final int backupVersion;
}

class DisasterRecoveryReadiness {
  const DisasterRecoveryReadiness({
    required this.ready,
    required this.checks,
  });

  final bool ready;
  final Map<String, bool> checks;
}

/// Phase 10 disaster-recovery coordinator.
///
/// Recovery never starts by guessing whether a backup is usable. This service
/// creates encrypted checkpoints and performs a non-destructive restore drill:
/// unzip -> manifest validation -> AES-GCM decrypt -> Ventio backup validation.
class DisasterRecoveryService {
  const DisasterRecoveryService(this.store);

  final AppStore store;

  static const String _lastCheckpointKey =
      'phase10_last_recovery_checkpoint_v1';
  static const String _lastVerificationKey =
      'phase10_last_recovery_verification_v1';
  static const String _lastVerifiedPathKey =
      'phase10_last_recovery_verified_path_v1';

  Future<DisasterRecoveryReadiness> assessReadiness() async {
    store.requirePermission(AppPermission.maintenanceView);
    final health = await Phase10HealthService(store).run(deep: false);
    final settings = await LocalAutoBackupService.loadSettings();
    final lastSuccess = LocalAutoBackupService.lastSuccessAt();
    final backupRecent = lastSuccess != null &&
        DateTime.now().difference(lastSuccess).inHours <= 48;
    final lastVerified = DateTime.tryParse(
      LocalDatabaseService.getString(_lastVerificationKey) ?? '',
    );
    final verificationRecent = lastVerified != null &&
        DateTime.now().difference(lastVerified).inDays <= 30;
    final checks = <String, bool>{
      'hostDevice': store.appIdentity.isHost,
      'healthGate': health.criticalCount == 0,
      'recoveryKey': store.appIdentity.recoveryKey.trim().length >= 8,
      'localBackupEnabled': settings.enabled,
      'recentBackup': backupRecent,
      'recentRestoreDrill': verificationRecent,
    };
    return DisasterRecoveryReadiness(
      ready: checks.values.every((value) => value),
      checks: Map<String, bool>.unmodifiable(checks),
    );
  }

  Future<DisasterRecoveryVerificationResult> createVerifiedCheckpoint() async {
    store.requirePermission(AppPermission.maintenanceManage);
    store.requirePermission(AppPermission.backupExport);
    if (!store.appIdentity.isHost) {
      throw StateError('Disaster recovery checkpoints are created on the Host device.');
    }
    final recoveryKey = store.appIdentity.recoveryKey.trim();
    if (recoveryKey.length < 8) {
      throw StateError('A valid Store Recovery Key is required.');
    }

    final Object created = await LocalAutoBackupService.createBackupNow(
      store,
      reason: 'disaster_recovery_checkpoint',
    );
    if (created is! File) {
      throw StateError('Local recovery checkpoint did not return a file.');
    }
    final verified = await _verifyFile(created);
    if (!verified.ok) {
      throw StateError('Recovery checkpoint verification failed: ${verified.message}');
    }
    final now = DateTime.now().toUtc();
    await LocalDatabaseService.setString(_lastCheckpointKey, now.toIso8601String());
    await _markVerified(created.path, now);
    await _audit(
      action: 'recovery_checkpoint_created',
      summary: 'Verified disaster-recovery checkpoint created',
      details: 'path=${created.path}; backupVersion=${verified.backupVersion}',
    );
    return verified;
  }

  Future<DisasterRecoveryVerificationResult> verifyLatestBackup() async {
    store.requirePermission(AppPermission.maintenanceManage);
    store.requirePermission(AppPermission.backupExport);
    if (!store.appIdentity.isHost) {
      throw StateError('Local backup verification is managed by the Host device.');
    }
    final file = await _latestBackupFile();
    if (file == null) {
      return const DisasterRecoveryVerificationResult(
        ok: false,
        message: 'No local .vtb backup file was found.',
      );
    }
    final verified = await _verifyFile(file);
    if (verified.ok) {
      final now = DateTime.now().toUtc();
      await _markVerified(file.path, now);
      await _audit(
        action: 'recovery_backup_verified',
        summary: 'Disaster-recovery restore drill passed',
        details: 'path=${file.path}; backupVersion=${verified.backupVersion}',
      );
    } else {
      await _audit(
        action: 'recovery_backup_verification_failed',
        summary: 'Disaster-recovery restore drill failed',
        details: 'path=${file.path}; reason=${verified.message}',
      );
    }
    return verified;
  }

  Future<void> _markVerified(String path, DateTime now) async {
    await LocalDatabaseService.setString(
        _lastVerificationKey, now.toIso8601String());
    await LocalDatabaseService.setString(_lastVerifiedPathKey, path);
  }

  Future<File?> _latestBackupFile() async {
    final settings = await LocalAutoBackupService.loadSettings();
    final root = Directory(settings.locationPath.trim().isEmpty
        ? await LocalAutoBackupService.defaultLocationPath()
        : settings.locationPath.trim());
    if (!await root.exists()) return null;
    final files = <File>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File && entity.path.toLowerCase().endsWith('.vtb')) {
        files.add(entity);
      }
    }
    if (files.isEmpty) return null;
    files.sort((a, b) {
      final aTime = a.statSync().modified;
      final bTime = b.statSync().modified;
      return bTime.compareTo(aTime);
    });
    return files.first;
  }

  Future<DisasterRecoveryVerificationResult> _verifyFile(File file) async {
    try {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        return DisasterRecoveryVerificationResult(
          ok: false,
          message: 'Backup file is empty.',
          path: file.path,
        );
      }
      final archive = ZipDecoder().decodeBytes(bytes, verify: true);
      ArchiveFile? backupEntry;
      ArchiveFile? manifestEntry;
      for (final entry in archive.files) {
        if (entry.name == 'backup.json') backupEntry = entry;
        if (entry.name == 'manifest.json') manifestEntry = entry;
      }
      if (backupEntry == null || manifestEntry == null) {
        return DisasterRecoveryVerificationResult(
          ok: false,
          message: 'Backup archive is missing backup.json or manifest.json.',
          path: file.path,
        );
      }
      final manifest = jsonDecode(
        utf8.decode(_archiveBytes(manifestEntry)),
      );
      if (manifest is! Map ||
          manifest['encrypted'] != true ||
          manifest['cipher']?.toString().toLowerCase() != 'aes-256-gcm') {
        return DisasterRecoveryVerificationResult(
          ok: false,
          message: 'Backup manifest does not declare the required encrypted format.',
          path: file.path,
        );
      }
      final encryptedJson = utf8.decode(_archiveBytes(backupEntry)).trim();
      if (!store.isEncryptedBackupJson(encryptedJson)) {
        return DisasterRecoveryVerificationResult(
          ok: false,
          message: 'Backup payload is not a recognized encrypted Ventio backup.',
          path: file.path,
        );
      }
      final plain = store.decryptBackupJson(
        encryptedJson,
        store.appIdentity.recoveryKey.trim(),
      );
      final validation = store.validateBackupJson(plain);
      if (!validation.isValid || validation.summary == null) {
        return DisasterRecoveryVerificationResult(
          ok: false,
          message: validation.errorMessage ?? 'Backup payload validation failed.',
          path: file.path,
        );
      }
      final summary = validation.summary!;
      return DisasterRecoveryVerificationResult(
        ok: true,
        message: 'Encrypted backup passed the non-destructive restore drill.',
        path: file.path,
        generatedAt: summary.generatedAt,
        backupVersion: summary.version,
      );
    } catch (error) {
      return DisasterRecoveryVerificationResult(
        ok: false,
        message: 'Backup verification failed: $error',
        path: file.path,
      );
    }
  }

  List<int> _archiveBytes(ArchiveFile entry) {
    return entry.content;
  }

  Future<void> _audit({
    required String action,
    required String summary,
    required String details,
  }) {
    return AuditLogger.record(
      entityType: 'disaster_recovery',
      entityId: store.appIdentity.storeId,
      action: action,
      summary: summary,
      details: details,
      userId: store.activeUser?.id ?? '',
      userName: store.activeUser?.username ?? '',
      storeId: store.appIdentity.storeId,
      branchId: store.appIdentity.branchId,
      sessionId: store.deviceId,
      traceId: store.deviceId,
      deviceId: store.deviceId,
      sourceModule: 'maintenance',
      isImportant: true,
    );
  }
}
