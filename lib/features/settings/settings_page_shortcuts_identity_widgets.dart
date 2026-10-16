part of 'settings_page.dart';

class _KeyboardShortcutsSettingsCard extends StatefulWidget {
  const _KeyboardShortcutsSettingsCard();

  @override
  State<_KeyboardShortcutsSettingsCard> createState() =>
      _KeyboardShortcutsSettingsCardState();
}

class _KeyboardShortcutsSettingsCardState
    extends State<_KeyboardShortcutsSettingsCard> {
  late SaleShortcutSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = SaleShortcutSettings.load();
    SaleShortcutSettings.revision.addListener(_handleShortcutSettingsChanged);
  }

  void _handleShortcutSettingsChanged() {
    if (!mounted) return;
    setState(() => _settings = SaleShortcutSettings.load());
  }

  @override
  void dispose() {
    SaleShortcutSettings.revision
        .removeListener(_handleShortcutSettingsChanged);
    super.dispose();
  }

  String _keyLabel(AppLocalizations tr, String keyName) {
    if (keyName == SaleShortcutSettings.noneKey) {
      return tr.text('shortcut_none');
    }
    return keyName;
  }

  Future<void> _setSaleShortcut(
      SaleShortcutAction action, String keyName) async {
    final tr = AppLocalizations.of(context);
    if (_settings.isSaleKeyUsedByAnotherAction(keyName, action)) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr.text('shortcut_key_already_used'))));
      return;
    }
    final next = _settings.copyWithSaleActionKey(action, keyName);
    setState(() => _settings = next);
    await next.save();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(tr.text('shortcuts_saved'))));
  }

  Future<void> _setPaymentShortcut(
      SalePaymentShortcutAction action, String keyName) async {
    final tr = AppLocalizations.of(context);
    if (_settings.isPaymentKeyUsedByAnotherAction(keyName, action)) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr.text('shortcut_key_already_used'))));
      return;
    }
    final next = _settings.copyWithPaymentActionKey(action, keyName);
    setState(() => _settings = next);
    await next.save();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(tr.text('shortcuts_saved'))));
  }

  Future<void> _setPurchasesShortcut(
      PurchasesShortcutAction action, String keyName) async {
    final tr = AppLocalizations.of(context);
    if (_settings.isPurchasesKeyUsedByAnotherAction(keyName, action)) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr.text('shortcut_key_already_used'))));
      return;
    }
    final next = _settings.copyWithPurchasesActionKey(action, keyName);
    setState(() => _settings = next);
    await next.save();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(tr.text('shortcuts_saved'))));
  }

  Future<void> _setPurchaseDialogShortcut(
      PurchaseDialogShortcutAction action, String keyName) async {
    final tr = AppLocalizations.of(context);
    if (_settings.isPurchaseDialogKeyUsedByAnotherAction(keyName, action)) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr.text('shortcut_key_already_used'))));
      return;
    }
    final next = _settings.copyWithPurchaseDialogActionKey(action, keyName);
    setState(() => _settings = next);
    await next.save();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(tr.text('shortcuts_saved'))));
  }

  Future<void> _resetDefaults() async {
    final next = SaleShortcutSettings.defaults();
    setState(() => _settings = next);
    await next.save();
  }

  Widget _shortcutDropdown({
    required BuildContext context,
    required String? value,
    required ValueChanged<String> onChanged,
  }) {
    final tr = AppLocalizations.of(context);
    return DropdownButtonFormField<String>(
      initialValue: value ?? SaleShortcutSettings.noneKey,
      decoration: const InputDecoration(isDense: true),
      items: [
        for (final keyName in SaleShortcutSettings.availableKeys)
          DropdownMenuItem(value: keyName, child: Text(_keyLabel(tr, keyName))),
      ],
      onChanged: (value) {
        if (value == null) return;
        onChanged(value);
      },
    );
  }

  Widget _buildSaleShortcuts(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr.text('sale_page'),
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(tr.text('keyboard_shortcuts_sale_hint'),
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        for (final action in SaleShortcutAction.values) ...[
          Row(
            children: [
              Expanded(child: Text(tr.text(action.labelKey))),
              SizedBox(
                width: 160,
                child: _shortcutDropdown(
                  context: context,
                  value: _settings.saleBindings[action],
                  onChanged: (value) => _setSaleShortcut(action, value),
                ),
              ),
            ],
          ),
          const Divider(height: 18),
        ],
      ],
    );
  }

  Widget _buildPaymentShortcuts(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr.text('shortcut_page_sale_payment'),
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(tr.text('keyboard_shortcuts_payment_hint'),
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        for (final action in SalePaymentShortcutAction.values) ...[
          Row(
            children: [
              Expanded(child: Text(tr.text(action.labelKey))),
              SizedBox(
                width: 160,
                child: _shortcutDropdown(
                  context: context,
                  value: _settings.paymentBindings[action],
                  onChanged: (value) => _setPaymentShortcut(action, value),
                ),
              ),
            ],
          ),
          const Divider(height: 18),
        ],
      ],
    );
  }

  Widget _buildPurchasesShortcuts(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr.text('purchases'),
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(tr.text('keyboard_shortcuts_purchases_hint'),
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        for (final action in PurchasesShortcutAction.values) ...[
          Row(
            children: [
              Expanded(child: Text(tr.text(action.labelKey))),
              SizedBox(
                width: 160,
                child: _shortcutDropdown(
                  context: context,
                  value: _settings.purchasesBindings[action],
                  onChanged: (value) => _setPurchasesShortcut(action, value),
                ),
              ),
            ],
          ),
          const Divider(height: 18),
        ],
      ],
    );
  }

  Widget _buildPurchaseDialogShortcuts(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr.text('shortcut_page_purchase_dialog'),
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(tr.text('keyboard_shortcuts_purchase_dialog_hint'),
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        for (final action in PurchaseDialogShortcutAction.values) ...[
          Row(
            children: [
              Expanded(child: Text(tr.text(action.labelKey))),
              SizedBox(
                width: 160,
                child: _shortcutDropdown(
                  context: context,
                  value: _settings.purchaseDialogBindings[action],
                  onChanged: (value) =>
                      _setPurchaseDialogShortcut(action, value),
                ),
              ),
            ],
          ),
          const Divider(height: 18),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return _SectionCard(
      icon: Icons.keyboard_command_key_outlined,
      title: tr.text('keyboard_shortcuts'),
      subtitle: tr.text('keyboard_shortcuts_desc'),
      trailing: TextButton.icon(
        onPressed: _resetDefaults,
        icon: const Icon(Icons.restore_outlined),
        label: Text(tr.text('restore_defaults')),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSaleShortcuts(context),
          const SizedBox(height: 18),
          _buildPaymentShortcuts(context),
          const SizedBox(height: 18),
          _buildPurchasesShortcuts(context),
          const SizedBox(height: 18),
          _buildPurchaseDialogShortcuts(context),
        ],
      ),
    );
  }
}

