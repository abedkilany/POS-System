// ignore_for_file: invalid_use_of_protected_member
part of 'sales_page.dart';

extension _SalesPageShortcutsCart on _SalesPageState {
  bool _handleSaleHardwareShortcutKey(KeyEvent event) {
    if (!mounted) return false;
    final productSearchHandler = _activeProductSearchKeyHandler;
    if (productSearchHandler != null) {
      if (_activeProductSearchFocusNode?.hasFocus == true) return false;
      return productSearchHandler(event);
    }
    if (ModalRoute.of(context)?.isCurrent != true) return false;
    return _handleSaleShortcutKey(event, _visibleProducts());
  }

  int? _productSearchDigitIndex(LogicalKeyboardKey key) {
    final topRow = <LogicalKeyboardKey>[
      LogicalKeyboardKey.digit0,
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8,
      LogicalKeyboardKey.digit9
    ];
    final keypad = <LogicalKeyboardKey>[
      LogicalKeyboardKey.numpad0,
      LogicalKeyboardKey.numpad1,
      LogicalKeyboardKey.numpad2,
      LogicalKeyboardKey.numpad3,
      LogicalKeyboardKey.numpad4,
      LogicalKeyboardKey.numpad5,
      LogicalKeyboardKey.numpad6,
      LogicalKeyboardKey.numpad7,
      LogicalKeyboardKey.numpad8,
      LogicalKeyboardKey.numpad9
    ];
    final topIndex = topRow.indexOf(key);
    if (topIndex >= 0) return topIndex;
    final keypadIndex = keypad.indexOf(key);
    return keypadIndex >= 0 ? keypadIndex : null;
  }

  bool _handleSaleShortcutKey(KeyEvent event, List<Product> visibleProducts) {
    if (event is! KeyDownEvent) return false;
    if (_handleCartArrowKey(event)) return true;
    final keyName = SaleShortcutSettings.keyNameForLogicalKey(event.logicalKey);
    if (keyName == null) return false;
    final action = SaleShortcutSettings.load().saleActionForKey(keyName);
    if (action == null) return false;
    _executeSaleShortcut(action, visibleProducts);
    return true;
  }

