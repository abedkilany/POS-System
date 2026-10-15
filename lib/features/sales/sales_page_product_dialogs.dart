// ignore_for_file: invalid_use_of_protected_member
part of 'sales_page.dart';

extension _SalesPageProductDialogs on _SalesPageState {
  String _cartLineTotalText(_DraftSaleItem item) => _formatSaleCurrency(
      _currencyFromBase(item.lineTotal, _invoiceCurrency), _invoiceCurrency);

  void _showQuickProductsSheet(List<Product> products) {
    final tr = AppLocalizations.of(context);
    _ensureQuickPages(products, tr);
    var sheetSelectedPageIndex =
        _selectedQuickPageIndex.clamp(0, _quickPages.length - 1).toInt();
    showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        isDismissible: false,
        enableDrag: false,
        builder: (sheetContext) =>
            StatefulBuilder(builder: (context, setModalState) {
              _ensureQuickPages(products, tr);
              sheetSelectedPageIndex = sheetSelectedPageIndex
                  .clamp(0, _quickPages.length - 1)
                  .toInt();
              final page = _quickPages[sheetSelectedPageIndex];
              final visibleSlotIndexes = _quickVisibleSlotIndexes(page);
              Future<bool> closeSheet() async {
                final navigator = Navigator.of(sheetContext);
                final canClose = await _confirmCloseQuickGridEditor();
                if (canClose && navigator.canPop()) navigator.pop();
                return canClose;
              }

              return PopScope(
                  canPop: false,
                  onPopInvokedWithResult: (didPop, result) {
                    if (didPop) return;
                    unawaited(closeSheet());
                  },
                  child: SafeArea(
                      child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                          child: SizedBox(
                              height:
                                  MediaQuery.sizeOf(sheetContext).height * 0.82,
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Row(children: [
                                      Expanded(
                                          child: Text(
                                              tr.text('quick_product_grid'),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleLarge)),
                                      _buildQuickTileSizeButton(context, tr,
                                          onChanged: () =>
                                              setModalState(() {})),
                                      IconButton(
                                          tooltip: tr.text('close'),
                                          onPressed: () {
                                            unawaited(closeSheet());
                                          },
                                          icon: const Icon(Icons.close))
                                    ]),
                                    const SizedBox(height: 8),
                                    Row(children: [
                                      Expanded(
                                          child: SizedBox(
                                              height: 42,
                                              child: _quickGridEditMode
                                                  ? ReorderableListView.builder(
                                                      scrollDirection:
                                                          Axis.horizontal,
                                                      buildDefaultDragHandles:
                                                          false,
                                                      itemCount:
                                                          _quickPages.length,
                                                      onReorderItem:
                                                          (oldIndex, newIndex) {
                                                        _moveQuickPage(
                                                            oldIndex, newIndex);
                                                        setModalState(() =>
                                                            sheetSelectedPageIndex =
                                                                _selectedQuickPageIndex);
                                                      },
                                                      proxyDecorator: (child, _,
                                                              __) =>
                                                          Material(
                                                              elevation: 6,
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          24),
                                                              child: child),
                                                      itemBuilder:
                                                          (context, index) {
                                                        final selected = index ==
                                                            sheetSelectedPageIndex;
                                                        return Padding(
                                                            key: ValueKey(
                                                                'mobile_quick_page_${index}_${_quickPages[index].name}'),
                                                            padding:
                                                                const EdgeInsetsDirectional.only(
                                                                    end: 8),
                                                            child: ReorderableDragStartListener(
                                                                index: index,
                                                                child: InputChip(
                                                                    avatar: const Icon(Icons.drag_indicator, size: 18),
                                                                    label: Row(mainAxisSize: MainAxisSize.min, children: [
                                                                      ConstrainedBox(
                                                                          constraints: const BoxConstraints(
                                                                              maxWidth:
                                                                                  120),
                                                                          child: Text(
                                                                              _quickPages[index].name,
                                                                              overflow: TextOverflow.ellipsis)),
                                                                      const SizedBox(
                                                                          width:
                                                                              4),
                                                                      const Icon(
                                                                          Icons
                                                                              .edit_outlined,
                                                                          size:
                                                                              16)
                                                                    ]),
                                                                    selected: selected,
                                                                    onSelected: (_) async {
                                                                      if (selected) {
                                                                        await _renameQuickPage(
                                                                            index);
                                                                        setModalState(
                                                                            () {});
                                                                      } else {
                                                                        setState(() =>
                                                                            _selectedQuickPageIndex =
                                                                                index);
                                                                        setModalState(() =>
                                                                            sheetSelectedPageIndex =
                                                                                index);
                                                                      }
                                                                    },
                                                                    deleteIcon: _quickPages.length > 1 ? const Icon(Icons.close, size: 18) : null,
                                                                    onDeleted: _quickPages.length > 1
                                                                        ? () {
                                                                            _deleteQuickPage(index);
                                                                            setModalState(() =>
                                                                                sheetSelectedPageIndex = _selectedQuickPageIndex);
                                                                          }
                                                                        : null)));
                                                      })
                                                  : ListView.separated(
                                                      scrollDirection:
                                                          Axis.horizontal,
                                                      itemCount:
                                                          _quickPages.length,
                                                      separatorBuilder:
                                                          (_, __) =>
                                                              const SizedBox(
                                                                  width: 8),
                                                      itemBuilder:
                                                          (context, index) {
                                                        final selected = index ==
                                                            sheetSelectedPageIndex;
                                                        return InputChip(
                                                            label: Text(
                                                                _quickPages[
                                                                        index]
                                                                    .name),
                                                            selected: selected,
                                                            onSelected: (_) {
                                                              setState(() =>
                                                                  _selectedQuickPageIndex =
                                                                      index);
                                                              setModalState(() =>
                                                                  sheetSelectedPageIndex =
                                                                      index);
                                                            });
                                                      }))),
                                      if (_quickGridEditMode) ...[
                                        const SizedBox(width: 8),
                                        ActionChip(
                                            avatar:
                                                const Icon(Icons.add, size: 18),
                                            label: Text(tr.text('page')),
                                            onPressed: () {
                                              _addQuickPage();
                                              setModalState(() =>
                                                  sheetSelectedPageIndex =
                                                      _selectedQuickPageIndex);
                                            })
                                      ]
                                    ]),
                                    const SizedBox(height: 10),
                                    if (_quickGridEditMode)
                                      Row(children: [
                                        Expanded(
                                            child: OutlinedButton.icon(
                                                onPressed: () {
                                                  _cancelQuickGridEditing();
                                                  setModalState(() =>
                                                      sheetSelectedPageIndex =
                                                          _selectedQuickPageIndex);
                                                },
                                                icon: const Icon(Icons.close),
                                                label:
                                                    Text(tr.text('cancel')))),
                                        const SizedBox(width: 8),
                                        Expanded(
                                            child: FilledButton.icon(
                                                onPressed: () {
                                                  _saveQuickGridEditing();
                                                  setModalState(() {});
                                                },
                                                icon: const Icon(Icons.check),
                                                label: Text(tr.text('save'))))
                                      ])
                                    else
                                      OutlinedButton.icon(
                                          onPressed: () {
                                            _startQuickGridEditing();
                                            setModalState(() {});
                                          },
                                          icon: const Icon(Icons.edit_outlined),
                                          label: Text(tr.text('edit_layout'))),
                                    const SizedBox(height: 12),
                                    Expanded(
                                        child: visibleSlotIndexes.isEmpty
                                            ? Center(
                                                child: Text(
                                                    tr.text('no_products')))
                                            : LayoutBuilder(builder:
                                                (context, constraints) {
                                                final crossAxisCount =
                                                    _quickTileColumnCount(
                                                        constraints.maxWidth);
                                                return GridView.builder(
                                                    itemCount:
                                                        visibleSlotIndexes
                                                            .length,
                                                    gridDelegate:
                                                        SliverGridDelegateWithFixedCrossAxisCount(
                                                            crossAxisCount:
                                                                crossAxisCount,
                                                            mainAxisSpacing: 10,
                                                            crossAxisSpacing:
                                                                10,
                                                            childAspectRatio:
                                                                1),
                                                    itemBuilder: (context,
                                                        visibleIndex) {
                                                      final slotIndex =
                                                          visibleSlotIndexes[
                                                              visibleIndex];
                                                      final slot =
                                                          page.slots[slotIndex];
                                                      final product = slot
                                                                  .productId ==
                                                              null
                                                          ? null
                                                          : _productById(
                                                              slot.productId!);
                                                      final isEmpty =
                                                          product == null;
                                                      final child =
                                                          _buildQuickProductTile(
                                                              context,
                                                              tr,
                                                              page,
                                                              slotIndex,
                                                              slot,
                                                              product,
                                                              isEmpty,
                                                              onChanged: () =>
                                                                  setModalState(
                                                                      () {}));
                                                      if (!_quickGridEditMode) {
                                                        return child;
                                                      }
                                                      final target = DragTarget<
                                                              int>(
                                                          onWillAcceptWithDetails:
                                                              (details) =>
                                                                  details
                                                                      .data !=
                                                                  slotIndex,
                                                          onAcceptWithDetails:
                                                              (details) {
                                                            _moveQuickSlot(
                                                                details.data,
                                                                slotIndex);
                                                            setModalState(
                                                                () {});
                                                          },
                                                          builder: (_,
                                                              candidateData,
                                                              ___) {
                                                            if (candidateData
                                                                .isEmpty) {
                                                              return child;
                                                            }
                                                            return DecoratedBox(
                                                                decoration: BoxDecoration(
                                                                    borderRadius:
                                                                        BorderRadius.circular(
                                                                            18),
                                                                    border: Border.all(
                                                                        color: Theme.of(context)
                                                                            .colorScheme
                                                                            .primary,
                                                                        width:
                                                                            2)),
                                                                child: child);
                                                          });
                                                      if (isEmpty) {
                                                        return target;
                                                      }
                                                      return LongPressDraggable<
                                                              int>(
                                                          data: slotIndex,
                                                          feedback: Material(
                                                              elevation: 6,
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          16),
                                                              child: SizedBox(
                                                                  width: 150,
                                                                  height: 120,
                                                                  child:
                                                                      child)),
                                                          childWhenDragging:
                                                              Opacity(
                                                                  opacity: 0.35,
                                                                  child: child),
                                                          child: target);
                                                    });
                                              }))
                                  ])))));
            }));
  }

  Future<String?> _scanCodeWithCameraOnce() async {
    final code = await Navigator.of(context).push<String>(MaterialPageRoute(
        builder: (_) => const PageTimingScope(
            pageKey: 'BarcodeScannerPage',
            pageLabel: 'Barcode scanner',
            child: BarcodeScannerPage())));
    final trimmed = code?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  void _showProductSearchSheet(List<Product> products) {
    final tr = AppLocalizations.of(context);
    final controller = TextEditingController(text: _search);
    final searchFocusNode = FocusNode(debugLabel: 'sale_product_search');
    _activeProductSearchFocusNode = searchFocusNode;
    BuildContext? searchSheetContext;
    void Function(VoidCallback)? modalSetState;
    List<({Product product, ProductSaleUnit unit})> currentSearchOptions =
        const [];
    int? selectedSearchIndex;
    final searchResultsScrollController = ScrollController();
    final searchResultKeys = <int, GlobalKey>{};
    var query = _search;
    final searchIndex = _productSearchIndex();
    void focusSearchField() {
      searchFocusNode.requestFocus();
      controller.selection =
          TextSelection(baseOffset: 0, extentOffset: controller.text.length);
    }

    void addSearchOption(int index) {
      if (index < 0 || index >= currentSearchOptions.length) return;
      final option = currentSearchOptions[index];
      selectedSearchIndex = index;
      modalSetState?.call(() {});
      _addProduct(option.product, saleUnit: option.unit);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        focusSearchField();
      });
    }

    void revealSearchOption(int index) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final optionContext = searchResultKeys[index]?.currentContext;
        if (optionContext == null) return;
        Scrollable.ensureVisible(optionContext,
            alignment: 0.45,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut);
      });
    }

    _activeProductSearchKeyHandler = (event) {
      if (event is! KeyDownEvent) return false;
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        final sheetContext = searchSheetContext;
        if (sheetContext != null && Navigator.of(sheetContext).canPop()) {
          Navigator.of(sheetContext).pop();
        }
        return true;
      }
      final keyName =
          SaleShortcutSettings.keyNameForLogicalKey(event.logicalKey);
      final configuredSearchKey = SaleShortcutSettings.load()
          .keyForSaleAction(SaleShortcutAction.searchProduct);
      if (keyName != null &&
          keyName == configuredSearchKey &&
          keyName != SaleShortcutSettings.noneKey &&
          keyName != 'Enter' &&
          keyName != 'Esc') {
        focusSearchField();
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
          event.logicalKey == LogicalKeyboardKey.arrowUp) {
        if (currentSearchOptions.isEmpty) return false;
        final lastIndex = currentSearchOptions.length - 1;
        final nextIndex = selectedSearchIndex == null
            ? (event.logicalKey == LogicalKeyboardKey.arrowDown ? 0 : lastIndex)
            : event.logicalKey == LogicalKeyboardKey.arrowDown
                ? math.min(lastIndex, selectedSearchIndex! + 1)
                : math.max(0, selectedSearchIndex! - 1);
        selectedSearchIndex = nextIndex;
        modalSetState?.call(() {});
        revealSearchOption(nextIndex);
        return true;
      }
      final digit = _productSearchDigitIndex(event.logicalKey);
      if (HardwareKeyboard.instance.isShiftPressed &&
          digit != null &&
          digit < currentSearchOptions.length) {
        selectedSearchIndex = digit;
        modalSetState?.call(() {});
        revealSearchOption(digit);
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter) {
        final index = selectedSearchIndex;
        if (index != null && index < currentSearchOptions.length) {
          addSearchOption(index);
          return true;
        }
      }
      return false;
    };
    searchFocusNode.onKeyEvent = (node, event) {
      final handler = _activeProductSearchKeyHandler;
      if (handler != null && handler(event)) {
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
    Future<List<Product>> loadSearchResults(String rawQuery) async {
      final normalized = rawQuery.trim().toLowerCase();
      if (normalized.isEmpty) return products;
      final sqlite = await LocalDatabaseService.queryProductsFromSqlite(
          query: normalized, limit: 250, activeOnly: true);
      if (sqlite != null) return sqlite.items;
      final allActiveProducts = widget.store.products
          .where((product) => product.isActive && !product.isDeleted)
          .where((product) =>
              searchIndex[product.id]?.contains(normalized) ?? false)
          .take(250)
          .toList(growable: false);
      return allActiveProducts;
    }

    Future<List<Product>>? searchFuture =
        query.trim().isEmpty ? null : loadSearchResults(query);
    Timer? revealTimer;
    int visibleCount = 100;
    int revealTargetCount = 0;
    void resetReveal() {
      revealTimer?.cancel();
      revealTimer = null;
      visibleCount = 100;
      revealTargetCount = 0;
    }

    void syncReveal(int totalCount, void Function(VoidCallback) setModalState) {
      revealTargetCount = totalCount;
      if (visibleCount > totalCount) {
        visibleCount = totalCount;
      }
      if (visibleCount >= totalCount) {
        revealTimer?.cancel();
        revealTimer = null;
        return;
      }
      revealTimer ??= Timer.periodic(const Duration(milliseconds: 20), (timer) {
        if (!mounted) {
          timer.cancel();
          revealTimer = null;
          return;
        }
        if (visibleCount >= revealTargetCount) {
          timer.cancel();
          revealTimer = null;
          return;
        }
        setModalState(() {
          visibleCount = math.min(revealTargetCount, visibleCount + 100);
        });
        if (visibleCount >= revealTargetCount) {
          timer.cancel();
          revealTimer = null;
        }
      });
    }

    showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) =>
            StatefulBuilder(builder: (context, setModalState) {
              searchSheetContext = sheetContext;
              modalSetState = setModalState;
              final q = query.trim().toLowerCase();
              return SafeArea(
                  child: Padding(
                      padding: EdgeInsets.only(
                          left: 16,
                          right: 16,
                          top: 16,
                          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom +
                              16),
                      child: SizedBox(
                          height: MediaQuery.sizeOf(sheetContext).height * 0.78,
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(children: [
                                  Expanded(
                                      child: Text(tr.text('search_product'),
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge))
                                ]),
                                const SizedBox(height: 12),
                                TextField(
                                    controller: controller,
                                    focusNode: searchFocusNode,
                                    autofocus: true,
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
                                              controller.text = code;
                                              setModalState(() {
                                                query = code;
                                                searchFuture =
                                                    loadSearchResults(code);
                                                resetReveal();
                                              });
                                            },
                                            icon: const Icon(
                                                Icons.camera_alt_outlined))),
                                    onChanged: (value) {
                                      setModalState(() {
                                        query = value;
                                        currentSearchOptions = const [];
                                        selectedSearchIndex = null;
                                        searchFuture = value.trim().isEmpty
                                            ? null
                                            : loadSearchResults(value);
                                        resetReveal();
                                      });
                                    }),
                                const SizedBox(height: 12),
                                Expanded(
                                    child: FutureBuilder<List<Product>>(
                                        future: searchFuture,
                                        builder: (context, snapshot) {
                                          if (searchFuture != null &&
                                              snapshot.connectionState !=
                                                  ConnectionState.done) {
                                            return const Center(
                                                child: CircularProgressIndicator
                                                    .adaptive());
                                          }
                                          final filteredProducts =
                                              snapshot.data ??
                                                  (q.isEmpty
                                                      ? products
                                                      : const <Product>[]);
                                          syncReveal(filteredProducts.length,
                                              setModalState);
                                          final visibleProducts =
                                              filteredProducts
                                                  .take(math.min(visibleCount,
                                                      filteredProducts.length))
                                                  .toList(growable: false);
                                          final searchOptions = <({
                                            Product product,
                                            ProductSaleUnit unit
                                          })>[];
                                          for (final product
                                              in visibleProducts) {
                                            for (final unit
                                                in product.effectiveSaleUnits) {
                                              searchOptions.add((
                                                product: product,
                                                unit: unit
                                              ));
                                            }
                                          }
                                          currentSearchOptions = searchOptions;
                                          if (searchOptions.isEmpty) {
                                            selectedSearchIndex = null;
                                          } else if (selectedSearchIndex ==
                                                  null ||
                                              selectedSearchIndex! >=
                                                  searchOptions.length) {
                                            selectedSearchIndex = 0;
                                          }
                                          if (searchOptions.isEmpty) {
                                            return Center(
                                                child: Text(
                                                    tr.text('no_products')));
                                          }
                                          return ListView.separated(
                                              controller:
                                                  searchResultsScrollController,
                                              itemCount: searchOptions.length,
                                              separatorBuilder: (_, __) =>
                                                  const Divider(height: 1),
                                              itemBuilder: (context, index) {
                                                final option =
                                                    searchOptions[index];
                                                final product = option.product;
                                                final unit = option.unit;
                                                final unitName =
                                                    unit.name.trim().isNotEmpty
                                                        ? unit.name.trim()
                                                        : product.unit;
                                                final barcode =
                                                    product.barcode.trim();
                                                final codeAndBarcode = barcode
                                                        .isEmpty
                                                    ? product.code
                                                    : '${product.code} • $barcode';
                                                final isSelected =
                                                    selectedSearchIndex ==
                                                        index;
                                                final colorScheme =
                                                    Theme.of(context)
                                                        .colorScheme;
                                                return ListTile(
                                                    key: searchResultKeys.putIfAbsent(
                                                        index, GlobalKey.new),
                                                    selected: isSelected,
                                                    selectedColor: colorScheme
                                                        .onPrimaryContainer,
                                                    selectedTileColor: colorScheme
                                                        .primaryContainer,
                                                    shape: RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                                8),
                                                        side: isSelected
                                                            ? BorderSide(
                                                                color: colorScheme
                                                                    .primary,
                                                                width: 2)
                                                            : BorderSide.none),
                                                    leading: index < 10
                                                        ? CircleAvatar(
                                                            radius: 14,
                                                            child:
                                                                Text('$index'))
                                                        : null,
                                                    title: Text('${product.name} — $unitName',
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis),
                                                    subtitle: Text(
                                                        '$codeAndBarcode • ${_stockAvailabilityLabel(product, tr)}',
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis),
                                                    trailing: Text(formatUsdReferenceAmount(_salePriceFor(product, unit), widget.store.storeProfile)),
                                                    onTap: () => addSearchOption(index));
                                              });
                                        }))
                              ]))));
            })).whenComplete(() {
      revealTimer?.cancel();
      _activeProductSearchKeyHandler = null;
      _activeProductSearchFocusNode = null;
      _search = '';
      _searchController.clear();
      _resetProductSearchReveal();
      searchFocusNode.dispose();
      controller.dispose();
      searchResultsScrollController.dispose();
    });
  }
}