class _SystemIdentityCard extends StatefulWidget {
  const _SystemIdentityCard({required this.store});

  final ApplicationSession store;

  @override
  State<_SystemIdentityCard> createState() => _SystemIdentityCardState();
}

class _SystemIdentityCardState extends State<_SystemIdentityCard> {
  DirectControlPlaneService _controlPlaneService() =>
      DirectControlPlaneService(widget.store);

  Future<void> _editDeviceName() async {
    final tr = AppLocalizations.of(context);
    final controller =
        TextEditingController(text: widget.store.runtime.identity.deviceName);
    String? errorText;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(tr.text('device_name')),
              content: TextField(
                controller: controller,
                autofocus: true,
                maxLength: 60,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: tr.text('device_name'),
                  errorText: errorText,
                ),
                onSubmitted: (_) {
                  final value =
                      controller.text.trim().replaceAll(RegExp(r'\s+'), ' ');
                  if (value.isEmpty) {
                    setDialogState(
                        () => errorText = tr.text('device_name_empty'));
                    return;
                  }
                  Navigator.of(dialogContext).pop(value);
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(tr.text('cancel')),
                ),
                FilledButton(
                  onPressed: () {
                    final value =
                        controller.text.trim().replaceAll(RegExp(r'\s+'), ' ');
                    if (value.isEmpty) {
                      setDialogState(
                          () => errorText = tr.text('device_name_empty'));
                      return;
                    }
                    Navigator.of(dialogContext).pop(value);
                  },
                  child: Text(tr.text('save')),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
    if (result == null || result.trim().isEmpty) return;
    try {
      await widget.store.runtime.updateDeviceName(result);
      final direct = VpsControlPlaneSettings.load();
      if (widget.store.runtime.identity.isDirectEnabled && direct.isConfigured) {
        await _controlPlaneService().registerCurrentDevice(
          direct,
          transport:
              widget.store.runtime.identity.activeSyncTransportNormalized == 'lan'
                  ? 'direct'
                  : widget.store.runtime.identity.activeSyncTransportNormalized,
        );
      }
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${tr.text('device_name')} ${tr.text('save')}')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final identity = widget.store.runtime.identity;
    return _SectionCard(
      icon: Icons.hub_outlined,
      title: tr.text('system_foundation'),
      subtitle: tr.text('system_foundation_desc'),
      trailing: Chip(
        avatar: const Icon(Icons.lock_outline, size: 16),
        label: Text(tr.text('read_only')),
      ),
      child: _InfoGrid(
        items: [
          _InfoGridItem(
              Icons.tag_outlined, tr.text('store_id'), identity.storeId),
          _InfoGridItem(
              Icons.business_outlined, tr.text('branch_id'), identity.branchId),
          _InfoGridItem(
              Icons.devices_outlined, tr.text('device_id'), identity.deviceId),
          _InfoGridItem(
              Icons.badge_outlined,
              tr.text('device_name'),
              identity.deviceName.trim().isEmpty
                  ? identity.deviceId
                  : identity.deviceName.trim(),
              onEdit: _editDeviceName),
          _InfoGridItem(Icons.computer_outlined, tr.text('platform'),
              identity.platform.name),
          _InfoGridItem(Icons.dns_outlined, tr.text('device_role'),
              identity.deviceRole.name),
          _InfoGridItem(
              Icons.badge_outlined, tr.text('app_role'), identity.appRole.name),
          _InfoGridItem(
              Icons.sync_outlined,
              tr.text('sync_mode'),
              identity.isHost
                  ? tr.text('host_lan_direct_controlled')
                  : identity.syncMode.name),
          _InfoGridItem(
              Icons.sync,
              tr.text('direct_tenant'),
              identity.controlPlaneTenantId.isEmpty
                  ? '—'
                  : identity.controlPlaneTenantId),
        ],
      ),
    );
  }
}
