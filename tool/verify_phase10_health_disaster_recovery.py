from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]

checks = []

def add(name, ok):
    checks.append((name, bool(ok)))

health = (ROOT / 'lib/features/maintenance/phase10_health_service.dart').read_text()
recovery = (ROOT / 'lib/features/maintenance/disaster_recovery_service_io.dart').read_text()
recovery_stub = (ROOT / 'lib/features/maintenance/disaster_recovery_service_stub.dart').read_text()
local_backup = (ROOT / 'lib/core/services/local_auto_backup_service_io.dart').read_text()
maint_service = (ROOT / 'lib/features/maintenance/maintenance_service.dart').read_text()
maint_page = (ROOT / 'lib/features/maintenance/maintenance_page.dart').read_text()
settings_backup = (ROOT / 'lib/features/settings/settings_page_backup.dart').read_text()
settings_page = (ROOT / 'lib/features/settings/settings_page.dart').read_text()

add('phase10 health service exists', 'class Phase10HealthService' in health)
add('quick/full sqlite integrity check', "deep ? 'integrity_check' : 'quick_check'" in health)
add('foreign key check', 'PRAGMA foreign_key_check;' in health)
add('WAL durability check', "journalMode == 'wal'" in health)
add('FULL synchronous durability check', "synchronous == '2'" in health and "synchronous == '3'" in health)
add('foreign keys enabled check', "foreignKeys == '1'" in health)
add('audit chain health integration', 'AuditLogger.verifyIntegrity()' in health)
add('business reference health integration', 'verifyLocalBusinessDataIntegrity()' in health)
add('inventory traceability health integration', 'InventoryTraceabilityService(db).verifyIntegrity' in health)
add('accounting production health integration', 'AccountingProductionIntegrityService(db).audit()' in health)
add('recovery identity health integration', "id: 'phase10_recovery_identity'" in health)
add('maintenance service runs phase10 gate', 'Phase10HealthService(store).run' in maint_service)
add('maintenance summary carries phase10 report', "'phase10ProductionHealth': phase10.toJson()" in maint_service)
add('production health dashboard card', "tr.text('production_health')" in maint_page)
add('dashboard exposes phase10 critical count', "summary.counts['phase10Critical']" in maint_page)
add('disaster recovery service exists', 'class DisasterRecoveryService' in recovery)
add('web-safe recovery stub exists', 'class DisasterRecoveryService' in recovery_stub)
add('readiness requires health gate', "'healthGate': health.criticalCount == 0" in recovery)
add('readiness requires recovery key', "'recoveryKey': store.appIdentity.recoveryKey.trim().length >= 8" in recovery)
add('readiness requires recent backup', "'recentBackup': backupRecent" in recovery)
add('readiness requires recent restore drill', "'recentRestoreDrill': verificationRecent" in recovery)
add('checkpoint requires backup export permission', 'AppPermission.backupExport' in recovery)
add('checkpoint restricted to host', "if (!store.appIdentity.isHost)" in recovery)
add('checkpoint uses dedicated recovery reason', "reason: 'disaster_recovery_checkpoint'" in recovery)
add('local backup writes dedicated recovery directory', 'Recovery checkpoints' in local_backup)
add('local backup writes timestamped recovery file', "ventio_recovery_checkpoint" in local_backup)
add('recovery checkpoint retention bounded', 'await _trimBackups(recoveryDir, 5);' in local_backup)
add('restore drill verifies zip crc', 'decodeBytes(bytes, verify: true)' in recovery)
add('restore drill requires manifest and payload', "entry.name == 'backup.json'" in recovery and "entry.name == 'manifest.json'" in recovery)
add('restore drill requires AES-256-GCM', "aes-256-gcm" in recovery)
add('restore drill decrypts with recovery key', 'store.decryptBackupJson' in recovery and 'store.appIdentity.recoveryKey.trim()' in recovery)
add('restore drill validates Ventio backup payload', 'store.validateBackupJson(plain)' in recovery)
add('recovery actions append audit events', "entityType: 'disaster_recovery'" in recovery and 'AuditLogger.record' in recovery)
add('maintenance exposes recovery readiness action', '_showRecoveryReadiness' in maint_page)
add('maintenance exposes checkpoint action', '_createRecoveryCheckpoint' in maint_page)
add('maintenance exposes restore drill action', '_verifyLatestRecoveryBackup' in maint_page)
add('settings imports phase10 post-restore verifier', 'phase10_health_service.dart' in settings_page)
add('restore performs post-restore deep health gate', 'Phase10HealthService(store).run(deep: true)' in settings_backup)
add('restore warns on critical post-check', 'backup_imported_health_warning' in settings_backup)

translations = {}
for language in ('ar', 'en', 'fr'):
    translations[language] = json.loads((ROOT / f'assets/translations/{language}.json').read_text())
keys = [set(value) for value in translations.values()]
add('translation key parity', keys[0] == keys[1] == keys[2])
for key in (
    'production_health',
    'disaster_recovery_readiness',
    'create_recovery_checkpoint',
    'verify_latest_backup',
    'backup_imported_health_verified',
    'backup_imported_health_warning',
):
    add(f'translation {key}', all(key in translations[lang] for lang in translations))

failed = [name for name, ok in checks if not ok]
for name, ok in checks:
    print(('PASS' if ok else 'FAIL') + '  ' + name)
print(f'\nPhase 10 static verification: {len(checks)-len(failed)}/{len(checks)} PASS')
if failed:
    raise SystemExit(1)
