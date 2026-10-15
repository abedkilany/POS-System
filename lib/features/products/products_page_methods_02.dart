// ignore_for_file: invalid_use_of_protected_member
part of 'products_page.dart';

extension _ProductsPageStatePart2 on _ProductsPageState {
  Future<void> _openProductPriceHistory(
    BuildContext context,
    Product product,
  ) async {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isArabic
            ? 'سجل أسعار ${product.name}'
            : 'Price history — ${product.name}'),
        content: SizedBox(
          width: 760,
          height: 520,
          child: FutureBuilder<List<ProductPriceHistoryEntry>>(
            future: widget.store.productPriceHistoryForProduct(product.id),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator.adaptive());
              }
              final rows = snapshot.data ?? const <ProductPriceHistoryEntry>[];
              if (rows.isEmpty) {
                return Center(
                  child: Text(isArabic
                      ? 'لا يوجد سجل تغييرات أسعار لهذا المنتج بعد.'
                      : 'No price changes have been recorded for this product yet.'),
                );
              }
              return ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final row = rows[index];
                  final sign = row.newAmount > row.oldAmount
                      ? '+'
                      : row.newAmount < row.oldAmount
                          ? '−'
                          : '';
                  final percentText = row.changePercent > 0
                      ? ' • $sign${row.changePercent.toStringAsFixed(row.changePercent % 1 == 0 ? 0 : 2)}%'
                      : '';
                  final source = row.source == 'bulk'
                      ? (isArabic ? 'تعديل جماعي' : 'Bulk adjustment')
                      : (isArabic ? 'تعديل يدوي' : 'Manual change');
                  return ListTile(
                    leading: Icon(row.newAmount >= row.oldAmount
                        ? Icons.trending_up
                        : Icons.trending_down),
                    title: Text(
                      '${_priceTypeLabel(row.priceListId, isArabic)}: '
                      '${row.oldAmount} → ${row.newAmount} ${row.currencyCode}$percentText',
                    ),
                    subtitle: Text(
                      '${_formatHistoryDate(row.changedAt)} • $source'
                      '${row.userName.trim().isNotEmpty ? ' • ${row.userName}' : ''}',
                    ),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(isArabic ? 'إغلاق' : 'Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _openPriceList(BuildContext context) async {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final products = _filteredProducts(widget.store.products);
    if (products.isEmpty) return;
    final priceListTitle = isArabic ? 'بيانات المنتج' : 'Product data';
    final cancelText = isArabic ? 'إلغاء' : 'Cancel';
    final printText = isArabic ? 'طباعة' : 'Print';
    final selection = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) {
        final selections = <String>{..._priceListViews};
        return StatefulBuilder(
          builder: (_, setState) {
            final limitReached = selections.length >= 8;
            return AlertDialog(
              title: Text(priceListTitle),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          isArabic
                              ? 'اختر حتى 8 بيانات (${selections.length}/8)'
                              : 'Choose up to 8 fields (${selections.length}/8)',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ..._priceListFieldOptions().map((option) {
                        final selected = selections.contains(option.id);
                        return CheckboxListTile(
                          value: selected,
                          title:
                              Text(isArabic ? option.labelAr : option.labelEn),
                          controlAffinity: ListTileControlAffinity.leading,
                          onChanged: (checked) {
                            setState(() {
                              if (checked == true) {
                                if (!selected && selections.length >= 8) return;
                                selections.add(option.id);
                              } else {
                                selections.remove(option.id);
                              }
                            });
                          },
                        );
                      }),
                      if (limitReached)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            isArabic
                                ? 'وصلت للحد الأقصى: 8 بيانات'
                                : 'Maximum 8 fields reached',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(cancelText),
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.check),
                  label: Text(isArabic ? 'اعتماد' : 'Apply'),
                  onPressed: () {
                    if (selections.isEmpty) return;
                    Navigator.pop(dialogContext, selections);
                  },
                ),
              ],
            );
          },
        );
      },
    );
    if (selection == null) return;
    if (!context.mounted) return;
    _priceListViews
      ..clear()
      ..addAll(selection);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_priceListTitle(isArabic, selection)),
        content: SizedBox(
          width: 920,
          height: 520,
          child: ListView.builder(
            itemCount: products.length,
            itemBuilder: (_, index) {
              final p = products[index];
              return ListTile(
                dense: true,
                title: Text(p.name),
                subtitle: Text('${p.code} • ${p.category} • ${p.unit}'),
                trailing: Text(
                  _productFieldSummary(p, selection, isArabic),
                  textAlign: TextAlign.end,
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(cancelText)),
          FilledButton.icon(
            icon: const Icon(Icons.print_outlined),
            label: Text(printText),
            onPressed: () async {
              Navigator.pop(dialogContext);
              await PriceListPdfService.printPriceList(
                context: context,
                products: products,
                profile: widget.store.storeProfile,
                title: _priceListTitle(isArabic, selection),
                fields: selection.toList(growable: false),
                valueResolver: (product, field) =>
                    _priceFieldValue(product, field),
                arabic: isArabic,
              );
            },
          ),
        ],
      ),
    );
  }

  String _priceListTitle(bool isArabic, Set<String> selection) {
    final labels = <String>[
      ...selection.map((field) {
        final option =
            _priceListFieldOptions().firstWhere((item) => item.id == field);
        return isArabic ? option.labelAr : option.labelEn;
      }),
    ];
    return labels.isEmpty
        ? (isArabic ? 'قائمة الأسعار' : 'Price List')
        : '${isArabic ? 'قائمة الأسعار' : 'Price List'} - ${labels.join(' + ')}';
  }

  String _productFieldSummary(
      Product product, Set<String> selection, bool isArabic) {
    final values = selection
        .map((field) => _priceFieldLine(product, field, isArabic))
        .toList(growable: false);
    return values.isEmpty ? '-' : values.join('\n');
  }

  String _priceAmountLabel(bool isArabic, String selection) {
    switch (selection) {
      case 'name':
        return isArabic ? 'الاسم' : 'Name';
      case 'nameEn':
        return isArabic ? 'الاسم الإنجليزي' : 'English name';
      case 'nameAr':
        return isArabic ? 'الاسم العربي' : 'Arabic name';
      case 'code':
        return isArabic ? 'الكود' : 'Code';
      case 'barcode':
        return isArabic ? 'الباركود' : 'Barcode';
      case 'category':
        return isArabic ? 'الفئة' : 'Category';
      case 'brand':
        return isArabic ? 'الماركة' : 'Brand';
      case 'supplier':
        return isArabic ? 'المورد' : 'Supplier';
      case 'description':
        return isArabic ? 'الوصف' : 'Description';
      case 'unit':
        return isArabic ? 'الوحدة' : 'Unit';
      case 'quantityType':
        return isArabic ? 'نوع الكمية' : 'Quantity type';
      case 'stock':
        return isArabic ? 'المخزون' : 'Stock';
      case 'lowStockThreshold':
        return isArabic ? 'حد المخزون المنخفض' : 'Low stock threshold';
      case 'cost':
        return isArabic ? 'الكلفة' : 'Cost';
      case 'price':
        return isArabic ? 'التجزئة' : 'Retail';
      case 'wholesale_bulk':
        return isArabic ? 'جملة الجملة' : 'Wholesale bulk';
      case 'wholesale':
        return isArabic ? 'الجملة' : 'Wholesale';
      case 'isActive':
        return isArabic ? 'الحالة' : 'Status';
      case 'imagePath':
        return isArabic ? 'الصورة' : 'Image';
      case 'retail':
      default:
        return isArabic ? 'التجزئة' : 'Retail';
    }
  }

  String _priceAmountValue(Product product, String selection) {
    switch (selection) {
      case 'name':
        return product.name;
      case 'nameEn':
        return product.nameEn;
      case 'nameAr':
        return product.nameAr;
      case 'code':
        return product.code;
      case 'barcode':
        return product.barcode;
      case 'category':
        return product.category;
      case 'brand':
        return product.brand;
      case 'supplier':
        return product.supplier;
      case 'description':
        return product.description;
      case 'unit':
        return product.unit;
      case 'quantityType':
        return product.quantityType == ProductQuantityType.measurable
            ? 'measurable'
            : 'countable';
      case 'stock':
        return product.stock.toStringAsFixed(2);
      case 'lowStockThreshold':
        return product.lowStockThreshold.toString();
      case 'cost':
        return '${product.costCurrency.toUpperCase()} ${product.originalCost.toStringAsFixed(2)}';
      case 'price':
        return '${product.originalCurrency} ${product.originalPrice.toStringAsFixed(2)}';
      case 'wholesale':
        final price = widget.store.productPriceFor(product.id, 'wholesale');
        final value = price?.baseAmount ?? product.originalPrice;
        return '${price?.baseCurrencyCode.toUpperCase() ?? product.originalCurrency} ${value.toStringAsFixed(2)}';
      case 'wholesale_bulk':
        final price =
            widget.store.productPriceFor(product.id, 'wholesale_bulk');
        final value = price?.baseAmount ?? product.originalPrice;
        return '${price?.baseCurrencyCode.toUpperCase() ?? product.originalCurrency} ${value.toStringAsFixed(2)}';
      case 'isActive':
        return product.isActive ? 'Active' : 'Inactive';
      case 'imagePath':
        return product.imagePath.isEmpty ? '-' : product.imagePath;
      default:
        return '-';
    }
  }

  String _priceFieldLine(Product product, String field, bool isArabic) {
    return '${_priceAmountLabel(isArabic, field)}: ${_priceAmountValue(product, field)}';
  }

  String _priceFieldValue(Product product, String field) {
    return _priceAmountValue(product, field);
  }

  List<_PriceListFieldOption> _priceListFieldOptions() {
    return const <_PriceListFieldOption>[
      _PriceListFieldOption(id: 'name', labelAr: 'الاسم', labelEn: 'Name'),
      _PriceListFieldOption(
          id: 'nameEn', labelAr: 'الاسم الإنجليزي', labelEn: 'English name'),
      _PriceListFieldOption(
          id: 'nameAr', labelAr: 'الاسم العربي', labelEn: 'Arabic name'),
      _PriceListFieldOption(id: 'code', labelAr: 'الكود', labelEn: 'Code'),
      _PriceListFieldOption(
          id: 'barcode', labelAr: 'الباركود', labelEn: 'Barcode'),
      _PriceListFieldOption(
          id: 'category', labelAr: 'الفئة', labelEn: 'Category'),
      _PriceListFieldOption(id: 'brand', labelAr: 'الماركة', labelEn: 'Brand'),
      _PriceListFieldOption(
          id: 'supplier', labelAr: 'المورد', labelEn: 'Supplier'),
      _PriceListFieldOption(
          id: 'description', labelAr: 'الوصف', labelEn: 'Description'),
      _PriceListFieldOption(id: 'unit', labelAr: 'الوحدة', labelEn: 'Unit'),
      _PriceListFieldOption(
          id: 'quantityType', labelAr: 'نوع الكمية', labelEn: 'Quantity type'),
      _PriceListFieldOption(id: 'stock', labelAr: 'المخزون', labelEn: 'Stock'),
      _PriceListFieldOption(
          id: 'lowStockThreshold',
          labelAr: 'حد المخزون المنخفض',
          labelEn: 'Low stock threshold'),
      _PriceListFieldOption(id: 'cost', labelAr: 'الكلفة', labelEn: 'Cost'),
      _PriceListFieldOption(id: 'price', labelAr: 'التجزئة', labelEn: 'Retail'),
      _PriceListFieldOption(
          id: 'wholesale', labelAr: 'الجملة', labelEn: 'Wholesale'),
      _PriceListFieldOption(
          id: 'wholesale_bulk',
          labelAr: 'جملة الجملة',
          labelEn: 'Wholesale bulk'),
      _PriceListFieldOption(
          id: 'isActive', labelAr: 'الحالة', labelEn: 'Status'),
      _PriceListFieldOption(
          id: 'imagePath', labelAr: 'الصورة', labelEn: 'Image'),
    ];
  }

  List<Product> _filteredProducts(List<Product> source) {
    final value = query.trim().toLowerCase();
    final revision = widget.store.productsRevision;
    if (_cachedRevision != revision) {
      _cachedProductSource = null;
      _cachedCategorySource = null;
      _cachedQuery = '';
      _cachedCategoryFilter = 'All';
      _cachedFilteredProducts = const <Product>[];
      _cachedCategories = const <String>[];
      _rowCache.clear();
      _searchIndexCache.clear();
      _cachedRevision = revision;
    }
    if (identical(source, _cachedProductSource) &&
        _cachedQuery == value &&
        _cachedCategoryFilter == categoryFilter) {
      return _cachedFilteredProducts;
    }
    if (_cachedProductSource != null &&
        !identical(source, _cachedProductSource)) {
      _rowCache.clear();
      _searchIndexCache.clear();
    }
    Stopwatch? sw;
    if (kDebugMode) {
      sw = Stopwatch()..start();
    }
    final filtered = source.where((product) {
      final matchesQuery =
          value.isEmpty || _searchIndexFor(product).contains(value);
      final matchesCategory =
          categoryFilter == 'All' || product.category == categoryFilter;
      return matchesQuery && matchesCategory;
    }).toList(growable: false);
    filtered
        .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _cachedProductSource = source;
    _cachedQuery = value;
    _cachedCategoryFilter = categoryFilter;
    _cachedFilteredProducts = filtered;
    if (kDebugMode) {
      final elapsed = sw?.elapsedMicroseconds ?? 0;
      if (elapsed > 2000) {
        debugPrint(
          '[ProductsPage] filter query="$value" category="$categoryFilter" '
          'products=${source.length} matched=${filtered.length} '
          'took=${elapsed / 1000.0}ms',
        );
      }
    }
    return filtered;
  }

  String _searchIndexFor(Product product) {
    final cached = _searchIndexCache[product.id];
    if (cached != null) return cached;
    final buffer = StringBuffer()
      ..write(product.name)
      ..write(' ')
      ..write(product.nameEn)
      ..write(' ')
      ..write(product.nameAr)
      ..write(' ')
      ..write(product.code)
      ..write(' ')
      ..write(product.barcode)
      ..write(' ')
      ..write(product.category)
      ..write(' ')
      ..write(product.brand)
      ..write(' ')
      ..write(product.supplier)
      ..write(' ')
      ..write(product.unit);
    for (final unit in product.saleUnits) {
      buffer
        ..write(' ')
        ..write(unit.name)
        ..write(' ')
        ..write(unit.barcode);
    }
    for (final unit in product.purchaseUnits) {
      buffer
        ..write(' ')
        ..write(unit.name)
        ..write(' ')
        ..write(unit.barcode);
    }
    final value = buffer.toString().toLowerCase();
    _searchIndexCache[product.id] = value;
    return value;
  }

  List<String> _categoriesFor(List<Product> source) {
    if (_cachedRevision != widget.store.productsRevision) {
      _cachedCategorySource = null;
      _cachedCategories = const <String>[];
    }
    if (identical(source, _cachedCategorySource)) {
      return _cachedCategories;
    }
    final categories = <String>{
      'All',
      ...source.map((p) => p.category).where((e) => e.trim().isNotEmpty)
    }.toList()
      ..sort();
    _cachedCategorySource = source;
    _cachedCategories = categories;
    return categories;
  }

  _ProductRowData _rowDataFor(
    Product product,
    AppLocalizations tr,
    String localeTag, {
    ProductCostSnapshot? costSnapshot,
  }) {
    final cacheKey = product.id;
    final costSignature = costSnapshot == null
        ? 'fallback'
        : '${costSnapshot.currentInventoryUnitCost}|${costSnapshot.inventoryQuantity}|${costSnapshot.batchCount}|${costSnapshot.lastPurchaseUnitCost}|${costSnapshot.referenceUnitCost}';
    final signature =
        '${widget.store.productsPageRevision}|$localeTag|$costSignature';
    final cached = _rowCache[cacheKey];
    if (cached != null && cached.signature == signature) {
      return cached.row;
    }
    Stopwatch? sw;
    if (kDebugMode) {
      sw = Stopwatch()..start();
    }
    final row = _ProductRowData.fromStore(
      product,
      widget.store,
      widget.store.storeProfile,
      tr,
      costSnapshot: costSnapshot,
    );
    _rowCache[cacheKey] = _RowCacheEntry(signature, row);
    if (kDebugMode) {
      final elapsed = sw?.elapsedMicroseconds ?? 0;
      if (elapsed > 1000) {
        debugPrint(
          '[ProductsPage] row productId=${product.id} '
          'revision=${widget.store.productsPageRevision} took=${elapsed / 1000.0}ms',
        );
      }
    }
    return row;
  }

  Future<void> _deleteProduct(BuildContext context, Product product) async {
    if (!widget.store.canManageProducts) return;
    final tr = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(tr.text('confirm_delete')),
        content: Text('${tr.text('delete_confirm_message')} ${product.name}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr.text('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr.text('delete'))),
        ],
      ),
    );
    if (confirmed == true) await widget.store.deleteProduct(product.id);
  }

  Future<void> _openCatalogManager(BuildContext context, String type) async {
    if (!widget.store.canManageProducts) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _CatalogManagerDialog(store: widget.store, type: type),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openProductForm(BuildContext context,
      {Product? product}) async {
    if (!widget.store.canManageProducts) return;
    final tr = AppLocalizations.of(context);
    final result = await showDialog<_ProductFormResult>(
      context: context,
      builder: (_) => _ProductDialog(store: widget.store, product: product),
    );
    if (result == null) return;
    try {
      await widget.store.addOrUpdateProduct(result.product);
      if (result.priceSave != null) {
        await result.priceSave!();
      }
      if (result.supplierPriceSave != null) {
        await result.supplierPriceSave!();
      }
      if (result.addToQuickProducts) {
        await _addProductToQuickProducts(result.product, tr);
      }
      if (mounted) {
        _invalidateProductViewCaches();
        setState(() {});
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(product == null
                ? tr.text('product_saved')
                : tr.text('product_updated'))));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                error.toString().replaceFirst('Invalid argument(s): ', ''))));
      }
    }
  }

  Future<void> _addProductToQuickProducts(
      Product product, AppLocalizations tr) async {
    const storageKey = 'sale_quick_product_pages_v1';
    List<dynamic> pages;
    try {
      final raw = LocalDatabaseService.getString(storageKey);
      pages = raw == null || raw.trim().isEmpty
          ? <dynamic>[]
          : jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      pages = <dynamic>[];
    }
    if (pages.isEmpty) {
      pages = [
        {
          'name': '${tr.text('page')} 1',
          'slots':
              List.generate(12, (_) => {'productId': null, 'shortName': null}),
        }
      ];
    }
    final shortName = (tr.locale.languageCode == 'ar'
            ? (product.nameAr.trim().isNotEmpty
                ? product.nameAr.trim()
                : product.nameEn.trim().isNotEmpty
                    ? product.nameEn.trim()
                    : product.name.trim())
            : (product.nameEn.trim().isNotEmpty
                ? product.nameEn.trim()
                : product.nameAr.trim().isNotEmpty
                    ? product.nameAr.trim()
                    : product.name.trim()))
        .trim();
    for (final page in pages) {
      if (page is! Map) continue;
      final slots = page['slots'];
      if (slots is! List) continue;
      for (var i = 0; i < slots.length; i++) {
        final slot = slots[i];
        if (slot is Map && slot['productId'] == product.id) return;
      }
    }
    for (final page in pages) {
      if (page is! Map) continue;
      final slots = page['slots'];
      if (slots is! List) continue;
      for (var i = 0; i < slots.length; i++) {
        final slot = slots[i];
        final isEmpty = slot is! Map ||
            (slot['productId'] as String?)?.trim().isEmpty != false;
        if (isEmpty) {
          slots[i] = {
            'productId': product.id,
            'shortName':
                shortName.length > 14 ? shortName.substring(0, 14) : shortName
          };
          await LocalDatabaseService.setString(storageKey, jsonEncode(pages));
          return;
        }
      }
    }
    final first = pages.first;
    if (first is Map) {
      final slots = first['slots'];
      if (slots is List) {
        slots.add({
          'productId': product.id,
          'shortName':
              shortName.length > 14 ? shortName.substring(0, 14) : shortName
        });
      }
    }
    await LocalDatabaseService.setString(storageKey, jsonEncode(pages));
  }
}
