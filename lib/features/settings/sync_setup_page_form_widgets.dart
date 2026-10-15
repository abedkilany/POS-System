// ignore_for_file: invalid_use_of_protected_member
part of 'sync_setup_page.dart';

extension _SyncSetupFormWidgets on _SyncSetupPageState {
  Widget _buildModeSelector(BuildContext context, AppLocalizations tr) {
    void selectMode(_ConnectMode mode) {
      if (_busy || _mode == mode) return;
      setState(() {
        _mode = mode;
        _status = '';
        _statusType = _SetupStatus.idle;
        _qrExpiresAt = null;
        _qrStatus = _ClientPairingState.noCode;
        _syncQrStatusFromInput();
      });
    }

    final segments = [
      ButtonSegment(
          value: _ConnectMode.lan,
          label: Text(tr.text('connection_lan')),
          icon: const Icon(Icons.wifi_outlined)),
      ButtonSegment(
          value: _ConnectMode.direct,
          label: Text(tr.text('direct')),
          icon: const Icon(Icons.link_outlined)),
    ];

    if (!VentioResponsive.isMobile(context)) {
      return SegmentedButton<_ConnectMode>(
        segments: segments,
        selected: {_mode},
        onSelectionChanged: _busy ? null : (value) => selectMode(value.first),
      );
    }

    Widget mobileButton(_ConnectMode mode, IconData icon, String label) {
      final selected = _mode == mode;
      final buttonChild = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Text(label, overflow: TextOverflow.ellipsis),
        ],
      );
      return SizedBox(
        width: double.infinity,
        child: selected
            ? FilledButton(
                onPressed: _busy ? null : () => selectMode(mode),
                child: buttonChild)
            : OutlinedButton(
                onPressed: _busy ? null : () => selectMode(mode),
                child: buttonChild),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        mobileButton(
            _ConnectMode.lan, Icons.wifi_outlined, tr.text('connection_lan')),
        const SizedBox(height: 8),
        mobileButton(_ConnectMode.direct, Icons.link_outlined, 'Direct'),
      ],
    );
  }

  Widget _buildHeader(
      BuildContext context, AppLocalizations tr, ColorScheme color) {
    return Column(
      children: [
        Icon(Icons.sync_alt_rounded, size: 56, color: color.primary),
        const SizedBox(height: 16),
        Text(tr.text('connect_device_to_store'),
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(tr.text('connect_device_to_store_desc'),
            textAlign: TextAlign.center),
      ],
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  ({String label, IconData icon, Color background, Color foreground})
      _qrStatusData(BuildContext context, AppLocalizations tr) {
    final color = Theme.of(context).colorScheme;
    return switch (_qrStatus) {
      _ClientPairingState.ready => (
          label: tr.text('connection_state_pending'),
          icon: Icons.check_circle_outline,
          background: Colors.green.withValues(alpha: 0.12),
          foreground: Colors.green.shade700
        ),
      _ClientPairingState.connecting => (
          label: tr.text('connection_state_connecting'),
          icon: Icons.sync_rounded,
          background: color.primaryContainer,
          foreground: color.onPrimaryContainer
        ),
      _ClientPairingState.expired => (
          label: tr.text('pairing_status_expired'),
          icon: Icons.timer_off_outlined,
          background: Colors.orange.withValues(alpha: 0.14),
          foreground: Colors.orange.shade800
        ),
      _ClientPairingState.connected => (
          label: tr.text('connection_state_active'),
          icon: Icons.done_all_outlined,
          background: Colors.green.withValues(alpha: 0.12),
          foreground: Colors.green.shade700
        ),
      _ClientPairingState.failed => (
          label: tr.text('connection_state_error'),
          icon: Icons.error_outline,
          background: color.errorContainer,
          foreground: color.onErrorContainer
        ),
      _ClientPairingState.noCode => (
          label: tr.text('pairing_status_no_code_entered'),
          icon: Icons.edit_note_outlined,
          background: Colors.grey.withValues(alpha: 0.16),
          foreground: color.onSurfaceVariant
        ),
    };
  }

  Widget _qrStatusBadge(BuildContext context, AppLocalizations tr) {
    final data = _qrStatusData(context, tr);
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

  Color _qrBorderColor(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return switch (_qrStatus) {
      _ClientPairingState.ready => Colors.green,
      _ClientPairingState.connecting => color.primary,
      _ClientPairingState.connected => Colors.green,
      _ClientPairingState.expired => Colors.orange,
      _ClientPairingState.failed => color.error,
      _ClientPairingState.noCode => color.outlineVariant,
    };
  }

  Widget _buildConnectionStateCard(BuildContext context, AppLocalizations tr) {
    final color = Theme.of(context).colorScheme;
    final icon = _busy
        ? Icons.sync_rounded
        : _statusType == _SetupStatus.error
            ? Icons.error_outline
            : _statusType == _SetupStatus.success
                ? Icons.check_circle_outline
                : Icons.radio_button_unchecked;
    final title = _busy
        ? tr.text('connection_state_connecting')
        : _statusType == _SetupStatus.error
            ? tr.text('connection_state_error')
            : _statusType == _SetupStatus.success
                ? tr.text('connection_state_active')
                : tr.text('connection_state_pending');
    final subtitle = _mode == _ConnectMode.direct
        ? 'Pair with the Host through Direct.'
        : tr.text('lan_pairing_code_helper');
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.primaryContainer,
          foregroundColor: color.onPrimaryContainer,
          child: Icon(icon),
        ),
        title: Text(title),
        subtitle: Text(subtitle),
      ),
    );
  }

  Widget _buildQrCard(BuildContext context, AppLocalizations tr) {
    final color = Theme.of(context).colorScheme;
    final hasCode = _activePairingCode.isNotEmpty;
    final borderColor = _qrBorderColor(context);
    final helper = switch (_qrStatus) {
      _ClientPairingState.noCode => tr.text('scan_or_enter_host_pairing_code'),
      _ClientPairingState.ready =>
        tr.text('pairing_code_ready_to_connect_help'),
      _ClientPairingState.connecting =>
        tr.text('connecting_downloading_store_data'),
      _ClientPairingState.connected => tr.text('connected_store_sign_in'),
      _ClientPairingState.expired => tr.text('pairing_code_expired_or_used'),
      _ClientPairingState.failed => tr.text('connection_failed_check_code'),
    };
    return Card.outlined(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side:
            BorderSide(color: borderColor.withValues(alpha: 0.65), width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final compactHeader = constraints.maxWidth < 430;
                final titleColumn = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr.text('scan_host_qr_code'),
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasCode
                          ? tr.text('pairing_code_ready_to_connect_help')
                          : tr.text('scan_or_enter_host_pairing_code'),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                );
                final iconBox = Container(
                  width: compactHeader ? 44 : 52,
                  height: compactHeader ? 44 : 52,
                  decoration: BoxDecoration(
                    color: color.secondaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.qr_code_2_rounded,
                      color: color.onSecondaryContainer),
                );

                if (compactHeader) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          iconBox,
                          const SizedBox(width: 10),
                          Expanded(child: titleColumn),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: _qrStatusBadge(context, tr)),
                    ],
                  );
                }

                return Row(
                  children: [
                    iconBox,
                    const SizedBox(width: 12),
                    Expanded(child: titleColumn),
                    const SizedBox(width: 12),
                    Flexible(
                        child: Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: _qrStatusBadge(context, tr))),
                  ],
                );
              },
            ),
            if (hasCode) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _qrStatusData(context, tr).background,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(_qrStatusData(context, tr).icon,
                        color: _qrStatusData(context, tr).foreground),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(helper,
                            style: TextStyle(
                                color: _qrStatusData(context, tr).foreground))),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _scanQr,
                icon: const Icon(Icons.qr_code_scanner),
                label: Text(tr.text('scan_qr_code')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildLanFields(AppLocalizations tr) => [
        TextField(
          controller: _hostController,
          enabled: !_busy,
          decoration: InputDecoration(
            labelText: tr.text('host_ip'),
            helperText: tr.text('host_ip_helper'),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _portController,
          enabled: !_busy,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
              labelText: tr.text('port'), border: const OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _lanTokenController,
          enabled: !_busy,
          onChanged: (_) => setState(_syncQrStatusFromInput),
          decoration: InputDecoration(
            labelText: tr.text('lan_pairing_code'),
            helperText: tr.text('lan_pairing_code_helper'),
            border: const OutlineInputBorder(),
          ),
        ),
      ];

  List<Widget> _buildDirectFields(AppLocalizations tr) => [
        TextField(
          controller: _directPairingCodeController,
          enabled: !_busy,
          onChanged: (_) => setState(_syncQrStatusFromInput),
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: tr.text('direct_pairing_code'),
            helperText: tr.text('direct_pairing_code_helper'),
            border: const OutlineInputBorder(),
          ),
        ),
      ];
}
