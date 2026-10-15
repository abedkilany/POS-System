// ignore_for_file: invalid_use_of_protected_member
part of 'settings_page.dart';

extension _SyncPairingViews on _UnifiedSyncSettingsCardState {
  Widget _pairingContent(BuildContext context,
      {required bool isHost, required bool isDirectClient}) {
    final tr = AppLocalizations.of(context);
    if (isHost) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                  onPressed: _busy ? null : _handleLanPairingButton,
                  icon: const Icon(Icons.lan_outlined),
                  label: Text(_lanPairingButtonLabel)),
              OutlinedButton.icon(
                  onPressed: _busy || !_canManageSync
                      ? null
                      : _createDirectPairingCode,
                  icon: const Icon(Icons.link_outlined),
                  label: Text(_directPairingButtonLabel)),
              if (_lanTokenController.text.trim().isNotEmpty &&
                  !_showLanPairingCode)
                OutlinedButton.icon(
                  onPressed: () => setState(() => _showLanPairingCode = true),
                  icon: const Icon(Icons.visibility_outlined),
                  label: Text(tr.text('show_code')),
                ),
              if (_latestDirectPairingCode.trim().isNotEmpty &&
                  !_showDirectPairingCode)
                OutlinedButton.icon(
                  onPressed: () =>
                      setState(() => _showDirectPairingCode = true),
                  icon: const Icon(Icons.visibility_outlined),
                  label: Text(tr.text('show_code')),
                ),
            ],
          ),
          if (_showLanPairingCode) ...[
            const SizedBox(height: 12),
            _lanPairingCodeCard()
          ],
          if (_showDirectPairingCode) ...[
            const SizedBox(height: 12),
            _directPairingCodeCard()
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _softNotice(
          context,
          Icons.info_outline,
          tr.text('connect_device'),
          tr.text('client_pairing_enter_or_scan_host_code'),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 10, children: [
          OutlinedButton.icon(
            onPressed: _busy || !_canManageSync ? null : _scanPairingQr,
            icon: const Icon(Icons.qr_code_scanner_outlined),
            label: Text(tr.text('scan_qr_code')),
          ),
        ]),
        const SizedBox(height: 8),
        Text(
          tr.text('replace_host_reset_required'),
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _miniLine(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(children: [
        Expanded(child: Text(title)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600))
      ]),
    );
  }

  Widget _softNotice(
      BuildContext context, IconData icon, String title, String value) {
    final color = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: color.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Icon(icon),
        const SizedBox(width: 10),
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(value)
            ]))
      ]),
    );
  }

  String _humanStatus(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final identity = widget.store.appIdentity;
    if (identity.isHost) {
      final lan = LanSyncSettings.load();
      final direct = DirectSyncSettings.load();
      return '${tr.text('connection_role_host')} • ${tr.text('connection_lan')}: ${lan.setupComplete && lan.isHost ? tr.text('connection_state_active') : tr.text('connection_state_disabled')} • Direct: ${direct.isConfigured ? tr.text('connection_state_active') : tr.text('connection_state_disabled')}';
    }
    final runtimeTransport = _runtimeClientTransport();
    return '${tr.text('connection_role_client')} • ${runtimeTransport == 'direct' ? 'Direct' : runtimeTransport == 'lan' ? tr.text('connection_lan') : tr.text('connection_local')}';
  }

  Widget _hostChangedNotificationCard() {
    final notice = widget.store.latestHostTransferNotification;
    if (notice == null) return const SizedBox.shrink();
    final newHostDeviceId = notice['newHostDeviceId']?.toString() ?? '';
    final storeId =
        notice['storeId']?.toString() ?? widget.store.appIdentity.storeId;
    final branchId =
        notice['branchId']?.toString() ?? widget.store.appIdentity.branchId;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: VentioResponsive.cardInsets(context),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .primaryContainer
            .withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color:
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline),
          const SizedBox(width: 8),
          Expanded(
            child: Text(AppLocalizations.of(context)
                .text('host_changed_notification')
                .replaceAll('{storeId}', storeId)
                .replaceAll('{branchId}', branchId)
                .replaceAll('{deviceId}', newHostDeviceId)),
          ),
          IconButton(
            tooltip: AppLocalizations.of(context).text('dismiss'),
            onPressed: _busy
                ? null
                : () {
                    widget.store.clearHostTransferNotification();
                  },
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _transferHostCard({required bool isHost}) {
    final tr = AppLocalizations.of(context);
    final pending = widget.store.pendingHostTransferRequest;
    final approvedForThisDevice =
        widget.store.approvedHostTransferDeviceId == widget.store.deviceId;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: VentioResponsive.cardInsets(context),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.swap_horiz_outlined),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(tr.text('transfer_host_role'),
                      style: Theme.of(context).textTheme.titleMedium)),
            ],
          ),
          const SizedBox(height: 8),
          if (isHost) ...[
            Text(tr.text('transfer_host_role_desc')),
            const SizedBox(height: 8),
            if (pending != null) ...[
              Text(tr.text('latest_request').replaceAll(
                  '{deviceId}',
                  (pending['requestingDeviceId'] ?? tr.text('unknown_device'))
                      .toString())),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => setState(() => _transferDeviceController.text =
                        (pending['requestingDeviceId'] ?? '').toString()),
                icon: const Icon(Icons.input_outlined),
                label: Text(tr.text('use_latest_request')),
              ),
              const SizedBox(height: 8),
            ],
            TextField(
              controller: _transferDeviceController,
              decoration: InputDecoration(
                  labelText: tr.text('client_device_id_to_approve'),
                  border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy || !_canManageSync
                    ? null
                    : _approveHostTransferFromUi,
                icon: const Icon(Icons.verified_user_outlined),
                label: Text(tr.text('approve_host_transfer')),
              ),
            ),
          ] else ...[
            Text(tr
                .text('this_client_device_id')
                .replaceAll('{deviceId}', widget.store.deviceId)),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed:
                    _busy || !_canManageSync ? null : _requestHostTransfer,
                icon: const Icon(Icons.outbox_outlined),
                label: Text(tr.text('request_to_become_host')),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy || !_canManageSync || !approvedForThisDevice
                    ? null
                    : _activateApprovedHostTransferFromUi,
                icon: const Icon(Icons.admin_panel_settings_outlined),
                label: Text(tr.text('activate_approved_host_transfer')),
              ),
            ),
            if (!approvedForThisDevice)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(tr.text('host_transfer_activation_hint')),
              ),
          ],
        ],
      ),
    );
  }

  Widget _hostIpInfoCard() {
    final tr = AppLocalizations.of(context);
    final ipText = _detectingHostIp
        ? tr.text('detecting_local_ip')
        : (_hostIpAddresses.isEmpty
            ? tr.text('no_local_ipv4')
            : _hostIpAddresses.join('  •  '));
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: VentioResponsive.cardInsets(context),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lan_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr.text('host_ip_address'),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(ipText),
                const SizedBox(height: 4),
                Text(tr.text('host_ip_desc')),
              ],
            ),
          ),
          IconButton(
            tooltip: tr.text('refresh_ip'),
            onPressed:
                _busy || _detectingHostIp ? null : _refreshHostIpAddresses,
            icon: const Icon(Icons.refresh_outlined),
          ),
        ],
      ),
    );
  }

  _PairingCodeVisualStatus _pairingVisualStatus({
    required String code,
    required DateTime? expiresAt,
    required bool consumed,
    bool invalid = false,
  }) {
    if (invalid) return _PairingCodeVisualStatus.invalid;
    if (consumed) return _PairingCodeVisualStatus.consumed;
    if (code.trim().isEmpty) return _PairingCodeVisualStatus.disabled;
    if (expiresAt == null) return _PairingCodeVisualStatus.invalid;
    if (!expiresAt.isAfter(DateTime.now())) {
      return _PairingCodeVisualStatus.expired;
    }
    return _PairingCodeVisualStatus.active;
  }

  ({String label, IconData icon, Color background, Color foreground})
      _pairingStatusData(
    BuildContext context,
    _PairingCodeVisualStatus status,
  ) {
    final tr = AppLocalizations.of(context);
    final color = Theme.of(context).colorScheme;
    return switch (status) {
      _PairingCodeVisualStatus.active => (
          label: tr.text('connection_state_active'),
          icon: Icons.check_circle_outline,
          background: Colors.green.withValues(alpha: 0.12),
          foreground: Colors.green.shade700
        ),
      _PairingCodeVisualStatus.expired => (
          label: tr.text('pairing_status_expired'),
          icon: Icons.timer_off_outlined,
          background: Colors.grey.withValues(alpha: 0.16),
          foreground: color.onSurfaceVariant
        ),
      _PairingCodeVisualStatus.consumed => (
          label: tr.text('pairing_status_consumed'),
          icon: Icons.done_all_outlined,
          background: Colors.green.withValues(alpha: 0.12),
          foreground: Colors.green.shade700
        ),
      _PairingCodeVisualStatus.invalid => (
          label: tr.text('pairing_status_invalid'),
          icon: Icons.error_outline,
          background: color.errorContainer,
          foreground: color.onErrorContainer
        ),
      _PairingCodeVisualStatus.disabled => (
          label: tr.text('pairing_status_disabled'),
          icon: Icons.block_outlined,
          background: Colors.grey.withValues(alpha: 0.16),
          foreground: color.onSurfaceVariant
        ),
    };
  }

  Widget _pairingStatusBadge(
      BuildContext context, _PairingCodeVisualStatus status) {
    final data = _pairingStatusData(context, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
          color: data.background, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(data.icon, size: 16, color: data.foreground),
          const SizedBox(width: 6),
          Text(data.label,
              style: TextStyle(
                  color: data.foreground, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _manualPairingValueTile({
    required String label,
    required String value,
    required String copiedMessage,
  }) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          tooltip: AppLocalizations.of(context).text('copy_code'),
          onPressed: value.trim().isEmpty
              ? null
              : () async {
                  await Clipboard.setData(ClipboardData(text: value));
                  if (!mounted) return;
                  setState(() => _status = copiedMessage);
                },
          icon: const Icon(Icons.copy_outlined),
        ),
      ),
      child: SelectableText(
        value,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(letterSpacing: value.length > 12 ? 0.8 : 0),
      ),
    );
  }

  Color _pairingBorderColor(
      BuildContext context, _PairingCodeVisualStatus status) {
    final color = Theme.of(context).colorScheme;
    return switch (status) {
      _PairingCodeVisualStatus.active => Colors.green,
      _PairingCodeVisualStatus.consumed => Colors.green,
      _PairingCodeVisualStatus.expired => Colors.grey,
      _PairingCodeVisualStatus.invalid => color.error,
      _PairingCodeVisualStatus.disabled => color.outlineVariant,
    };
  }

  Widget _lanPairingCodeCard() {
    final tr = AppLocalizations.of(context);
    final code = _lanTokenController.text.trim();
    if (code.isEmpty) return const SizedBox.shrink();
    final host = _lanHostController.text.trim().isNotEmpty
        ? _lanHostController.text.trim()
        : LanSyncSettings.load().host;
    final status = _pairingVisualStatus(
        code: code,
        expiresAt: _latestLanPairingExpiresAt,
        consumed: _latestLanPairingConsumed);
    final borderColor = _pairingBorderColor(context, status);
    final identity = widget.store.appIdentity;
    final payload = jsonEncode({
      'transport': 'lan',
      'host': host,
      'port': _lanPort,
      'pairingCode': code,
      'storeId': identity.storeId,
      'branchId': identity.branchId,
      'hostDeviceId': widget.store.deviceId,
      if (identity.controlPlaneTenantId.trim().isNotEmpty)
        'controlPlaneTenantId': identity.controlPlaneTenantId,
      'expiresAt': _latestLanPairingExpiresAt?.toIso8601String(),
    });
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: VentioResponsive.pageInsets(context),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: borderColor.withValues(alpha: 0.65), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_latestPairingTransport == 'direct'
                  ? Icons.link_outlined
                  : Icons.qr_code_2_outlined),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(tr.text('lan_one_time_pairing_code'),
                      style: Theme.of(context).textTheme.titleMedium)),
              _pairingStatusBadge(context, status),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () => setState(() => _showLanPairingCode = false),
                icon: const Icon(Icons.visibility_off_outlined),
                label: Text(tr.text('hide_code')),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Center(
            child: Container(
              padding: VentioResponsive.cardInsets(context),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                data: payload,
                version: QrVersions.auto,
                size: 180,
              ),
            ),
          ),
          if (_latestPairingTransport == 'direct') ...[
            const SizedBox(height: 12),
            _temporaryDirectDiagnostics(),
          ],
          const SizedBox(height: 12),
          Text(
            status == _PairingCodeVisualStatus.active
                ? tr.format('expires_in',
                    {'time': _countdownText(_latestLanPairingExpiresAt)})
                : tr.format('pairing_code_state_help', {
                    'status':
                        _pairingStatusData(context, status).label.toLowerCase()
                  }),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          _manualPairingValueTile(
              label: tr.text('host_ip_address'),
              value: host,
              copiedMessage: tr.text('copied_to_clipboard')),
          const SizedBox(height: 10),
          _manualPairingValueTile(
              label: tr.text('port'),
              value: _lanPort.toString(),
              copiedMessage: tr.text('copied_to_clipboard')),
          const SizedBox(height: 10),
          _manualPairingValueTile(
              label: tr.text('pairing_token'),
              value: code,
              copiedMessage: tr.text('lan_pairing_code_copied')),
        ],
      ),
    );
  }

  Widget _temporaryDirectDiagnostics() {
    final tr = AppLocalizations.of(context);
    if (!_showDirectDiagnostics) {
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: () => setState(() => _showDirectDiagnostics = true),
          icon: const Icon(Icons.terminal_outlined),
          label: Text(tr.text('show_log')),
        ),
      );
    }
    return ValueListenableBuilder<List<String>>(
      valueListenable: SyncDiagnosticsLog.lines,
      builder: (context, lines, _) {
        final directLines =
            lines.where((line) => line.contains('[DIRECT_')).toList();
        final text = directLines.join('\n');
        return Card(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.bug_report_outlined),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(tr.text('direct_diagnostics_temporary'))),
                    IconButton(
                      tooltip: tr.text('hide_log'),
                      onPressed: () =>
                          setState(() => _showDirectDiagnostics = false),
                      icon: const Icon(Icons.visibility_off_outlined),
                    ),
                    IconButton(
                      tooltip: tr.text('copy_diagnostics'),
                      onPressed: text.isEmpty
                          ? null
                          : () async {
                              await Clipboard.setData(
                                  ClipboardData(text: text));
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content:
                                          Text(tr.text('diagnostics_copied'))),
                                );
                              }
                            },
                      icon: const Icon(Icons.copy_outlined),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SelectableText(
                  text.isEmpty ? tr.text('no_direct_diagnostics_yet') : text,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        height: 1.35,
                      ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _directPairingCodeCard() {
    final tr = AppLocalizations.of(context);
    final code = _latestDirectPairingCode.trim();
    if (code.isEmpty) {
      return const SizedBox.shrink();
    }
    final status = _pairingVisualStatus(
        code: code,
        expiresAt: _latestDirectPairingExpiresAt,
        consumed: _latestDirectPairingConsumed,
        invalid: _latestDirectPairingInvalid);
    final borderColor = _pairingBorderColor(context, status);
    final expiresText = status == _PairingCodeVisualStatus.active
        ? tr.format('expires_in',
            {'time': _countdownText(_latestDirectPairingExpiresAt)})
        : tr.format('pairing_code_state_help', {
            'status': _pairingStatusData(context, status).label.toLowerCase()
          });
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: VentioResponsive.pageInsets(context),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: borderColor.withValues(alpha: 0.65), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.qr_code_2_outlined),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(
                      _latestPairingTransport == 'direct'
                          ? 'Direct Pairing Code'
                          : tr.text('direct_pairing_code'),
                      style: Theme.of(context).textTheme.titleMedium)),
              _pairingStatusBadge(context, status),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () => setState(() => _showDirectPairingCode = false),
                icon: const Icon(Icons.visibility_off_outlined),
                label: Text(tr.text('hide_code')),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Center(
            child: Container(
              padding: VentioResponsive.cardInsets(context),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                data: jsonEncode({
                  'transport': _latestPairingTransport,
                  'pairingCode': code,
                  if (_latestPairingTransport == 'direct')
                    'apiBaseUrl':
                        DirectSyncSettings.load().apiBaseUrl.trim().isNotEmpty
                            ? DirectSyncSettings.load().apiBaseUrl.trim()
                            : VpsControlPlaneSettings.load().apiBaseUrl,
                  'storeId': widget.store.appIdentity.storeId,
                  'branchId': widget.store.appIdentity.branchId,
                  'hostDeviceId': widget.store.deviceId,
                  if (widget.store.appIdentity.controlPlaneTenantId
                      .trim()
                      .isNotEmpty)
                    'controlPlaneTenantId':
                        widget.store.appIdentity.controlPlaneTenantId,
                  'expiresAt': _latestDirectPairingExpiresAt?.toIso8601String(),
                }),
                version: QrVersions.auto,
                size: 180,
              ),
            ),
          ),
          if (_latestPairingTransport == 'direct') ...[
            const SizedBox(height: 12),
            _temporaryDirectDiagnostics(),
          ],
          const SizedBox(height: 12),
          Text(
            expiresText,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          _manualPairingValueTile(
              label: _latestPairingTransport == 'direct'
                  ? 'Direct pairing code'
                  : tr.text('direct_pairing_code'),
              value: code,
              copiedMessage: tr.text('direct_pairing_code_copied')),
        ],
      ),
    );
  }

  List<Widget> _lanFields(
          {required bool showHostIp,
          bool forHost = false,
          bool dialogBusy = false}) =>
      [
        if (showHostIp)
          TextField(
              enabled: !dialogBusy,
              controller: _lanHostController,
              decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)
                      .text('manual_host_ip_optional'),
                  border: const OutlineInputBorder())),
        if (showHostIp) const SizedBox(height: 12),
        TextField(
            enabled: !dialogBusy,
            controller: _lanPortController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
                labelText: AppLocalizations.of(context).text('port'),
                border: const OutlineInputBorder())),
        const SizedBox(height: 12),
        if (!forHost) ...[
          TextField(
            controller: _lanTokenController,
            decoration: InputDecoration(
              labelText:
                  AppLocalizations.of(context).text('lan_pairing_code_label'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ];

  List<Widget> _lanClientFields() => [
        TextField(
          enabled: !_busy,
          controller: _lanHostController,
          decoration: InputDecoration(
            labelText: AppLocalizations.of(context).text('host_ip_address'),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          enabled: !_busy,
          controller: _lanPortController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: AppLocalizations.of(context).text('port'),
            border: const OutlineInputBorder(),
          ),
        ),
      ];

  List<Widget> _directFields({required bool showPairingCode}) => [
        if (showPairingCode)
          TextField(
            controller: _directPairingCodeController,
            decoration: InputDecoration(
              labelText:
                  AppLocalizations.of(context).text('pairing_code_from_host'),
              border: const OutlineInputBorder(),
            ),
          ),
        const SizedBox(height: 12),
      ];
}
