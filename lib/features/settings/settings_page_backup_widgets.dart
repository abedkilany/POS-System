part of 'settings_page.dart';

class _ScannerFeedbackSettingsCard extends StatefulWidget {
  const _ScannerFeedbackSettingsCard();

  @override
  State<_ScannerFeedbackSettingsCard> createState() =>
      _ScannerFeedbackSettingsCardState();
}

class _ScannerFeedbackSettingsCardState
    extends State<_ScannerFeedbackSettingsCard> {
  late BarcodeFeedbackSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = BarcodeFeedbackService.loadSettings();
  }

  Future<void> _save(BarcodeFeedbackSettings value) async {
    setState(() => _settings = value);
    await BarcodeFeedbackService.saveSettings(value);
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: VentioResponsive.pageInsets(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.qr_code_scanner_outlined),
              title: Text(tr.text('scanner_feedback')),
              subtitle: Text(tr.text('scanner_feedback_desc')),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr.text('scanner_feedback_sound')),
              subtitle: Text(tr.text('scanner_feedback_sound_desc')),
              value: _settings.soundEnabled,
              onChanged: (value) =>
                  _save(_settings.copyWith(soundEnabled: value)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr.text('scanner_feedback_vibration')),
              subtitle: Text(tr.text('scanner_feedback_vibration_desc')),
              value: _settings.vibrationEnabled,
              onChanged: (value) =>
                  _save(_settings.copyWith(vibrationEnabled: value)),
            ),
            const SizedBox(height: 8),
            Text(tr.text('scanner_feedback_volume')),
            Slider(
              value: _settings.volume,
              onChanged: _settings.soundEnabled
                  ? (value) => _save(_settings.copyWith(volume: value))
                  : null,
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                onPressed: () => BarcodeFeedbackService.play(force: true),
                icon: const Icon(Icons.volume_up_outlined),
                label: Text(tr.text('test_scanner_feedback')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AutoLocalBackupSettingsCard extends StatefulWidget {
  const _AutoLocalBackupSettingsCard({required this.store});

  final ApplicationSession store;

  @override
  State<_AutoLocalBackupSettingsCard> createState() =>
      _AutoLocalBackupSettingsCardState();
}

class _AutoLocalBackupSettingsCardState
    extends State<_AutoLocalBackupSettingsCard> {
  LocalAutoBackupSettings? _settings;
  bool _saving = false;
  bool _hasChanges = false;
  bool _expanded = false;
  final TextEditingController _pathController = TextEditingController();
  final TextEditingController _dailyController = TextEditingController();
  final TextEditingController _weeklyController = TextEditingController();
  final TextEditingController _monthlyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _pathController.addListener(_markChanged);
    _dailyController.addListener(_markChanged);
    _weeklyController.addListener(_markChanged);
    _monthlyController.addListener(_markChanged);
    _load();
  }

  @override
  void dispose() {
    _pathController.dispose();
    _dailyController.dispose();
    _weeklyController.dispose();
    _monthlyController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final settings = await LocalAutoBackupService.loadSettings();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _pathController.text = settings.locationPath;
      _dailyController.text = settings.dailyCount.toString();
      _weeklyController.text = settings.weeklyCount.toString();
      _monthlyController.text = settings.monthlyCount.toString();
      _hasChanges = false;
    });
  }

  void _markChanged() {
    final current = _settings;
    if (current == null || _saving) return;
    final changed =
        _settingsSignature(_draftSettings()) != _settingsSignature(current);
    if (changed != _hasChanges && mounted) {
      setState(() => _hasChanges = changed);
    }
  }

  String _settingsSignature(LocalAutoBackupSettings settings) =>
      '${settings.enabled}|${settings.locationPath.trim()}|${settings.dailyCount}|${settings.weeklyCount}|${settings.monthlyCount}';

  LocalAutoBackupSettings _draftSettings({bool? enabled}) {
    final current = _settings!;
    return current.copyWith(
      enabled: enabled ?? current.enabled,
      locationPath: _pathController.text.trim(),
      dailyCount:
          _count(_dailyController, LocalAutoBackupService.defaultDailyCount),
      weeklyCount:
          _count(_weeklyController, LocalAutoBackupService.defaultWeeklyCount),
      monthlyCount: _count(
          _monthlyController, LocalAutoBackupService.defaultMonthlyCount),
    );
  }

  int _count(TextEditingController controller, int fallback) {
    final value = int.tryParse(controller.text.trim());
    if (value == null || value <= 0) return fallback;
    return value;
  }

  Future<void> _save({bool? enabled}) async {
    final current = _settings;
    if (current == null) return;
    final tr = AppLocalizations.of(context);
    setState(() => _saving = true);
    final next = _draftSettings(enabled: enabled);
    try {
      await LocalAutoBackupService.saveSettings(next);
      if (!mounted) return;
      setState(() {
        _settings = next;
        _saving = false;
        _hasChanges = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr.text('local_backup_settings_saved'))));
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr.format(
              'could_not_save_backup_settings', {'error': error.toString()}))));
    }
  }

  Future<void> _pickDirectory() async {
    final tr = AppLocalizations.of(context);
    final picked = await FilePicker.platform
        .getDirectoryPath(dialogTitle: tr.text('choose_backup_folder'));
    if (picked == null || picked.trim().isEmpty) return;
    _pathController.text = picked;
  }

  Future<void> _backupNow() async {
    final tr = AppLocalizations.of(context);
    try {
      if (_hasChanges) {
        await _save();
      }
      final settings = await LocalAutoBackupService.loadSettings();
      await LocalAutoBackupService.createBackupNow(widget.store,
          settings: settings, reason: 'manual');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr.text('local_backup_completed'))));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              tr.format('local_backup_failed', {'error': error.toString()}))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    final theme = Theme.of(context);
    final tr = AppLocalizations.of(context);
    if (settings == null) {
      return const Center(child: LinearProgressIndicator());
    }
    final disabled = widget.store.runtime.identity.isClient;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.schedule_outlined),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      tr.text('automatic_local_backup'),
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Icon(_expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down),
                  const SizedBox(width: 8),
                  Switch(
                    value: !disabled && settings.enabled,
                    onChanged: disabled || _saving
                        ? null
                        : (value) => _save(enabled: value),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 8),
            Text(disabled
                ? tr.text('local_backup_host_only')
                : tr.text('local_backup_background_desc')),
            const SizedBox(height: 12),
            TextField(
              controller: _pathController,
              enabled: !disabled && !_saving,
              decoration: InputDecoration(
                labelText: tr.text('backup_location'),
                helperText: tr.text('backup_location_default'),
                suffixIcon: IconButton(
                  tooltip: tr.text('browse'),
                  onPressed: disabled || _saving ? null : _pickDirectory,
                  icon: const Icon(Icons.folder_open_outlined),
                ),
              ),
              onSubmitted: (_) {
                if (_hasChanges) _save();
              },
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final itemWidth = constraints.maxWidth < 620
                    ? constraints.maxWidth
                    : (constraints.maxWidth - 24) / 3;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                        width: itemWidth,
                        child: _countField(_dailyController,
                            tr.text('daily_copies'), disabled)),
                    SizedBox(
                        width: itemWidth,
                        child: _countField(_weeklyController,
                            tr.text('weekly_copies'), disabled)),
                    SizedBox(
                        width: itemWidth,
                        child: _countField(_monthlyController,
                            tr.text('monthly_copies'), disabled)),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: disabled || _saving || !_hasChanges
                      ? null
                      : () => _save(),
                  icon: const Icon(Icons.save_outlined),
                  label: Text(tr.text('save_backup_settings')),
                ),
                FilledButton.icon(
                  onPressed: disabled || _saving ? null : _backupNow,
                  icon: const Icon(Icons.backup_outlined),
                  label: Text(tr.text('backup_now')),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _countField(
      TextEditingController controller, String label, bool disabled) {
    return TextField(
      controller: controller,
      enabled: !disabled && !_saving,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: label),
      onSubmitted: (_) {
        if (_hasChanges) _save();
      },
    );
  }
}

