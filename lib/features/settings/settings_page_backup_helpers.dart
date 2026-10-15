part of 'settings_page.dart';

bool _looksLikeZip(List<int> bytes) {
  return bytes.length >= 4 &&
      bytes[0] == 0x50 &&
      bytes[1] == 0x4B &&
      bytes[2] == 0x03 &&
      bytes[3] == 0x04;
}

Future<String?> _requestBackupPassword(BuildContext context) async {
  final tr = AppLocalizations.of(context);
  final controller = TextEditingController();
  try {
    return await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr.text('enter_password')),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: InputDecoration(labelText: tr.text('backup_password')),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(tr.text('cancel')),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: Text(tr.text('continue')),
          ),
        ],
      ),
    );
  } finally {
    controller.dispose();
  }
}

Future<void> _publishImportedSnapshotToDirectIfNeeded(
  AppStore store,
) async {
  final identity = store.runtime.identity;
  final direct = VpsControlPlaneSettings.load();
  if (!identity.isHost || !identity.isDirectEnabled || !direct.isConfigured) {
    return;
  }

  final settings = direct.copyWith(enabled: true, clearLastPullCursor: true);
  try {
    SyncDiagnosticsLog.add(
      '[SYNC_TRACE] backupImport:publishHostSnapshot store=${identity.storeId} branch=${identity.branchId}',
    );
    final service = DirectControlPlaneService(store);
    // Snapshot data remains on the Host and is served through the relay.
    await service.pushPendingForUnifiedEngine(settings);
    SyncDiagnosticsLog.add(
      '[SYNC_TRACE] backupImport:publishHostSnapshotDone store=${identity.storeId} branch=${identity.branchId}',
    );
  } catch (error) {
    SyncDiagnosticsLog.add(
      '[SYNC_TRACE] backupImport:publishHostSnapshotFailed error=$error',
    );
  }
}