  bool _handleCartArrowKey(KeyDownEvent event) {
    if (_cart.isEmpty || !_canHandleCartArrowKeys()) return false;
    if (event.logicalKey != LogicalKeyboardKey.arrowUp &&
        event.logicalKey != LogicalKeyboardKey.arrowDown &&
        event.logicalKey != LogicalKeyboardKey.arrowLeft &&
        event.logicalKey != LogicalKeyboardKey.arrowRight) {
      return false;
    }
    final currentIndex = _normalizedSelectedCartIndex();
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowUp:
        _selectCartIndex((currentIndex - 1).clamp(0, _cart.length - 1).toInt());
        return true;
      case LogicalKeyboardKey.arrowDown:
        _selectCartIndex((currentIndex + 1).clamp(0, _cart.length - 1).toInt());
        return true;
      case LogicalKeyboardKey.arrowLeft:
        if (Directionality.of(context) == TextDirection.rtl) {
          _increaseSelectedCartItem();
        } else {
          _decreaseOrMarkSelectedCartItem();
        }
        return true;
      case LogicalKeyboardKey.arrowRight:
        if (Directionality.of(context) == TextDirection.rtl) {
          _decreaseOrMarkSelectedCartItem();
        } else {
          _increaseSelectedCartItem();
        }
        return true;
    }
    return false;
  }

  bool _canHandleCartArrowKeys() {
    final primaryFocus = FocusManager.instance.primaryFocus;
    if (primaryFocus == null || primaryFocus == _barcodeFocusNode) return true;
    final focusContext = primaryFocus.context;
    if (focusContext == null) return true;
    final isEditable = focusContext.widget is EditableText ||
        focusContext.findAncestorWidgetOfExactType<EditableText>() != null;
    return !isEditable;
  }

  int _normalizedSelectedCartIndex() {
    if (_cart.isEmpty) return 0;
    final index = _selectedCartIndex ?? 0;
    return index.clamp(0, _cart.length - 1).toInt();
  }

  void _selectCartIndex(int index) {
    if (_cart.isEmpty) return;
    setState(() {
      _selectedCartIndex = index.clamp(0, _cart.length - 1).toInt();
      _pendingDeleteCartIndex = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final key = _cartItemKeys[_selectedCartIndex];
      final itemContext = key?.currentContext;
      if (itemContext == null) return;
      Scrollable.ensureVisible(itemContext,
          alignment: 0.5,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut);
    });
  }

  void _increaseSelectedCartItem() {
    if (_cart.isEmpty) return;
    final index = _normalizedSelectedCartIndex();
    final item = _cart[index];
    _changeCartQuantity(index, item.quantity + 1);
  }

  void _decreaseOrMarkSelectedCartItem() {
    if (_cart.isEmpty) return;
    _decreaseOrMarkCartItem(_normalizedSelectedCartIndex());
  }

  void _decreaseOrMarkCartItem(int index) {
    if (index < 0 || index >= _cart.length) return;
    final item = _cart[index];
    if (item.quantity > 1) {
      _changeCartQuantity(index, item.quantity - 1);
      return;
    }
    if (_pendingDeleteCartIndex == index) {
      setState(() {
        _saleCart.removeAt(index);
        _pendingDeleteCartIndex = null;
        if (_cart.isEmpty) {
          _selectedCartIndex = null;
        } else {
          _selectedCartIndex = index.clamp(0, _cart.length - 1).toInt();
        }
      });
      return;
    }
    setState(() {
      _selectedCartIndex = index;
      _pendingDeleteCartIndex = index;
    });
  }

  void _removeCartItem(int index) {
    if (index < 0 || index >= _cart.length) return;
    setState(() {
      _saleCart.removeAt(index);
      _pendingDeleteCartIndex = null;
      if (_cart.isEmpty) {
        _selectedCartIndex = null;
      } else {
        _selectedCartIndex = index.clamp(0, _cart.length - 1).toInt();
      }
    });
  }

  Future<void> _executeSaleShortcut(
      SaleShortcutAction action, List<Product> visibleProducts) async {
    final tr = AppLocalizations.of(context);
    switch (action) {
      case SaleShortcutAction.focusBarcode:
        _restoreScannerMode();
        break;
      case SaleShortcutAction.searchProduct:
        _showProductSearchSheet(visibleProducts);
        break;
      case SaleShortcutAction.holdCart:
        if (_cart.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(tr.text('shortcut_cart_empty'))));
          return;
        }
        await _holdCurrentCart();
        break;
      case SaleShortcutAction.restoreHeldCarts:
        await _showHeldCartsDialog();
        break;
      case SaleShortcutAction.openPayment:
        if (_cart.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(tr.text('shortcut_cart_empty'))));
          return;
        }
        await _openPaymentPage();
        break;
      case SaleShortcutAction.clearCart:
        await _confirmClearCart();
        break;
    }
  }

  bool _handlePaymentShortcutKey(KeyEvent event, BuildContext dialogContext,
      void Function(void Function()) setDialogState) {
    if (event is! KeyDownEvent) return false;
    if (!dialogContext.mounted ||
        ModalRoute.of(dialogContext)?.isCurrent != true) {
      return false;
    }
    final keyName = SaleShortcutSettings.keyNameForLogicalKey(event.logicalKey);
    if (keyName == null) return false;
    final action = SaleShortcutSettings.load().paymentActionForKey(keyName);
    if (action == null) return false;
    switch (action) {
      case SalePaymentShortcutAction.confirmPayment:
        Navigator.pop(dialogContext, true);
        return true;
      case SalePaymentShortcutAction.cancelPayment:
        Navigator.pop(dialogContext, false);
        return true;
      case SalePaymentShortcutAction.focusDiscount:
        _discountFocusNode.requestFocus();
        return true;
      case SalePaymentShortcutAction.focusCashReceived:
        if (_showsCashReceived) {
          _cashReceivedFocusNode.requestFocus();
        }
        return true;
      case SalePaymentShortcutAction.toggleCash:
        _setPaymentMethod('Cash');
        setDialogState(() {});
        return true;
      case SalePaymentShortcutAction.toggleCard:
        _setPaymentMethod('Card');
        setDialogState(() {});
        return true;
      case SalePaymentShortcutAction.toggleCredit:
        _setPaymentMethod('Credit');
        setDialogState(() {});
        return true;
    }
  }

  Future<void> _editPaymentShortcut(
      SalePaymentShortcutAction action, AppLocalizations tr) async {
    final settings = SaleShortcutSettings.load();
    final currentKey =
        settings.keyForPaymentAction(action) ?? SaleShortcutSettings.noneKey;
    final selectedKey = await showShortcutKeyPicker(
        context: context,
        title: tr.text('shortcut_change'),
        currentKey: currentKey,
        noneLabel: tr.text('shortcut_none'),
        cancelLabel: tr.text('cancel'),
        saveLabel: tr.text('save'));
    if (selectedKey == null || !mounted) return;
    if (settings.isPaymentKeyUsedByAnotherAction(selectedKey, action)) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr.text('shortcut_key_already_used'))));
      return;
    }
    final next = settings.copyWithPaymentActionKey(action, selectedKey);
    await next.save();
    if (mounted) setState(() {});
  }

  Widget _buildPaymentShortcutGuide(BuildContext context, AppLocalizations tr) {
    return ValueListenableBuilder<int>(
        valueListenable: SaleShortcutSettings.revision,
        builder: (context, _, __) {
          final settings = SaleShortcutSettings.load();
          final chips = <Widget>[];
          for (final action in SalePaymentShortcutAction.values) {
            final keyName = settings.keyForPaymentAction(action);
            if (keyName == null || keyName == SaleShortcutSettings.noneKey) {
              continue;
            }
            chips.add(Padding(
                padding: const EdgeInsetsDirectional.only(end: 6, bottom: 6),
                child: ShortcutGuideChip(
                    keyName: keyName,
                    label: tr.text(action.labelKey),
                    onPressed: () => _editPaymentShortcut(action, tr))));
          }
          if (chips.isEmpty) return const SizedBox.shrink();
          return Wrap(children: chips);
        });
  }

  Future<void> _confirmClearCart() async {
    if (_cart.isEmpty) return;
    final tr = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text(tr.text('clear_cart')),
                content: Text(tr.text('confirm_clear_cart')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Text(tr.text('cancel'))),
                  FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: Text(tr.text('clear')))
                ]));
    if (confirmed == true && mounted) {
      setState(() {
        _saleCart.clear();
        _selectedCartIndex = null;
        _pendingDeleteCartIndex = null;
      });
      _restoreScannerMode();
    }
  }

  void _setSelectedCustomerId(String? value) {
    final id = widget.store.commerce.sanitizeSelectedCustomerId(value);
    setState(() {
      _selectedCustomerId = id;
      if (id == CommerceDefaults.walkInCustomerId && _paymentMethod == 'Credit') {
        _paymentMethod = 'Cash';
        _paidAmountController.clear();
      }
    });
  }

  void _setPaymentMethod(String value) {
    setState(() {
      _paymentMethod =
          (_isWalkInCustomer && value == 'Credit') ? 'Cash' : value;
      if (_paymentMethod == 'Cash') {
        _paidAmountController.clear();
      } else if (_paidAmountController.text.trim().isEmpty) {
        _paidAmountController.text = '0';
      }
    });
  }
}