class _GoogleDriveBackupSettingsCard extends StatefulWidget {
  const _GoogleDriveBackupSettingsCard({required this.store});

  final ApplicationSession store;

  @override
  State<_GoogleDriveBackupSettingsCard> createState() =>
      _GoogleDriveBackupSettingsCardState();
}

class _GoogleDriveBackupSettingsCardState
    extends State<_GoogleDriveBackupSettingsCard> {
  GoogleDriveBackupSettings? _settings;
  bool _saving = false;
  bool _hasChanges = false;
  bool _expanded = false;
  bool _showAdvancedSetup = false;
  int _developerTapCount = 0;
  final TextEditingController _clientIdController = TextEditingController();
  final TextEditingController _clientSecretController = TextEditingController();
  final TextEditingController _folderIdController = TextEditingController();
  final TextEditingController _dailyController = TextEditingController();
  final TextEditingController _weeklyController = TextEditingController();
  final TextEditingController _monthlyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    for (final controller in [
      _clientIdController,
      _clientSecretController,
      _folderIdController,
      _dailyController,
      _weeklyController,
      _monthlyController,
    ]) {
      controller.addListener(_markChanged);
    }
    _load();
  }

  @override
  void dispose() {
    _clientIdController.dispose();
    _clientSecretController.dispose();
    _folderIdController.dispose();
    _dailyController.dispose();
    _weeklyController.dispose();
    _monthlyController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final settings = await GoogleDriveBackupService.loadSettings();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _clientIdController.text = settings.clientId;
      _clientSecretController.text = settings.clientSecret;
      _folderIdController.text = settings.folderId;
      _dailyController.text = settings.dailyCount.toString();
      _weeklyController.text = settings.weeklyCount.toString();
      _monthlyController.text = settings.monthlyCount.toString();
      _hasChanges = false;
    });
  }

  void _markChanged() {
    final current = _settings;
    if (current == null || _saving) return;
    final changed =
        _settingsSignature(_draftSettings()) != _settingsSignature(current);
    if (changed != _hasChanges && mounted) {
      setState(() => _hasChanges = changed);
    }
  }

  String _settingsSignature(GoogleDriveBackupSettings settings) =>
      '${settings.enabled}|${settings.clientId.trim()}|${settings.clientSecret.trim()}|${settings.folderId.trim()}|${settings.dailyCount}|${settings.weeklyCount}|${settings.monthlyCount}';

  GoogleDriveBackupSettings _draftSettings({bool? enabled}) {
    final current = _settings!;
    return current.copyWith(
      enabled: enabled ?? current.enabled,
      clientId: _clientIdController.text.trim(),
      clientSecret: _clientSecretController.text.trim(),
      folderId: _folderIdController.text.trim(),
      dailyCount:
          _count(_dailyController, GoogleDriveBackupService.defaultDailyCount),
      weeklyCount: _count(
          _weeklyController, GoogleDriveBackupService.defaultWeeklyCount),
      monthlyCount: _count(
          _monthlyController, GoogleDriveBackupService.defaultMonthlyCount),
    );
  }

  int _count(TextEditingController controller, int fallback) {
    final value = int.tryParse(controller.text.trim());
    if (value == null || value <= 0) return fallback;
    return value;
  }

  Future<GoogleDriveBackupSettings?> _save({bool? enabled}) async {
    final current = _settings;
    if (current == null) return null;
    final tr = AppLocalizations.of(context);
    setState(() => _saving = true);
    final next = _draftSettings(enabled: enabled);
    try {
      await GoogleDriveBackupService.saveSettings(next);
      if (!mounted) return next;
      setState(() {
        _settings = next;
        _saving = false;
        _hasChanges = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr.text('google_drive_backup_settings_saved'))));
      return next;
    } catch (error) {
      if (!mounted) return null;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr.format('could_not_save_google_drive_settings',
              {'error': error.toString()}))));
      return null;
    }
  }

  Future<void> _startConnect() async {
    final tr = AppLocalizations.of(context);
    setState(() => _saving = true);
    try {
      final settings = _hasChanges ? await _save() : _settings;
      if (settings == null) {
        if (mounted) setState(() => _saving = false);
        return;
      }
      final next = await GoogleDriveBackupService.connectWithServer(settings);
      if (!mounted) return;
      setState(() {
        _settings = next;
        _saving = false;
        _hasChanges = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr.text('google_drive_connected'))));
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr.format(
              'google_drive_connection_failed', {'error': error.toString()}))));
    }
  }

  Future<void> _disconnect() async {
    final tr = AppLocalizations.of(context);
    setState(() => _saving = true);
    await GoogleDriveBackupService.disconnect();
    await _load();
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr.text('google_drive_disconnected'))));
  }

  Future<void> _importGoogleCredentialsFile() async {
    final tr = AppLocalizations.of(context);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final bytes = result.files.single.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw Exception(tr.text('empty_google_credentials_file'));
      }
      final decoded = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final section = decoded['installed'] is Map
          ? decoded['installed'] as Map
          : decoded['web'] is Map
              ? decoded['web'] as Map
              : null;
      if (section == null) {
        throw Exception(tr.text('invalid_google_credentials_file'));
      }
      final clientId = (section['client_id'] ?? '').toString().trim();
      final clientSecret = (section['client_secret'] ?? '').toString().trim();
      if (clientId.isEmpty) {
        throw Exception(tr.text('google_client_id_not_found'));
      }
      _clientIdController.text = clientId;
      _clientSecretController.text = clientSecret;
      final saved = await _save();
      if (!mounted || saved == null) return;
      setState(() => _showAdvancedSetup = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr.text('google_credentials_imported_connect_now'))));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr.format('could_not_import_google_credentials',
              {'error': error.toString()}))));
    }
  }

  void _handleDeveloperTap() {
    final tr = AppLocalizations.of(context);
    if (_showAdvancedSetup) return;
    _developerTapCount += 1;
    if (_developerTapCount >= 5) {
      _developerTapCount = 0;
      setState(() => _showAdvancedSetup = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr.text('developer_setup_unlocked'))),
      );
    }
  }

  Future<void> _copyDriveFolderLink() async {
    final tr = AppLocalizations.of(context);
    final folderId = _settings?.folderId.trim() ?? '';
    if (folderId.isEmpty) return;
    await Clipboard.setData(ClipboardData(
        text: 'https://drive.google.com/drive/folders/$folderId'));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr.text('drive_folder_link_copied'))));
  }

  Future<void> _backupNow() async {
    final tr = AppLocalizations.of(context);
    try {
      if (_hasChanges) {
        await _save();
      }
      final settings = await GoogleDriveBackupService.loadSettings();
      await GoogleDriveBackupService.createBackupNow(widget.store,
          settings: settings, reason: 'manual');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr.text('google_drive_backup_completed'))));
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr.format(
              'google_drive_backup_failed', {'error': error.toString()}))));
    }
  }

  Future<void> _downloadFromDrive() async {
    final tr = AppLocalizations.of(context);
    try {
      if (_hasChanges) {
        await _save();
      }
      final settings = await GoogleDriveBackupService.loadSettings();
      final files =
          await GoogleDriveBackupService.listBackupFiles(settings: settings);
      if (!mounted) return;
      if (files.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr.text('no_google_drive_backups_found'))));
        return;
      }
      final selected = await showDialog<GoogleDriveBackupFile>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(tr.text('download_backup_from_drive')),
          content: SizedBox(
            width: VentioResponsive.modalMaxWidth(context, 520),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: files.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final file = files[index];
                return ListTile(
                  leading: const Icon(Icons.download),
                  title: Text(file.name),
                  subtitle: Text(
                      '${file.category}${file.createdAt == null ? '' : ' - ${_formatDriveBackupDate(file.createdAt!)}'}'),
                  onTap: () => Navigator.pop(dialogContext, file),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(tr.text('cancel')),
            ),
          ],
        ),
      );
      if (selected == null) return;
      final bytes = await GoogleDriveBackupService.downloadBackupFile(selected,
          settings: settings);
      await downloadBinaryFile(
        filename: selected.name,
        bytes: bytes,
        dialogTitle: tr.text('save_google_drive_backup'),
        cancelMessage: tr.text('backup_download_cancelled'),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr.text('google_drive_backup_downloaded'))));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr.format('google_drive_backup_download_failed',
              {'error': error.toString()}))));
    }
  }

  String _formatDriveBackupDate(DateTime value) {
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    final theme = Theme.of(context);
    final tr = AppLocalizations.of(context);
    if (settings == null) {
      return const Center(child: LinearProgressIndicator());
    }
    final disabled = widget.store.runtime.identity.isClient;
    final connected = settings.isAuthorized;
    final showDeveloperSetup = _showAdvancedSetup;
    final googleConfigured =
        VpsControlPlaneSettings.load().apiBaseUrl.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _expanded = !_expanded),
            onLongPress: _handleDeveloperTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.upload),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      tr.text('google_drive_backup'),
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Icon(_expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down),
                  const SizedBox(width: 8),
                  Switch(
                    value: !disabled && connected && settings.enabled,
                    onChanged: disabled || _saving || !connected
                        ? null
                        : (value) => _save(enabled: value),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 8),
            Text(disabled
                ? tr.text('google_drive_backup_host_only')
                : connected
                    ? tr.text('google_drive_backup_available_desc')
                    : googleConfigured
                        ? tr.text('google_drive_backup_connect_first')
                        : tr.text('google_drive_backup_not_configured')),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(connected
                  ? Icons.check_circle_outline
                  : googleConfigured
                      ? Icons.account_circle_outlined
                      : Icons.info_outline),
              title: Text(connected
                  ? tr.text('google_drive_is_connected')
                  : googleConfigured
                      ? tr.text('connect_with_google')
                      : tr.text('google_drive_not_ready')),
              subtitle: Text(connected
                  ? tr.text('google_drive_backup_upload_desc')
                  : googleConfigured
                      ? tr.text('google_drive_account_desc')
                      : tr.text('google_drive_packaged_server_required')),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final itemWidth = constraints.maxWidth < 620
                    ? constraints.maxWidth
                    : (constraints.maxWidth - 24) / 3;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                        width: itemWidth,
                        child: _countField(_dailyController,
                            tr.text('daily_copies'), disabled)),
                    SizedBox(
                        width: itemWidth,
                        child: _countField(_weeklyController,
                            tr.text('weekly_copies'), disabled)),
                    SizedBox(
                        width: itemWidth,
                        child: _countField(_monthlyController,
                            tr.text('monthly_copies'), disabled)),
                  ],
                );
              },
            ),
            if (showDeveloperSetup) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(tr.text('google_packaging_only_desc')),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed:
                    disabled || _saving ? null : _importGoogleCredentialsFile,
                icon: const Icon(Icons.file_upload_outlined),
                label: Text(tr.text('import_google_credentials_file')),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _clientIdController,
                enabled: !disabled && !_saving,
                decoration: InputDecoration(
                  labelText: tr.text('google_oauth_client_id'),
                  helperText: tr.text('one_time_developer_setup_desc'),
                ),
                onSubmitted: (_) {
                  if (_hasChanges) _save();
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _clientSecretController,
                enabled: !disabled && !_saving,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: tr.text('google_oauth_client_secret_optional'),
                  helperText: tr.text('google_oauth_client_secret_helper'),
                ),
                onSubmitted: (_) {
                  if (_hasChanges) _save();
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _folderIdController,
                enabled: !disabled && !_saving,
                decoration: InputDecoration(
                  labelText: tr.text('drive_folder_id_optional'),
                  helperText: tr.text('drive_folder_id_helper'),
                ),
                onSubmitted: (_) {
                  if (_hasChanges) _save();
                },
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: disabled || _saving || !_hasChanges
                      ? null
                      : () => _save(),
                  icon: const Icon(Icons.save_outlined),
                  label: Text(tr.text('save_backup_settings')),
                ),
                OutlinedButton.icon(
                  onPressed: disabled || _saving || !googleConfigured
                      ? null
                      : _startConnect,
                  icon: const Icon(Icons.account_circle_outlined),
                  label: Text(connected
                      ? tr.text('reconnect_with_google')
                      : tr.text('connect_with_google')),
                ),
                FilledButton.icon(
                  onPressed:
                      disabled || _saving || !connected ? null : _backupNow,
                  icon: const Icon(Icons.upload),
                  label: Text(tr.text('backup_now')),
                ),
                OutlinedButton.icon(
                  onPressed: disabled || _saving || !connected
                      ? null
                      : _downloadFromDrive,
                  icon: const Icon(Icons.download),
                  label: Text(tr.text('download_from_drive')),
                ),
                if (connected && settings.folderId.trim().isNotEmpty)
                  OutlinedButton.icon(
                    onPressed:
                        disabled || _saving ? null : _copyDriveFolderLink,
                    icon: const Icon(Icons.folder_open_outlined),
                    label: Text(tr.text('copy_drive_folder_link')),
                  ),
                if (connected)
                  TextButton.icon(
                    onPressed: disabled || _saving ? null : _disconnect,
                    icon: const Icon(Icons.link_off_outlined),
                    label: Text(tr.text('disconnect')),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _countField(
      TextEditingController controller, String label, bool disabled) {
    return TextField(
      controller: controller,
      enabled: !disabled && !_saving,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: label),
      onSubmitted: (_) {
        if (_hasChanges) _save();
      },
    );
  }
}

