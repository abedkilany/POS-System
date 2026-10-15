part of 'settings_page.dart';

extension _DataActions on SettingsPage {
  Future<void> _downloadBackupFile(BuildContext context) async {
    await SettingsBackupActions.downloadBackupFile(context, store);
  }

  Future<void> _importBackupFile(BuildContext context) async {
    await SettingsBackupActions.importBackupFile(context, store);
  }

  Future<void> _downloadRecoveryFile(BuildContext context) async {
    await SettingsBackupActions.downloadRecoveryFile(context, store);
  }

  Future<void> _recoverExistingStore(BuildContext context) async {
    await SettingsBackupActions.recoverExistingStore(context, store);
  }

  Future<void> _clearLocalData(BuildContext context) async {
    await SettingsBackupActions.clearLocalData(context, store);
  }

  Future<void> _rebuildFromHost(BuildContext context) async {
    final tr = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppLocalizations.of(context).text('rebuild_from_host')),
        content:
            Text(AppLocalizations.of(context).text('rebuild_from_host_desc')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(AppLocalizations.of(context).text('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(AppLocalizations.of(context).text('rebuild'))),
        ],
      ),
    );
    if (confirmed != true) return;

    final progress = ValueNotifier<_OperationProgress>(
      _OperationProgress(0.05, tr.text('preparing_rebuild_percent')),
    );
    if (context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: Text(AppLocalizations.of(context).text('rebuild_from_host')),
          content: ValueListenableBuilder<_OperationProgress>(
            valueListenable: progress,
            builder: (_, value, __) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                UnifiedSnapshotProgressView(
                  value: value.value,
                  label: value.label,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final identity = store.runtime.identity;
    String message = '';
    bool success = false;

    try {
      progress.value = _OperationProgress(
          0.20, tr.text('resetting_local_client_state_percent'));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (identity.syncMode == SyncMode.directConnected ||
          identity.syncMode == SyncMode.marketplaceEnabled) {
        progress.value = _OperationProgress(
            0.40, tr.text('contacting_host_snapshot_percent'));
        final result = await UnifiedSyncFactory.directEngine(
          store,
          settings: VpsControlPlaneSettings.load(),
        ).rebuildFromHostSnapshot(
          onProgress: (value, label) => progress.value =
              _OperationProgress(value, '$label ${(value * 100).round()}%'),
        );
        progress.value = _OperationProgress(
            result.ok ? 1.0 : 0.90,
            result.ok
                ? tr.text('direct_rebuild_completed_percent')
                : tr.text('direct_rebuild_failed_verifying_percent'));
        message = localizeRuntimeMessage(result.message, tr);
        success = result.ok;
      } else {
        final settings = LanSyncSettings.load();
        progress.value =
            _OperationProgress(0.40, tr.text('contacting_lan_host_percent'));
        final result = await UnifiedSyncFactory.lanEngine(
          store,
          settings: settings,
        ).rebuildFromHostSnapshot(
          onProgress: (value, label) => progress.value =
              _OperationProgress(value, '$label ${(value * 100).round()}%'),
        );
        progress.value = _OperationProgress(
            result.ok ? 1.0 : 0.90,
            result.ok
                ? tr.text('lan_rebuild_completed_percent')
                : tr.text('lan_rebuild_failed_verifying_percent'));
        message = localizeRuntimeMessage(result.message, tr);
        success = result.ok;
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    } finally {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      progress.dispose();
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? AppLocalizations.of(context)
                  .text('rebuild_completed_successfully')
              : message),
        ),
      );
    }
  }

