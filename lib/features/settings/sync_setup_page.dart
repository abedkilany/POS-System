import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/utils/responsive.dart';
import '../../core/services/direct_sync_settings.dart';
import '../../core/services/lan_sync_service.dart';
import '../../core/sync_unified/sync_unified.dart';
import '../../core/services/sync_diagnostics_log.dart';
import '../../core/snapshot/unified_snapshot_progress.dart';
import '../../data/app_store.dart';
import '../../core/services/page_timing_scope.dart';
import '../barcode/barcode_scanner_page.dart';

part 'sync_setup_page_connection_state.dart';
part 'sync_setup_page_pairing.dart';
part 'sync_setup_page_status_widgets.dart';
part 'sync_setup_page_form_widgets.dart';

enum _ConnectMode { lan, direct }

enum _SetupStatus { idle, info, success, warning, error }

enum _ClientPairingState {
  noCode,
  ready,
  connecting,
  connected,
  failed,
  expired
}

class SyncSetupPage extends StatefulWidget {
  const SyncSetupPage({super.key, required this.store, required this.onDone});

  final AppStore store;
  final Future<void> Function() onDone;

  @override
  State<SyncSetupPage> createState() => _SyncSetupPageState();
}

class _SyncSetupPageState extends State<SyncSetupPage> {
  final _hostController =
      TextEditingController(text: LanSyncSettings.load().host);
  final _portController =
      TextEditingController(text: LanSyncSettings.load().port.toString());
  final _lanTokenController = TextEditingController(
    text: LanSyncSettings.load().secret.trim(),
  );

  final _directPairingCodeController = TextEditingController();

  UnifiedSyncEngine _lanEngine() => UnifiedSyncFactory.lanEngine(
        widget.store,
        settings: LanSyncSettings.load().copyWith(
          host: _hostController.text.trim(),
          port: _port,
          secret: _lanTokenController.text.trim(),
          mode: LanSyncDeviceMode.client,
          setupComplete: true,
          hostModeEnabled: false,
        ),
      );

  _ConnectMode _mode = _ConnectMode.direct;
  bool _busy = false;
  String _status = '';
  _SetupStatus _statusType = _SetupStatus.idle;
  double? _snapshotProgressValue;
  String _snapshotProgressLabel = '';
  final List<String> _connectionLog = <String>[];
  Timer? _qrCountdownTimer;
  DateTime? _qrExpiresAt;
  _ClientPairingState _qrStatus = _ClientPairingState.noCode;

  int get _port => int.tryParse(_portController.text.trim()) ?? 8787;

  String get _activePairingCode => _mode == _ConnectMode.direct
      ? _directPairingCodeController.text.trim()
      : _lanTokenController.text.trim();

  @override
  void initState() {
    super.initState();
    _syncQrStatusFromInput();
    _startQrCountdownTimer();
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _lanTokenController.dispose();
    _directPairingCodeController.dispose();
    _qrCountdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final color = Theme.of(context).colorScheme;
    final isMobile = VentioResponsive.isMobile(context);
    final outerPadding = VentioResponsive.pagePadding(context);
    final cardMargin = EdgeInsets.all(isMobile ? 8 : 24);

    return Scaffold(
      appBar: AppBar(
        title: Text(tr.text('connect_to_store')),
      ),
      body: Stack(
        children: [
          SafeArea(
            child: Align(
              alignment: AlignmentDirectional.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: VentioResponsive.clampToScreen(
                    context,
                    860,
                    min: 280,
                    horizontalPadding: outerPadding * 2,
                  ),
                ),
                child: Card(
                  margin: cardMargin,
                  child: Padding(
                    padding: VentioResponsive.pageInsets(context),
                    child: ListView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      children: [
                        _buildHeader(context, tr, color),
                        SizedBox(height: isMobile ? 18 : 24),
                        _buildSectionTitle(context,
                            tr.text('connection_method'), Icons.hub_outlined),
                        const SizedBox(height: 12),
                        _buildModeSelector(context, tr),
                        const SizedBox(height: 16),
                        _buildConnectionStateCard(context, tr),
                        const SizedBox(height: 16),
                        _buildQrCard(context, tr),
                        const SizedBox(height: 16),
                        _buildSectionTitle(
                            context,
                            _mode == _ConnectMode.direct
                                ? 'Direct connection'
                                : 'lan_setup',
                            Icons.tune_outlined),
                        const SizedBox(height: 12),
                        if (_mode == _ConnectMode.direct)
                          ..._buildDirectFields(tr),
                        if (_mode == _ConnectMode.lan) ..._buildLanFields(tr),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _busy ? null : _connect,
                            icon: const Icon(Icons.check_circle_outline),
                            label: Text(tr.text('connect_to_store'),
                                overflow: TextOverflow.ellipsis),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_status.isNotEmpty) _buildStatusBanner(context),
                        if (_connectionLog.isNotEmpty ||
                            SyncDiagnosticsLog.lines.value
                                .any((line) => line.contains('[DIRECT_')))
                          _buildConnectionLogCard(context),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_busy)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                        maxWidth: VentioResponsive.modalMaxWidth(context, 520)),
                    child: Card(
                      margin: EdgeInsets.all(outerPadding),
                      child: Padding(
                        padding: VentioResponsive.pageInsets(context),
                        child: UnifiedSnapshotProgressView(
                          value: _snapshotProgressValue,
                          label: _snapshotProgressLabel.isEmpty
                              ? (_status.isEmpty
                                  ? tr.text('connecting_downloading_store_data')
                                  : _status)
                              : _snapshotProgressLabel,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