class _BackupSummaryCard extends StatelessWidget {
  const _BackupSummaryCard({required this.summary});

  final BackupSummary summary;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: VentioResponsive.cardInsets(context),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: _BackupSummaryDetails(summary: summary),
    );
  }
}

class _BackupSummaryDetails extends StatelessWidget {
  const _BackupSummaryDetails({required this.summary});

  final BackupSummary summary;

  String _formatDate(DateTime? value) {
    if (value == null) return '—';
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr.text('current_backup_status'),
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 12),
        _InfoGrid(
          items: [
            _InfoGridItem(
                Icons.store_outlined, tr.text('store_name'), summary.storeName),
            _InfoGridItem(Icons.new_releases_outlined,
                tr.text('backup_version'), 'V${summary.version}'),
            _InfoGridItem(Icons.event_outlined, tr.text('backup_date'),
                _formatDate(summary.generatedAt)),
            _InfoGridItem(Icons.inventory_2_outlined, tr.text('products'),
                summary.productsCount.toString()),
            _InfoGridItem(Icons.people_alt_outlined, tr.text('customers'),
                summary.customersCount.toString()),
            _InfoGridItem(Icons.point_of_sale_outlined, tr.text('sales'),
                summary.salesCount.toString()),
            _InfoGridItem(Icons.local_shipping_outlined, tr.text('suppliers'),
                summary.suppliersCount.toString()),
            _InfoGridItem(Icons.receipt_long_outlined, tr.text('expenses'),
                summary.expensesCount.toString()),
          ],
        ),
      ],
    );
  }
}
