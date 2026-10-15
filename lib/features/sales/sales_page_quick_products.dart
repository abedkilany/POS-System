// ignore_for_file: invalid_use_of_protected_member
part of 'sales_page.dart';

extension _SalesPageQuickProducts on _SalesPageState {
  Widget _buildQuickProductTile(
      BuildContext context,
      AppLocalizations tr,
      _QuickProductPage page,
      int index,
      _QuickProductSlot slot,
      Product? product,
      bool isEmpty,
      {VoidCallback? onChanged}) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          if (isEmpty) {
            if (_quickGridEditMode) {
              await _configureQuickSlot(page, index);
              onChanged?.call();
            }
          } else if (_quickGridEditMode) {
            await _configureQuickSlot(page, index);
            onChanged?.call();
          } else {
            _addProduct(product!);
          }
        },
        child: Ink(
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: isEmpty
                    ? scheme.surfaceContainerHighest.withValues(alpha: 0.35)
                    : scheme.primaryContainer.withValues(alpha: 0.40),
                border: Border.all(
                    color: isEmpty
                        ? scheme.outlineVariant
                        : scheme.primary.withValues(alpha: 0.28))),
            child: Stack(children: [
              Center(
                  child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: isEmpty
                          ? Icon(Icons.add, size: 34, color: scheme.primary)
                          : LayoutBuilder(builder: (context, constraints) {
                              final productName =
                                  slot.shortName?.trim().isNotEmpty == true
                                      ? slot.shortName!.trim()
                                      : product!.name;
                              final price = formatUsdReferenceAmount(
                                  product!.price, widget.store.storeProfile);
                              return Center(
                                  child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: SizedBox(
                                          width: constraints.maxWidth,
                                          child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(productName,
                                                    textAlign: TextAlign.center,
                                                    softWrap: true,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .titleMedium
                                                        ?.copyWith(
                                                            fontWeight:
                                                                FontWeight
                                                                    .w800)),
                                                const SizedBox(height: 8),
                                                Text(price,
                                                    textAlign: TextAlign.center,
                                                    softWrap: true)
                                              ]))));
                            }))),
              if (_quickGridEditMode && !isEmpty)
                Positioned(
                    top: 4,
                    right: 4,
                    child: IconButton.filledTonal(
                        tooltip: tr.text('delete'),
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          _clearQuickSlot(page, index);
                          onChanged?.call();
                        },
                        icon: const Icon(Icons.close, size: 18))),
              if (_quickGridEditMode && !isEmpty)
                const Positioned(
                    left: 8,
                    bottom: 8,
                    child: Icon(Icons.drag_indicator, size: 20)),
              if (_quickGridEditMode && !isEmpty)
                Positioned(
                    right: 8,
                    bottom: 8,
                    child: Icon(Icons.edit_outlined,
                        size: 20, color: scheme.primary))
            ])));
  }

  List<int> _quickVisibleSlotIndexes(_QuickProductPage page) {
    final filled = <int>[];
    int? firstEmpty;
    for (var i = 0; i < page.slots.length; i += 1) {
      final slot = page.slots[i];
      final product =
          slot.productId == null ? null : _productById(slot.productId!);
      if (product != null) {
        filled.add(i);
      } else {
        firstEmpty ??= i;
      }
    }
    if (_quickGridEditMode && firstEmpty != null) filled.add(firstEmpty);
    return filled;
  }

  List<_QuickProductPage> _cloneQuickPages(List<_QuickProductPage> pages) {
    return pages
        .map((page) => _QuickProductPage(
            name: page.name,
            slots: page.slots
                .map((slot) => _QuickProductSlot(
                    productId: slot.productId, shortName: slot.shortName))
                .toList()))
        .toList();
  }

  bool get _quickGridHasUnsavedChanges {
    final snapshot = _quickPagesEditSnapshot;
    if (snapshot == null) return false;
    return jsonEncode(snapshot.map((page) => page.toJson()).toList()) !=
        jsonEncode(_quickPages.map((page) => page.toJson()).toList());
  }

  void _startQuickGridEditing() {
    setState(() {
      _quickPagesEditSnapshot ??= _cloneQuickPages(_quickPages);
      _quickGridEditMode = true;
    });
  }

  void _saveQuickGridEditing() {
    setState(() {
      _quickGridEditMode = false;
      _quickPagesEditSnapshot = null;
    });
    unawaited(_saveQuickProductPages());
  }

  void _cancelQuickGridEditing() {
    final snapshot = _quickPagesEditSnapshot;
    setState(() {
      if (snapshot != null) {
        _quickPages
          ..clear()
          ..addAll(_cloneQuickPages(snapshot));
      }
      _quickGridEditMode = false;
      _quickPagesEditSnapshot = null;
      _selectedQuickPageIndex =
          _selectedQuickPageIndex.clamp(0, _quickPages.length - 1).toInt();
    });
  }

  Future<bool> _confirmCloseQuickGridEditor() async {
    if (!_quickGridEditMode) return true;
    if (!_quickGridHasUnsavedChanges) {
      _cancelQuickGridEditing();
      return true;
    }
    final tr = AppLocalizations.of(context);
    final result = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
                title: Text(tr.text('unsaved_changes')),
                content: Text(tr.text('quick_grid_unsaved_changes_desc')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext, 'stay'),
                      child: Text(tr.text('continue_editing'))),
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext, 'discard'),
                      child: Text(tr.text('discard_changes'))),
                  FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, 'save'),
                      child: Text(tr.text('save')))
                ]));
    if (result == 'save') {
      _saveQuickGridEditing();
      return true;
    }
    if (result == 'discard') {
      _cancelQuickGridEditing();
      return true;
    }
    return false;
  }

  void _loadQuickProductPages() {
    final raw =
        LocalDatabaseService.getString(_SalesPageState._quickPagesStorageKey);
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      _quickPages
        ..clear()
        ..addAll(decoded
            .whereType<Map<String, dynamic>>()
            .map(_QuickProductPage.fromJson));
    } catch (_) {
      _quickPages.clear();
    }
  }

  void _loadQuickProductPreferences() {
    final storedTileSize = LocalDatabaseService.getString(
        _SalesPageState._quickTileSizeStorageKey);
    _quickTileSize = _QuickProductTileSize.values.firstWhere(
        (value) => value.name == storedTileSize,
        orElse: () => _QuickProductTileSize.medium);
    final storedFraction = double.tryParse(LocalDatabaseService.getString(
            _SalesPageState._quickPanelFractionStorageKey) ??
        '');
    if (storedFraction != null && storedFraction.isFinite) {
      _quickPanelFraction = storedFraction.clamp(0.25, 0.65).toDouble();
    }
  }

  void _setQuickTileSize(_QuickProductTileSize value) {
    if (_quickTileSize == value) return;
    setState(() => _quickTileSize = value);
    unawaited(LocalDatabaseService.setString(
        _SalesPageState._quickTileSizeStorageKey, value.name));
  }

  void _resizeQuickProductPanel(double totalWidth, double delta) {
    if (totalWidth <= 0) return;
    final direction = Directionality.of(context) == TextDirection.rtl ? -1 : 1;
    final requestedWidth = totalWidth * _quickPanelFraction - delta * direction;
    final minimumWidth = math.min(280.0, totalWidth * 0.35);
    final maximumWidth =
        math.max(minimumWidth, math.min(totalWidth * 0.65, totalWidth - 420));
    final nextWidth =
        requestedWidth.clamp(minimumWidth, maximumWidth).toDouble();
    setState(() => _quickPanelFraction = nextWidth / totalWidth);
  }

  int _quickTileColumnCount(double width) {
    switch (_quickTileSize) {
      case _QuickProductTileSize.small:
        return width >= 650
            ? 4
            : width >= 420
                ? 3
                : 2;
      case _QuickProductTileSize.medium:
        return width >= 520 ? 3 : 2;
      case _QuickProductTileSize.large:
        return width >= 760
            ? 3
            : width >= 500
                ? 2
                : 1;
    }
  }

  Widget _buildQuickTileSizeButton(BuildContext context, AppLocalizations tr,
      {VoidCallback? onChanged}) {
    return PopupMenuButton<_QuickProductTileSize>(
        tooltip: tr.text('quick_tile_size'),
        icon: const Icon(Icons.grid_view_outlined),
        initialValue: _quickTileSize,
        onSelected: (value) {
          _setQuickTileSize(value);
          onChanged?.call();
        },
        itemBuilder: (context) => [
              PopupMenuItem(
                  value: _QuickProductTileSize.small,
                  child: Text(tr.text('small'))),
              PopupMenuItem(
                  value: _QuickProductTileSize.medium,
                  child: Text(tr.text('medium'))),
              PopupMenuItem(
                  value: _QuickProductTileSize.large,
                  child: Text(tr.text('large')))
            ]);
  }

  void _ensureQuickPages(List<Product> products, AppLocalizations tr) {
    if (_quickPages.isEmpty) {
      _quickPages.add(_QuickProductPage(
          name: tr.text('favorites'),
          slots: List.generate(12, (index) {
            if (index < products.length && index < 6) {
              final product = products[index];
              return _QuickProductSlot(
                  productId: product.id, shortName: product.name);
            }
            return const _QuickProductSlot();
          })));
      unawaited(_saveQuickProductPages());
    }
    _migrateLegacyQuickProductNames();
    if (_selectedQuickPageIndex >= _quickPages.length) {
      _selectedQuickPageIndex = _quickPages.length - 1;
    }
    if (_selectedQuickPageIndex < 0) _selectedQuickPageIndex = 0;
  }

  void _migrateLegacyQuickProductNames() {
    var changed = false;
    for (final page in _quickPages) {
      for (var index = 0; index < page.slots.length; index += 1) {
        final slot = page.slots[index];
        final productId = slot.productId;
        if (productId == null) continue;
        final product = _productById(productId);
        if (product == null) continue;
        final fullName = product.name.trim();
        final legacyName =
            fullName.length <= 14 ? fullName : fullName.substring(0, 14).trim();
        if (fullName.length > legacyName.length &&
            slot.shortName?.trim() == legacyName) {
          page.slots[index] =
              _QuickProductSlot(productId: productId, shortName: fullName);
          changed = true;
        }
      }
    }
    if (changed) unawaited(_saveQuickProductPages());
  }

  Future<void> _saveQuickProductPages() => LocalDatabaseService.setString(
      _SalesPageState._quickPagesStorageKey,
      jsonEncode(_quickPages.map((page) => page.toJson()).toList()));

  Product? _productById(String id) {
    final product = widget.store.productById(id);
    if (product == null || !product.isActive) return null;
    return product;
  }

  void _addQuickPage() {
    setState(() {
      _quickPages.add(_QuickProductPage(
          name:
              '${AppLocalizations.of(context).text('page')} ${_quickPages.length + 1}',
          slots: List.generate(12, (_) => const _QuickProductSlot())));
      _selectedQuickPageIndex = _quickPages.length - 1;
      _quickGridEditMode = true;
    });
    if (!_quickGridEditMode) unawaited(_saveQuickProductPages());
  }

  void _deleteQuickPage(int index) {
    if (_quickPages.length <= 1 || index < 0 || index >= _quickPages.length) {
      return;
    }
    setState(() {
      _quickPages.removeAt(index);
      _selectedQuickPageIndex =
          _selectedQuickPageIndex.clamp(0, _quickPages.length - 1).toInt();
    });
    if (!_quickGridEditMode) unawaited(_saveQuickProductPages());
  }

  Future<void> _renameQuickPage(int index) async {
    if (index < 0 || index >= _quickPages.length) return;
    final controller = TextEditingController(text: _quickPages[index].name);
    final tr = AppLocalizations.of(context);
    final result = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
                title: Text(tr.text('rename_quick_page')),
                content: TextField(
                    controller: controller,
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    decoration:
                        InputDecoration(labelText: tr.text('page_name')),
                    onSubmitted: (value) =>
                        Navigator.pop(dialogContext, value.trim())),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: Text(tr.text('cancel'))),
                  FilledButton(
                      onPressed: () =>
                          Navigator.pop(dialogContext, controller.text.trim()),
                      child: Text(tr.text('save')))
                ]));
    controller.dispose();
    if (result == null || result.trim().isEmpty) return;
    setState(() => _quickPages[index].name = result.trim());
    if (!_quickGridEditMode) unawaited(_saveQuickProductPages());
  }

  void _moveQuickPage(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _quickPages.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex < 0 ||
        newIndex >= _quickPages.length ||
        oldIndex == newIndex) {
      return;
    }
    setState(() {
      final page = _quickPages.removeAt(oldIndex);
      _quickPages.insert(newIndex, page);
      if (_selectedQuickPageIndex == oldIndex) {
        _selectedQuickPageIndex = newIndex;
      } else if (oldIndex < _selectedQuickPageIndex &&
          newIndex >= _selectedQuickPageIndex) {
        _selectedQuickPageIndex -= 1;
      } else if (oldIndex > _selectedQuickPageIndex &&
          newIndex <= _selectedQuickPageIndex) {
        _selectedQuickPageIndex += 1;
      }
    });
    if (!_quickGridEditMode) unawaited(_saveQuickProductPages());
  }

  void _moveQuickSlot(int fromIndex, int toIndex) {
    if (_selectedQuickPageIndex < 0 ||
        _selectedQuickPageIndex >= _quickPages.length) {
      return;
    }
    final page = _quickPages[_selectedQuickPageIndex];
    if (fromIndex < 0 ||
        fromIndex >= page.slots.length ||
        toIndex < 0 ||
        toIndex >= page.slots.length ||
        fromIndex == toIndex) {
      return;
    }
    setState(() {
      final moved = page.slots.removeAt(fromIndex);
      page.slots.insert(toIndex, moved);
    });
    if (!_quickGridEditMode) unawaited(_saveQuickProductPages());
  }

  void _clearQuickSlot(_QuickProductPage page, int index) {
    if (index < 0 || index >= page.slots.length) return;
    setState(() => page.slots[index] = const _QuickProductSlot());
    if (!_quickGridEditMode) unawaited(_saveQuickProductPages());
  }

  Future<void> _configureQuickSlot(
      _QuickProductPage page, int slotIndex) async {
    if (slotIndex < 0 || slotIndex >= page.slots.length) return;
    final tr = AppLocalizations.of(context);
    final products = _activeProductsCache.getOrCompute(
        widget.store.productsRevision,
        'active_products',
        () => widget.store.products
            .where((product) => product.isActive && !product.isDeleted)
            .toList(growable: false));
    final searchIndex = _productSearchIndex();
    final nameController =
        TextEditingController(text: page.slots[slotIndex].shortName ?? '');
    final quickSearchController = TextEditingController();
    Product? selected = page.slots[slotIndex].productId == null
        ? null
        : _productById(page.slots[slotIndex].productId!);
    var query = '';
    final result = await showModalBottomSheet<_QuickProductSlot>(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) =>
            StatefulBuilder(builder: (context, setSheetState) {
              final filteredFuture = _resolveSearchProducts(
                  products, searchIndex, query,
                  limit: 500);
              return SafeArea(
                  child: Padding(
                      padding: EdgeInsets.only(
                          left: 16,
                          right: 16,
                          top: 16,
                          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom +
                              16),
                      child: SizedBox(
                          height: MediaQuery.sizeOf(sheetContext).height * 0.86,
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(children: [
                                  Expanded(
                                      child: Text(
                                          tr.text('quick_product_shortcut'),
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge)),
                                  IconButton(
                                      tooltip: tr.text('close'),
                                      onPressed: () =>
                                          Navigator.pop(sheetContext),
                                      icon: const Icon(Icons.close))
                                ]),
                                const SizedBox(height: 10),
                                TextField(
                                    controller: quickSearchController,
                                    decoration: InputDecoration(
                                        prefixIcon: const Icon(Icons.search),
                                        labelText: tr.text('search_product'),
                                        suffixIcon: IconButton(
                                            tooltip:
                                                tr.text('scan_with_camera'),
                                            onPressed: () async {
                                              final code =
                                                  await _scanCodeWithCameraOnce();
                                              if (code == null) return;
                                              quickSearchController.text = code;
                                              setSheetState(() => query = code);
                                            },
                                            icon: const Icon(
                                                Icons.camera_alt_outlined))),
                                    onChanged: (value) =>
                                        setSheetState(() => query = value)),
                                const SizedBox(height: 10),
                                TextField(
                                    controller: nameController,
                                    decoration: InputDecoration(
                                        labelText: tr.text('short_name'))),
                                const SizedBox(height: 10),
                                Expanded(
                                    child: FutureBuilder<List<Product>>(
                                        future: filteredFuture,
                                        builder: (context, snapshot) {
                                          if (snapshot.connectionState !=
                                              ConnectionState.done) {
                                            return const Center(
                                                child: CircularProgressIndicator
                                                    .adaptive());
                                          }
                                          final filtered = snapshot.data ??
                                              const <Product>[];
                                          if (filtered.isEmpty) {
                                            return Center(
                                                child: Text(
                                                    tr.text('no_products')));
                                          }
                                          return ListView.separated(
                                              itemCount: filtered.length,
                                              separatorBuilder: (_, __) =>
                                                  const Divider(height: 1),
                                              itemBuilder: (context, index) {
                                                final product = filtered[index];
                                                final isSelected =
                                                    selected?.id == product.id;
                                                return ListTile(
                                                    selected: isSelected,
                                                    leading: Icon(isSelected
                                                        ? Icons.check_circle
                                                        : Icons
                                                            .inventory_2_outlined),
                                                    title: Text(product.name,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis),
                                                    subtitle: Text(
                                                        '${product.code} • ${_stockAvailabilityLabel(product, tr)}',
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis),
                                                    trailing: Text(
                                                        formatUsdReferenceAmount(
                                                            widget.store
                                                                .defaultProductUsdPrice(
                                                                    product),
                                                            widget.store
                                                                .storeProfile)),
                                                    onTap: () {
                                                      setSheetState(() {
                                                        selected = product;
                                                        if (nameController.text
                                                            .trim()
                                                            .isEmpty) {
                                                          nameController.text =
                                                              product.name;
                                                        }
                                                      });
                                                    });
                                              });
                                        })),
                                const SizedBox(height: 12),
                                Row(children: [
                                  Expanded(
                                      child: OutlinedButton(
                                          onPressed: () =>
                                              Navigator.pop(sheetContext),
                                          child: Text(tr.text('cancel')))),
                                  if (page.slots[slotIndex].productId !=
                                      null) ...[
                                    const SizedBox(width: 8),
                                    Expanded(
                                        child: OutlinedButton(
                                            onPressed: () => Navigator.pop(
                                                sheetContext,
                                                const _QuickProductSlot()),
                                            child: Text(tr.text('delete'))))
                                  ],
                                  const SizedBox(width: 8),
                                  Expanded(
                                      child: FilledButton(
                                          onPressed: selected == null
                                              ? null
                                              : () => Navigator.pop(
                                                  sheetContext,
                                                  _QuickProductSlot(
                                                      productId: selected!.id,
                                                      shortName: nameController
                                                              .text
                                                              .trim()
                                                              .isEmpty
                                                          ? selected!.name
                                                          : nameController.text
                                                              .trim())),
                                          child: Text(tr.text('save'))))
                                ])
                              ]))));
            }));
    nameController.dispose();
    if (result == null) return;
    setState(() => page.slots[slotIndex] = result);
    if (!_quickGridEditMode) unawaited(_saveQuickProductPages());
  }
}
