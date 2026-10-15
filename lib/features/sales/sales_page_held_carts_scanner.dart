// ignore_for_file: invalid_use_of_protected_member
part of 'sales_page.dart';

extension _SalesPageHeldCartsScanner on _SalesPageState {
  void _toggleManualBarcodeInput() {
    setState(() => _manualBarcodeInput = !_manualBarcodeInput);
    if (_manualBarcodeInput) {
      _barcodeFocusNode.requestFocus();
      SystemChannels.textInput.invokeMethod('TextInput.show');
    } else {
      _barcodeFocusNode.unfocus();
      SystemChannels.textInput.invokeMethod('TextInput.hide');
    }
  }

  void _restoreScannerMode() {
    if (_manualBarcodeInput) {
      setState(() => _manualBarcodeInput = false);
    }
    _barcodeFocusNode.requestFocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
  }

  Future<void> _loadHeldSaleCarts() async {
    final raw =
        LocalDatabaseService.getString(_SalesPageState._heldSalesStorageKey);
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final carts = decoded
          .map((item) =>
              _HeldSaleCart.fromJson(Map<String, dynamic>.from(item as Map)))
          .where((cart) => cart.items.isNotEmpty)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (!mounted) return;
      setState(() {
        _heldCarts
          ..clear()
          ..addAll(carts);
      });
    } catch (_) {}
  }

  Future<void> _saveHeldSaleCarts() async {
    await LocalDatabaseService.setString(_SalesPageState._heldSalesStorageKey,
        jsonEncode(_heldCarts.map((cart) => cart.toJson()).toList()));
  }

  String _defaultHeldCartName() {
    final now = DateTime.now();
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    return 'Hold ${_heldCarts.length + 1} - $hour:$minute';
  }

  Future<bool> _confirmSalesExit() async {
    if (_cart.isEmpty) return true;
    if (_exitPromptOpen) return false;
    _exitPromptOpen = true;
    try {
      final tr = AppLocalizations.of(context);
      final choice = await showDialog<_SalesExitChoice>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
                  title: Text(tr.text('sales_exit_cart_title')),
                  content: Text(tr.text('sales_exit_cart_message')),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.of(dialogContext)
                            .pop(_SalesExitChoice.cancel),
                        child: Text(tr.text('cancel'))),
                    OutlinedButton.icon(
                        onPressed: () => Navigator.of(dialogContext)
                            .pop(_SalesExitChoice.holdCart),
                        icon: const Icon(Icons.pause_circle_outline),
                        label: Text(tr.text('hold_cart'))),
                    FilledButton.icon(
                        onPressed: () => Navigator.of(dialogContext)
                            .pop(_SalesExitChoice.clearCart),
                        icon: const Icon(Icons.delete_sweep_outlined),
                        label: Text(tr.text('clear_cart')))
                  ]));
      switch (choice) {
        case _SalesExitChoice.clearCart:
          if (!mounted) return false;
          setState(() {
            _cart.clear();
            _selectedCartIndex = null;
            _pendingDeleteCartIndex = null;
          });
          _restoreScannerMode();
          return true;
        case _SalesExitChoice.holdCart:
          return _holdCurrentCart();
        case _SalesExitChoice.cancel:
        case null:
          return false;
      }
    } finally {
      _exitPromptOpen = false;
    }
  }

  Future<bool> _holdCurrentCart() async {
    if (!widget.store.security.canSell) return false;
    if (_cart.isEmpty) return false;
    final tr = AppLocalizations.of(context);
    final nameController = TextEditingController(text: _defaultHeldCartName());
    final name = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text(tr.text('hold_cart')),
                content: TextField(
                    controller: nameController,
                    autofocus: true,
                    decoration:
                        InputDecoration(labelText: tr.text('hold_cart_name')),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (value) => Navigator.of(context).pop(value)),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(tr.text('cancel'))),
                  FilledButton(
                      onPressed: () =>
                          Navigator.of(context).pop(nameController.text),
                      child: Text(tr.text('hold')))
                ]));
    nameController.dispose();
    if (name == null) return false;
    final trimmedName =
        name.trim().isEmpty ? _defaultHeldCartName() : name.trim();
    final cart = _HeldSaleCart(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: trimmedName,
        createdAt: DateTime.now(),
        items: _cart.map(_HeldSaleItem.fromDraft).toList());
    setState(() {
      _heldCarts.insert(0, cart);
      _cart.clear();
      _selectedCartIndex = null;
      _pendingDeleteCartIndex = null;
    });
    await _saveHeldSaleCarts();
    if (!mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr.text('cart_held_successfully'))));
    _restoreScannerMode();
    return true;
  }

  Future<void> _restoreHeldCart(_HeldSaleCart heldCart) async {
    if (_cart.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              AppLocalizations.of(context).text('hold_current_cart_first'))));
      return;
    }
    final restored = <_DraftSaleItem>[];
    final missingNames = <String>[];
    for (final item in heldCart.items) {
      final product = widget.store.catalog.productById(item.productId);
      if (product == null || !product.isActive) {
        missingNames.add(item.productName);
        continue;
      }
      ProductSaleUnit? saleUnit;
      for (final unit in product.effectiveSaleUnits) {
        if (unit.id == item.saleUnitId) {
          saleUnit = unit;
          break;
        }
      }
      final restoredUnit = saleUnit ?? item.saleUnit;
      restored.add(_DraftSaleItem(
          product: product,
          quantity: item.quantity,
          saleUnit: restoredUnit.copyWith(
              price: _salePriceFor(product, restoredUnit))));
    }
    if (restored.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context)
              .text('held_cart_products_missing'))));
      return;
    }
    setState(() {
      _cart
        ..clear()
        ..addAll(restored);
      _selectedCartIndex = _cart.isEmpty ? null : 0;
      _pendingDeleteCartIndex = null;
      _heldCarts.removeWhere((cart) => cart.id == heldCart.id);
    });
    await _saveHeldSaleCarts();
    if (!mounted) return;
    Navigator.of(context).maybePop();
    final tr = AppLocalizations.of(context);
    final message = missingNames.isEmpty
        ? tr.text('cart_restored_successfully')
        : '${tr.text('cart_restored_with_missing_products')}: ${missingNames.join(', ')}';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
    _restoreScannerMode();
  }

  Future<void> _deleteHeldCart(_HeldSaleCart heldCart) async {
    setState(() => _heldCarts.removeWhere((cart) => cart.id == heldCart.id));
    await _saveHeldSaleCarts();
  }

  Future<void> _showHeldCartsDialog() async {
    final tr = AppLocalizations.of(context);
    await showDialog<void>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
                    title:
                        Text('${tr.text('held_carts')} (${_heldCarts.length})'),
                    content: SizedBox(
                        width: 420,
                        child: _heldCarts.isEmpty
                            ? Text(tr.text('no_held_carts'))
                            : ListView.separated(
                                shrinkWrap: true,
                                itemCount: _heldCarts.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final cart = _heldCarts[index];
                                  return ListTile(
                                      leading: const Icon(
                                          Icons.pause_circle_outline),
                                      title: Text(cart.name),
                                      subtitle: Text(
                                          '${cart.items.length} ${tr.text('items')} • ${_formatHeldCartTime(cart.createdAt)}'),
                                      trailing: IconButton(
                                          tooltip: tr.text('delete'),
                                          icon:
                                              const Icon(Icons.delete_outline),
                                          onPressed: () async {
                                            await _deleteHeldCart(cart);
                                            setDialogState(() {});
                                          }),
                                      onTap: () => _restoreHeldCart(cart));
                                })),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(tr.text('close')))
                    ])));
  }

  String _formatHeldCartTime(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '$day/$month $hour:$minute';
  }

  bool get _canUseCameraScanner =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> _scanBarcodeWithCamera() async {
    if (_scannerActive) {
      await _scannerController.stop();
      if (mounted) setState(() => _scannerActive = false);
      return;
    }
    if (!mounted) return;
    setState(() {
      _scannerActive = true;
      _scannerStartFailed = false;
    });
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _startEmbeddedScanner());
  }

  Future<void> _startEmbeddedScanner() async {
    if (!mounted || !_scannerActive) return;
    setState(() => _scannerStartFailed = false);
    try {
      await _scannerController.start();
    } catch (_) {
      if (mounted) setState(() => _scannerStartFailed = true);
    }
  }

  void _handleEmbeddedBarcode(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final code = barcode.rawValue?.trim();
      if (code == null || code.isEmpty) continue;
      final now = DateTime.now();
      if (_lastScannedCode == code &&
          _lastScannedAt != null &&
          now.difference(_lastScannedAt!) <
              const Duration(milliseconds: 1500)) {
        return;
      }
      _lastScannedCode = code;
      _lastScannedAt = now;
      _barcodeController.text = code;
      unawaited(_addByCode(code));
      return;
    }
  }

  Widget _buildEmbeddedScannerPreview() {
    if (!_canUseCameraScanner || !_scannerActive) {
      return const SizedBox.shrink();
    }
    final tr = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final scannerHeight = VentioResponsive.adaptiveWidth(context,
        mobile: 132, tablet: 150, desktop: 170);
    return Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(children: [
                    const Icon(Icons.center_focus_strong_outlined, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(tr.text('inline_barcode_scanner'),
                            maxLines: 1, overflow: TextOverflow.ellipsis)),
                    IconButton(
                        tooltip: tr.text('stop_camera_scanner'),
                        onPressed: _scanBarcodeWithCamera,
                        icon: const Icon(Icons.close))
                  ])),
              Container(
                  height: scannerHeight,
                  decoration:
                      BoxDecoration(color: scheme.surfaceContainerHighest),
                  child: Stack(fit: StackFit.expand, children: [
                    MobileScanner(
                        controller: _scannerController,
                        fit: BoxFit.cover,
                        onDetect: _handleEmbeddedBarcode,
                        errorBuilder: (context, error) => _EmbeddedScannerError(
                            onRetry: _startEmbeddedScanner),
                        placeholderBuilder: (_) =>
                            ColoredBox(color: scheme.surfaceContainerHighest)),
                    if (_scannerStartFailed)
                      _EmbeddedScannerError(onRetry: _startEmbeddedScanner),
                    IgnorePointer(child: Center(
                        child: LayoutBuilder(builder: (context, constraints) {
                      final frameWidth = VentioResponsive.clampToScreen(
                          context, constraints.maxWidth * 0.62,
                          min: 150, horizontalPadding: 48);
                      return Container(
                          width: frameWidth,
                          height: (frameWidth * 0.40).clamp(64, 90).toDouble(),
                          decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border:
                                  Border.all(color: Colors.white, width: 2)));
                    })))
                  ]))
            ]));
  }

  Widget _buildBarcodeStation(BuildContext context, AppLocalizations tr,
      {required List<Product> products, bool embedded = false}) {
    return Container(
        padding: VentioResponsive.cardInsets(context),
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: Theme.of(context)
                .colorScheme
                .primaryContainer
                .withValues(alpha: 0.45),
            border: Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.25))),
        child: LayoutBuilder(builder: (context, constraints) {
          final field = TextField(
              controller: _barcodeController,
              focusNode: _barcodeFocusNode,
              autofocus: false,
              readOnly: false,
              showCursor: _manualBarcodeInput,
              enableInteractiveSelection: _manualBarcodeInput,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.done,
              onTap: () {
                if (!_manualBarcodeInput) {
                  SystemChannels.textInput.invokeMethod('TextInput.hide');
                }
              },
              decoration: InputDecoration(
                  labelText: tr.text('scan_barcode'),
                  hintText: tr.text('scan_barcode_hint'),
                  prefixIcon: const Icon(Icons.qr_code_2),
                  suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                        tooltip: _manualBarcodeInput
                            ? tr.text('hide_keyboard')
                            : tr.text('manual_input'),
                        onPressed: _toggleManualBarcodeInput,
                        icon: Icon(_manualBarcodeInput
                            ? Icons.keyboard_hide_outlined
                            : Icons.keyboard_outlined)),
                    IconButton(
                        tooltip: tr.text('search_product'),
                        onPressed: () => _showProductSearchSheet(products),
                        icon: const Icon(Icons.search)),
                    if (_canUseCameraScanner)
                      IconButton(
                          tooltip: _scannerActive
                              ? tr.text('stop_camera_scanner')
                              : tr.text('start_camera_scanner'),
                          onPressed: _scanBarcodeWithCamera,
                          icon: Icon(_scannerActive
                              ? Icons.videocam_off_outlined
                              : Icons.camera_alt_outlined)),
                    IconButton(
                        tooltip: tr.text('clear'),
                        onPressed: () {
                          _barcodeController.clear();
                          if (_manualBarcodeInput) {
                            _barcodeFocusNode.requestFocus();
                          } else {
                            SystemChannels.textInput
                                .invokeMethod('TextInput.hide');
                          }
                        },
                        icon: const Icon(Icons.clear))
                  ])),
              onSubmitted: (value) => unawaited(_addByCode(value)));
          final button = FilledButton.icon(
              onPressed: () => unawaited(_addByCode(_barcodeController.text)),
              icon: const Icon(Icons.add_shopping_cart),
              label: Text(tr.text('add_to_cart')));
          final preview = embedded
              ? const SizedBox.shrink()
              : _buildEmbeddedScannerPreview();
          if (constraints.maxWidth < 460) {
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  field,
                  const SizedBox(height: 8),
                  button,
                  if (!embedded && _scannerActive) preview
                ]);
          }
          return Column(children: [
            Row(children: [
              const Icon(Icons.qr_code_scanner, size: 32),
              const SizedBox(width: 12),
              Expanded(child: field),
              const SizedBox(width: 12),
              button
            ]),
            if (!embedded && _scannerActive) preview
          ]);
        }));
  }
}
