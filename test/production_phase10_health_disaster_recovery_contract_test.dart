import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _source(String path) => File(path).readAsStringSync();

void main() {
  test('Phase 10 composes all production integrity gates', () {
    final health =
        _source('lib/features/maintenance/phase10_health_service.dart');
    final maintenance =
        _source('lib/features/maintenance/maintenance_service.dart');

    expect(health, contains("deep ? 'integrity_check' : 'quick_check'"));
    expect(health, contains('PRAGMA foreign_key_check;'));
    expect(health, contains("journalMode == 'wal'"));
    expect(health, contains('AuditLogger.verifyIntegrity()'));
    expect(health, contains('verifyLocalBusinessDataIntegrity()'));
    expect(health, contains('InventoryTraceabilityService(db).verifyIntegrity'));
    expect(health, contains('AccountingProductionIntegrityService(db).audit()'));
    expect(health, contains('_guardedCheck('));
    expect(maintenance, contains('Phase10HealthService(store).run'));
    expect(maintenance, contains("'phase10ProductionHealth': phase10.toJson()"));
  });

  test('Phase 10 recovery checkpoint performs a non-destructive restore drill', () {
    final recovery = _source(
        'lib/features/maintenance/disaster_recovery_service_io.dart');
    final backup =
        _source('lib/core/services/local_auto_backup_service_io.dart');

    expect(recovery, contains('AppPermission.backupExport'));
    expect(recovery, contains("reason: 'disaster_recovery_checkpoint'"));
    expect(recovery, contains('decodeBytes(bytes, verify: true)'));
    expect(recovery, contains("entry.name == 'manifest.json'"));
    expect(recovery, contains("entry.name == 'backup.json'"));
    expect(recovery, contains('store.decryptBackupJson'));
    expect(recovery, contains('store.validateBackupJson(plain)'));
    expect(recovery, contains("entityType: 'disaster_recovery'"));
    expect(backup, contains('Recovery checkpoints'));
    expect(backup, contains('ventio_recovery_checkpoint'));
    expect(backup, contains('await _trimBackups(recoveryDir, 5);'));
  });

  test('backup restore runs Phase 10 post-restore validation', () {
    final settings =
        _source('lib/features/settings/settings_page_backup.dart');
    expect(settings, contains('Phase10HealthService(store).run(deep: true)'));
    expect(settings, contains('backup_imported_health_verified'));
    expect(settings, contains('backup_imported_health_warning'));
  });
}
