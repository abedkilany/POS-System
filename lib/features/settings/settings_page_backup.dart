part of 'settings_page.dart';

class SettingsBackupActions {
  static Future<void> downloadBackupFile(
    BuildContext context,
    AppStore store,
  ) async {
    final tr = AppLocalizations.of(context);
    try {
      final filename =
          'ventio_backup_${DateTime.now().millisecondsSinceEpoch}.json';
      await downloadTextFile(
        filename: filename,
        content: store.exportBackupJson(),
        dialogTitle: tr.text('export'),
        cancelMessage: tr.text('file_save_cancelled'),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr.text('backup_downloaded'))),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr.text('backup_download_not_supported'))),
        );
      }
    }
  }

  static Future<void> importBackupFile(
    BuildContext context,
    AppStore store,
  ) async {
    final tr = AppLocalizations.of(context);
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json', 'vtb'],
        withData: true,
      );
      final file = picked?.files.single;
      final bytes = file?.bytes;
      if (bytes == null || bytes.isEmpty) return;

      final isLocalBackupArchive =
          (file?.extension?.toLowerCase() == 'vtb') || _looksLikeZip(bytes);
      var rawJson = isLocalBackupArchive
          ? store.extractBackupJsonFromLocalBackupArchiveBytes(bytes)
          : utf8.decode(bytes, allowMalformed: true).trim();
      if (rawJson.startsWith('RESET_PROTECTION_TOKEN:')) {
        final jsonStart = rawJson.indexOf('{');
        if (jsonStart >= 0) {
          rawJson = rawJson.substring(jsonStart).trim();
        }
      }

      if (store.isEncryptedBackupJson(rawJson)) {
        if (!context.mounted) return;
        final password = await _requestBackupPassword(context);
        if (password == null) return;
        rawJson = store.decryptBackupJson(rawJson, password);
      }

      final plan = store.inspectBackupJson(rawJson);
      if (!context.mounted) return;
      final selectedSections = await confirmBackupImport(context, plan);
      if (selectedSections == null || selectedSections.isEmpty) return;

      await store.importBackupJson(rawJson,
          selectedSectionIds: selectedSections);
      await _publishImportedSnapshotToCloudIfNeeded(store);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr.text('backup_imported'))),
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${tr.text('backup_import_failed')}: $error')),
        );
      }
    }
  }

  static Future<void> _publishImportedSnapshotToCloudIfNeeded(
    AppStore store,
  ) async {
    final identity = store.appIdentity;
    final cloud = CloudSyncSettings.load();
    if (!identity.isHost || !identity.isCloudEnabled || !cloud.isConfigured) {
      return;
    }

    final settings = cloud.copyWith(enabled: true, clearLastPullCursor: true);
    try {
      SyncDiagnosticsLog.add(
        '[SYNC_TRACE] backupImport:publishHostSnapshot store=${identity.storeId} branch=${identity.branchId}',
      );
      final service = CloudSyncService(store);
      await service.publishBootstrapSnapshotToCloud(settings, force: true);
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

  static Future<void> downloadRecoveryFile(
    BuildContext context,
    AppStore store,
  ) async {
    final tr = AppLocalizations.of(context);
    final identity = store.appIdentity;
    final cloud = CloudSyncSettings.load();
    var confirmed = false;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(tr.text('store_recovery_security')),
          content: ResponsiveDialogBox(
            maxWidth: VentioResponsive.modalMaxWidth(context, 540),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr.text('store_recovery_security_desc')),
                const SizedBox(height: 12),
                _SecureRecoveryLine(
                    title: tr.text('store_id'), value: identity.storeId),
                _SecureRecoveryLine(
                    title: tr.text('branch_id'), value: identity.branchId),
                _SecureRecoveryLine(
                    title: tr.text('recovery_key'),
                    value: identity.recoveryKey),
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: confirmed,
                  onChanged: (value) =>
                      setState(() => confirmed = value ?? false),
                  title: Text(tr.text('confirm_recovery_saved')),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(tr.text('cancel'))),
            FilledButton(
                onPressed:
                    confirmed ? () => Navigator.pop(dialogContext, true) : null,
                child: Text(tr.text('download_recovery_file'))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final filename =
        'ventio_recovery_${identity.storeId}_${DateTime.now().millisecondsSinceEpoch}.json';
    try {
      await downloadTextFile(
          filename: filename,
          content: store.exportRecoveryFileJson(cloudApiUrl: cloud.apiBaseUrl),
          dialogTitle: tr.text('save_recovery_file'),
          cancelMessage: tr.text('file_save_cancelled'));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr.text('recovery_file_downloaded'))));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr.text('backup_download_not_supported'))));
      }
    }
  }

  static Future<void> recoverExistingStore(
    BuildContext context,
    AppStore store,
  ) async {
    if (store.appIdentity.hostDeviceId.trim().isNotEmpty) {
      if (!store.hasPermission(AppPermission.syncManage)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('You do not have permission: sync.manage'),
          ));
        }
        return;
      }
      await recoverStoreData(context, store);
      return;
    }
    await recoverStoreIdentity(context, store);
  }

  static Future<void> recoverStoreIdentity(
    BuildContext context,
    AppStore store,
  ) async {
    final tr = AppLocalizations.of(context);
    final cache = AccountAuthCache.load();
    final cloud = CloudSyncSettings.load();
    final storeId = (cache?.storeId.trim().isNotEmpty == true
            ? cache!.storeId
            : store.appIdentity.storeId)
        .trim()
        .toUpperCase();
    final branchId = (cache?.branchId.trim().isNotEmpty == true
            ? cache!.branchId
            : store.appIdentity.branchId)
        .trim()
        .toUpperCase();

    if (cache == null || cache.accountToken.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Online account session is required. Please sign in again.'),
        ),
      );
      return;
    }
    if (!storeId.startsWith('ST-')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A valid Store ID was not found for this account.'),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr.text('recover_store_identity')),
        content: ResponsiveDialogBox(
          maxWidth: VentioResponsive.modalMaxWidth(context, 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr.text('recover_store_identity_desc')),
              const SizedBox(height: 12),
              Text('Store ID: $storeId'),
              if (branchId.isNotEmpty) Text('Branch ID: $branchId'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(tr.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(tr.text('recover')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final recoverySettings = cloud.copyWith(
        enabled: true,
        apiBaseUrl: cloud.apiBaseUrl.trim().isNotEmpty
            ? cloud.apiBaseUrl.trim()
            : CloudSyncSettings.bundledApiBaseUrl,
        clearLastPullCursor: true,
      );
      await recoverySettings.save();
      final result =
          await CloudSyncService(store).recoverExistingStoreIdentityFromCloud(
        recoverySettings,
        storeId: storeId,
        branchId: branchId,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(localizeRuntimeMessage(result.message, tr))),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  static Future<void> recoverStoreData(
    BuildContext context,
    AppStore store,
  ) async {
    final tr = AppLocalizations.of(context);
    final cache = AccountAuthCache.load();
    final cloud = CloudSyncSettings.load();
    final storeId = (cache?.storeId.trim().isNotEmpty == true
            ? cache!.storeId
            : store.appIdentity.storeId)
        .trim()
        .toUpperCase();
    final branchId = (cache?.branchId.trim().isNotEmpty == true
            ? cache!.branchId
            : store.appIdentity.branchId)
        .trim()
        .toUpperCase();

    if (cache == null || cache.accountToken.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Online account session is required. Please sign in again.'),
        ),
      );
      return;
    }
    if (!storeId.startsWith('ST-')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A valid Store ID was not found for this account.'),
        ),
      );
      return;
    }
    if (store.appIdentity.hostDeviceId.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr.text('recover_store_identity_first'))),
      );
      return;
    }
    if (!store.hasPermission(AppPermission.syncManage)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You do not have permission: sync.manage'),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr.text('recover_store_data')),
        content: ResponsiveDialogBox(
          maxWidth: VentioResponsive.modalMaxWidth(context, 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr.text('recover_store_data_desc')),
              const SizedBox(height: 12),
              Text('Store ID: $storeId'),
              if (branchId.isNotEmpty) Text('Branch ID: $branchId'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(tr.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(tr.text('recover')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final recoverySettings = cloud.copyWith(
        enabled: true,
        apiBaseUrl: cloud.apiBaseUrl.trim().isNotEmpty
            ? cloud.apiBaseUrl.trim()
            : CloudSyncSettings.bundledApiBaseUrl,
        clearLastPullCursor: true,
      );
      await recoverySettings.save();
      final result =
          await CloudSyncService(store).recoverExistingStoreFromCloud(
        recoverySettings,
        storeId: storeId,
        branchId: branchId,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(localizeRuntimeMessage(result.message, tr))),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  static Future<void> clearLocalData(
    BuildContext context,
    AppStore store,
  ) async {
    const confirmationWord = 'CONFIRM';
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final controller = TextEditingController();
        var canDelete = false;
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text(AppLocalizations.of(context).text('clear_local_data')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppLocalizations.of(context)
                    .text('clear_local_data_warning')),
                const SizedBox(height: 16),
                Text(
                  AppLocalizations.of(context).format(
                      'type_word_to_confirm', {'word': confirmationWord}),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText:
                        AppLocalizations.of(context).text('confirmation_word'),
                    hintText: confirmationWord,
                  ),
                  onChanged: (value) {
                    final next = value.trim() == confirmationWord;
                    if (next != canDelete) {
                      setState(() => canDelete = next);
                    }
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(AppLocalizations.of(context).text('cancel')),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed:
                    canDelete ? () => Navigator.pop(dialogContext, true) : null,
                child: Text(
                    AppLocalizations.of(context).text('clear_this_device')),
              ),
            ],
          ),
        );
      },
    );
    if (confirmed != true) return;
    await store.factoryResetLocalDevice();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(AppLocalizations.of(context).text('device_reset_sign_in'))));
    }
  }

  static Future<void> rebuildFromHost(
    BuildContext context,
    AppStore store,
  ) async {
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

    final identity = store.appIdentity;
    String message = '';
    bool success = false;

    try {
      progress.value = _OperationProgress(
          0.20, tr.text('resetting_local_client_state_percent'));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (identity.syncMode == SyncMode.cloudConnected ||
          identity.syncMode == SyncMode.marketplaceEnabled) {
        progress.value = _OperationProgress(
            0.40, tr.text('contacting_cloud_host_snapshot_percent'));
        final result = await UnifiedSyncEngine(
          CloudSyncTransportAdapter(
            service: CloudSyncService(store),
            settings: CloudSyncSettings.load(),
          ),
        ).rebuildFromHostSnapshot(
          onProgress: (value, label) => progress.value =
              _OperationProgress(value, '$label ${(value * 100).round()}%'),
        );
        progress.value = _OperationProgress(
            result.ok ? 1.0 : 0.90,
            result.ok
                ? tr.text('cloud_rebuild_completed_percent')
                : tr.text('cloud_rebuild_failed_verifying_percent'));
        message = localizeRuntimeMessage(result.message, tr);
        success = result.ok;
      } else {
        final settings = LanSyncSettings.load();
        progress.value =
            _OperationProgress(0.40, tr.text('contacting_lan_host_percent'));
        final result = await UnifiedSyncEngine(
          LanSyncTransportAdapter(
            service: LanSyncService(store),
            settings: settings,
          ),
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

  static Future<void> resetBusinessData(
    BuildContext context,
    AppStore store,
  ) async {
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

    try {
      final backup =
          'RESET_PROTECTION_TOKEN:$token\n${store.exportBackupJson()}';
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

    final passwordOk = await store.verifyAdminPassword(passwordController.text);
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

    await store.factoryResetLocalDevice();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr.text('host_reset_completed'))));
    }
  }

  static Future<Set<String>?> confirmBackupImport(
    BuildContext context,
    BackupImportPlan plan,
  ) async {
    final tr = AppLocalizations.of(context);
    final selected = plan.sections
        .where((section) => section.available && section.selectedByDefault)
        .map((section) => section.id)
        .toSet();
    return showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          final businessSections = plan.sections
              .where((section) => section.group == 'Business data')
              .toList();
          final systemSections = plan.sections
              .where((section) => section.group == 'System data')
              .toList();
          final selectedAvailableCount = plan.sections
              .where((section) =>
                  section.available && selected.contains(section.id))
              .length;

          Widget sectionTile(BackupImportSection section) {
            final checked = selected.contains(section.id);
            final subtitleParts = <String>[];
            if (section.count != null) {
              subtitleParts
                  .add('${section.count} item${section.count == 1 ? '' : 's'}');
            }
            if (!section.available) {
              subtitleParts.add('Not available in this backup');
            }
            if (section.warning != null && checked) {
              subtitleParts.add(section.warning!);
            }
            return CheckboxListTile(
              value: section.available && checked,
              onChanged: section.available
                  ? (value) {
                      setState(() {
                        if (value == true) {
                          selected.add(section.id);
                        } else {
                          selected.remove(section.id);
                        }
                      });
                    }
                  : null,
              title: Text(section.label),
              subtitle: subtitleParts.isEmpty
                  ? null
                  : Text(subtitleParts.join(' • ')),
              controlAffinity: ListTileControlAffinity.leading,
            );
          }

          Widget group(String title, List<BackupImportSection> sections) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                ...sections.map(sectionTile),
              ],
            );
          }

          final dialogWidth = VentioResponsive.dialogLargeWidth(context);
          final wideLayout = VentioResponsive.isWideDialogLayout(context);
          final sectionsLayout = wideLayout
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: group('Business data', businessSections)),
                    const SizedBox(width: 24),
                    Expanded(child: group('System data', systemSections)),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    group('Business data', businessSections),
                    group('System data', systemSections),
                  ],
                );

          return AlertDialog(
            insetPadding: EdgeInsets.symmetric(
              horizontal: VentioResponsive.pagePadding(context),
              vertical: 24,
            ),
            constraints: BoxConstraints(maxWidth: dialogWidth),
            title: Text(tr.text('confirm_backup_import')),
            content: SizedBox(
              width: dialogWidth,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _BackupSummaryDetails(summary: plan.summary),
                    const SizedBox(height: 16),
                    Text(
                      'Review backup sections. Business data is selected by default. System data is available but left unchecked by default.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    sectionsLayout,
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(tr.text('cancel')),
              ),
              FilledButton(
                onPressed: selectedAvailableCount == 0
                    ? null
                    : () => Navigator.pop(
                        dialogContext, Set<String>.from(selected)),
                child: Text(tr.text('restore')),
              ),
            ],
          );
        },
      ),
    );
  }

  static bool _looksLikeZip(List<int> bytes) {
    return bytes.length >= 4 &&
        bytes[0] == 0x50 &&
        bytes[1] == 0x4B &&
        bytes[2] == 0x03 &&
        bytes[3] == 0x04;
  }

  static Future<String?> _requestBackupPassword(BuildContext context) async {
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
}