  Future<void> _resetBusinessData(BuildContext context) async {
    final tr = AppLocalizations.of(context);
    const confirmationWord = 'CONFIRM';
    String hostSafety = 'no_connected_devices';
    final token =
        'RST-${DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase()}';

    final step1 = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(tr.text('reset_all_data')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr.text('reset_host_local_factory_desc')),
              const SizedBox(height: 16),
              Text(tr.text('confirm_host_safety_status')),
              RadioGroup<String>(
                groupValue: hostSafety,
                onChanged: (value) =>
                    setState(() => hostSafety = value ?? hostSafety),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RadioListTile<String>(
                      value: 'other_host_ready',
                      title: Text(tr.text('configured_another_host')),
                    ),
                    RadioListTile<String>(
                      value: 'not_ready',
                      title: Text(tr.text('no')),
                    ),
                    RadioListTile<String>(
                      value: 'no_connected_devices',
                      title: Text(tr.text('no_connected_devices')),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(AppLocalizations.of(context).text('cancel'))),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(tr.text('continue'))),
          ],
        ),
      ),
    );
    if (step1 != true) return;
    if (!context.mounted) return;

    try {
      final backupPassword = await _requestBackupPassword(context);
      if (backupPassword == null) return;
      final backup =
          'RESET_PROTECTION_TOKEN:$token\n${await store.exportEncryptedBackupJson(backupPassword)}';
      await downloadTextFile(
          filename:
              'reset_protection_backup_${DateTime.now().millisecondsSinceEpoch}.json',
          content: backup);
    } catch (_) {
      // Backup download can fail on unsupported platforms; the visible token is still accepted.
    }

    if (!context.mounted) return;
    final tokenController = TextEditingController();
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    var canContinue = false;
    final verified = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(tr.text('reset_protection')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr.text('reset_protection_backup_generated')),
                const SizedBox(height: 8),
                SelectableText(token,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                TextField(
                    controller: tokenController,
                    decoration: InputDecoration(
                        labelText: tr.text('reset_token'),
                        border: const OutlineInputBorder()),
                    onChanged: (_) => setState(() => canContinue =
                        tokenController.text.trim() == token &&
                            confirmController.text.trim() == confirmationWord &&
                            passwordController.text.isNotEmpty)),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.attach_file_outlined),
                  label: Text(tr.text('attach_reset_protection_backup')),
                  onPressed: () async {
                    final picked = await FilePicker.platform
                        .pickFiles(type: FileType.any, withData: true);
                    final bytes = picked?.files.single.bytes;
                    if (bytes == null) return;
                    final content = utf8.decode(bytes, allowMalformed: true);
                    if (content.startsWith('RESET_PROTECTION_TOKEN:$token')) {
                      tokenController.text = token;
                      setState(() => canContinue =
                          tokenController.text.trim() == token &&
                              confirmController.text.trim() ==
                                  confirmationWord &&
                              passwordController.text.isNotEmpty);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: InputDecoration(
                        labelText: tr.text('admin_password'),
                        border: const OutlineInputBorder()),
                    onChanged: (_) => setState(() => canContinue =
                        tokenController.text.trim() == token &&
                            confirmController.text.trim() == confirmationWord &&
                            passwordController.text.isNotEmpty)),
                const SizedBox(height: 12),
                TextField(
                    controller: confirmController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                        labelText: tr.text('type_confirm'),
                        border: const OutlineInputBorder()),
                    onChanged: (_) => setState(() => canContinue =
                        tokenController.text.trim() == token &&
                            confirmController.text.trim() == confirmationWord &&
                            passwordController.text.isNotEmpty)),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(AppLocalizations.of(context).text('cancel'))),
            FilledButton(
                onPressed: canContinue
                    ? () => Navigator.pop(dialogContext, true)
                    : null,
                child: Text(tr.text('verify'))),
          ],
        ),
      ),
    );
    if (verified != true) return;

    final passwordOk =
        await store.security.verifyAdminPassword(passwordController.text) &&
            await store.security.authorizeSensitiveAction(
              action: SensitiveAction.databaseDestructive,
              password: passwordController.text,
            );
    if (!passwordOk) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr.text('admin_password_incorrect'))));
      }
      return;
    }

    if (!context.mounted) return;
    final finalController = TextEditingController();
    var finalOk = false;
    final finalConfirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(tr.text('final_irreversible_warning')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr.text('final_reset_warning')),
              const SizedBox(height: 12),
              TextField(
                  controller: finalController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                      labelText: tr.text('type_confirm_again'),
                      border: const OutlineInputBorder()),
                  onChanged: (value) => setState(
                      () => finalOk = value.trim() == confirmationWord)),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(AppLocalizations.of(context).text('cancel'))),
            FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error),
                onPressed:
                    finalOk ? () => Navigator.pop(dialogContext, true) : null,
                child: Text(tr.text('erase_everything'))),
          ],
        ),
      ),
    );
    if (finalConfirm != true) return;

    await store.recovery.factoryResetLocalDevice();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr.text('host_reset_completed'))));
    }
  }
}
