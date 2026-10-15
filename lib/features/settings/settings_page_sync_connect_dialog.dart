// ignore_for_file: invalid_use_of_protected_member
part of 'settings_page.dart';

extension _SyncConnectDialog on _UnifiedSyncSettingsCardState {
  Future<void> _openConnectToStoreDialog(SyncMode mode) async {
    widget.store.requirePermission(AppPermission.syncManage);
    final tr = AppLocalizations.of(context);
    final lan = LanSyncSettings.load();
    final direct = DirectSyncSettings.load();
    _lanHostController.text = lan.host;
    _lanPortController.text = lan.port.toString();
    _lanIntervalController.text = lan.intervalSeconds.toString();
    _lanTokenController.text = lan.secret.trim();
    _directApiController.text = direct.apiBaseUrl;
    _directPairingCodeController.clear();
    _clearExpectedPairingTarget();
    var dialogMode = mode;
    var dialogBusy = false;
    double? dialogProgressValue;
    var dialogProgressLabel = '';
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isLan = dialogMode == SyncMode.lanOnly;
            final screenWidth = MediaQuery.sizeOf(context).width;
            final compact = screenWidth < 420;
            return AlertDialog(
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              title: Text(tr.text('connect_to_store'),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              content: ConstrainedBox(
                constraints: BoxConstraints(
                    maxWidth: screenWidth < 568 ? screenWidth - 32 : 520),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(tr.text('connect_to_store_desc'),
                          style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SegmentedButton<SyncMode>(
                          showSelectedIcon: !compact,
                          segments: [
                            ButtonSegment<SyncMode>(
                                value: SyncMode.lanOnly,
                                icon: const Icon(Icons.lan_outlined),
                                label: Text(tr.text('lan'))),
                            ButtonSegment<SyncMode>(
                                value: SyncMode.directConnected,
                                icon: const Icon(Icons.link_outlined),
                                label: Text(tr.text('direct'))),
                          ],
                          selected: {dialogMode},
                          onSelectionChanged: dialogBusy
                              ? null
                              : (value) => setDialogState(
                                  () => dialogMode = value.first),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: SizedBox(
                          width: compact ? double.infinity : null,
                          child: OutlinedButton.icon(
                            onPressed: (_busy || dialogBusy)
                                ? null
                                : () => _scanConnectToStoreQr(
                                      setDialogState,
                                      (mode) => setDialogState(
                                          () => dialogMode = mode),
                                      dialogMode,
                                    ),
                            icon: const Icon(Icons.qr_code_scanner_outlined),
                            label: Text(tr.text('scan_qr_code'),
                                overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (isLan) ...[
                        TextField(
                            enabled: !dialogBusy,
                            controller: _lanHostController,
                            decoration: InputDecoration(
                                labelText: tr.text('host_ip_address'),
                                border: const OutlineInputBorder())),
                        const SizedBox(height: 12),
                        TextField(
                            enabled: !dialogBusy,
                            controller: _lanPortController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                                labelText: tr.text('port'),
                                border: const OutlineInputBorder())),
                        const SizedBox(height: 12),
                        TextField(
                            enabled: !dialogBusy,
                            controller: _lanTokenController,
                            decoration: InputDecoration(
                                labelText: tr.text('pairing_token'),
                                border: const OutlineInputBorder())),
                      ] else ...[
                        TextField(
                            enabled: !dialogBusy,
                            controller: _directPairingCodeController,
                            decoration: InputDecoration(
                                labelText: tr.text('pairing_code_from_host'),
                                border: const OutlineInputBorder())),
                      ],
                      if (dialogBusy) ...[
                        const SizedBox(height: 16),
                        UnifiedSnapshotProgressView(
                          value: dialogProgressValue,
                          label: dialogProgressLabel.isEmpty
                              ? tr.text('connecting_downloading_store_data')
                              : dialogProgressLabel,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: Text(tr.text('cancel'))),
                FilledButton(
                  onPressed: dialogBusy
                      ? null
                      : () async {
                          setDialogState(() {
                            dialogBusy = true;
                            dialogProgressValue = 0.04;
                            dialogProgressLabel =
                                tr.text('connecting_downloading_store_data');
                          });
                          void dialogProgress(double value, String label) {
                            if (!dialogContext.mounted) return;
                            setDialogState(() {
                              dialogProgressValue = value;
                              dialogProgressLabel =
                                  localizeRuntimeMessage(label, tr);
                            });
                          }

                          try {
                            if (isLan) {
                              final host = _lanHostController.text.trim();
                              final token = _lanTokenController.text.trim();
                              if (host.isEmpty || token.isEmpty) {
                                setDialogState(() => dialogBusy = false);
                                return;
                              }
                              final previousIdentity = widget.store.appIdentity;
                              final previousActive = previousIdentity
                                  .activeSyncTransportNormalized;
                              final result = await _lanEngine(
                                LanSyncSettings.load().copyWith(
                                  host: host,
                                  port: _lanPort,
                                  secret: token,
                                  mode: LanSyncDeviceMode.client,
                                  setupComplete: true,
                                  hostModeEnabled: false,
                                ),
                              ).claimPairingCode(
                                token,
                                onProgress: dialogProgress,
                              );
                              if (!result.ok) throw Exception(result.message);
                              _validateExpectedPairingTarget(
                                  widget.store.appIdentity);
                              _validateAgainstExistingClientIdentity(
                                  previousIdentity, widget.store.appIdentity);
                              if (previousActive == 'direct') {
                                await widget.store
                                    .setActiveSyncTransport('direct');
                              }
                            } else {
                              final code =
                                  _directPairingCodeController.text.trim();
                              if (code.isEmpty) {
                                setDialogState(() => dialogBusy = false);
                                return;
                              }
                              final previousIdentity = widget.store.appIdentity;
                              final previousActive = previousIdentity
                                  .activeSyncTransportNormalized;
                              final result =
                                  await UnifiedSyncFactory.directEngine(
                                          widget.store)
                                      .claimPairingCode(
                                code,
                                onProgress: dialogProgress,
                              );
                              if (!result.ok) throw Exception(result.message);
                              final claimedIdentity =
                                  result.identity ?? widget.store.appIdentity;
                              _validateExpectedPairingTarget(claimedIdentity);
                              _validateAgainstExistingClientIdentity(
                                  previousIdentity, claimedIdentity);
                              if (previousActive == 'lan') {
                                await widget.store
                                    .setActiveSyncTransport('lan');
                              } else {
                                await widget.store
                                    .setActiveSyncTransport('direct');
                              }
                            }
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop(true);
                            }
                          } catch (error) {
                            if (!dialogContext.mounted) return;
                            setDialogState(() {
                              dialogBusy = false;
                              dialogProgressLabel =
                                  localizeRuntimeMessage(error.toString(), tr);
                            });
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text(localizeRuntimeMessage(
                                    error.toString(), tr))));
                          }
                        },
                  child:
                      Text(dialogBusy ? tr.text('working') : tr.text('save')),
                ),
              ],
            );
          },
        );
      },
    );
    if (saved == true && mounted) {
      setState(() => _status = tr.text('sync_settings_saved'));
      await widget.onSyncSettingsChanged?.call();
    }
  }
}
