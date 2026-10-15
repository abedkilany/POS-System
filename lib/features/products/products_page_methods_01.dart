// ignore_for_file: invalid_use_of_protected_member
part of 'products_page.dart';

extension _ProductsPageStatePart1 on _ProductsPageState {
  void _handleStoreChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _refreshPricingData() async {
    try {
      await widget.store.refreshAfterDatabaseChange('price_lists_v1');
      await widget.store.refreshAfterDatabaseChange('product_prices_v1');
    } catch (_) {
      // If the targeted refresh fails, the page will still fall back to the
      // existing store state instead of blocking the UI.
    }
  }

  void _invalidateProductViewCaches() {
    _productsQueryFuture = null;
    _productsQueryFutureKey = '';
    _cachedRevision = -1;
    _cachedProductSource = null;
    _cachedCategorySource = null;
    _cachedFilteredProducts = const <Product>[];
    _cachedCategories = const <String>[];
    _rowCache.clear();
    _searchIndexCache.clear();
    _resetProductReveal();
  }

  void _resetProductReveal() {
    _productRevealTimer?.cancel();
    _productRevealTimer = null;
    _visibleProductCount = 100;
    _productRevealTargetCount = 0;
  }

  void _syncProductReveal(int totalCount) {
    _productRevealTargetCount = totalCount;
    if (_visibleProductCount > totalCount) {
      _visibleProductCount = totalCount;
    }
    if (_visibleProductCount >= totalCount) {
      _productRevealTimer?.cancel();
      _productRevealTimer = null;
      return;
    }
    _productRevealTimer ??=
        Timer.periodic(const Duration(milliseconds: 20), (timer) {
      if (!mounted) {
        timer.cancel();
        _productRevealTimer = null;
        return;
      }
      if (_visibleProductCount >= _productRevealTargetCount) {
        timer.cancel();
        _productRevealTimer = null;
        return;
      }
      setState(() {
        _visibleProductCount = math.min(
          _productRevealTargetCount,
          _visibleProductCount + 100,
        );
      });
      if (_visibleProductCount >= _productRevealTargetCount) {
        timer.cancel();
        _productRevealTimer = null;
      }
    });
  }

  Future<void> _scanProductSearchBarcode() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const PageTimingScope(
          pageKey: 'BarcodeScannerPage',
          pageLabel: 'Barcode scanner',
          child: BarcodeScannerPage(),
        ),
      ),
    );
    if (!mounted || code == null || code.trim().isEmpty) return;
    setState(() {
      query = code.trim();
      _searchController.text = query;
      _resetProductReveal();
    });
  }

  Widget _buildProductsFromMemory(
    BuildContext context,
    AppLocalizations tr,
    String localeTag,
  ) {
    final allProducts = widget.store.products;
    final products = _filteredProducts(allProducts);
    final categories = _categoriesFor(allProducts);
    _syncProductReveal(products.length);
    final visibleProducts = products
        .take(math.min(_visibleProductCount, products.length))
        .toList(growable: false);
    return _buildProductsView(
      context,
      tr,
      localeTag: localeTag,
      products: visibleProducts,
      totalCount: products.length,
      categories: categories,
    );
  }

  Future<_ProductsQueryResult?> _queryProductsFromSqlite(String value) {
    final limit = math.max(1, _visibleProductCount);
    final key =
        '${widget.store.productsPageRevision}|$value|$categoryFilter|$limit';
    if (_productsQueryFuture == null || _productsQueryFutureKey != key) {
      _productsQueryFutureKey = key;
      _productsQueryFuture = () async {
        final page = await LocalDatabaseService.queryProductsFromSqlite(
          query: value,
          category: categoryFilter,
          limit: limit,
        );
        if (page == null) return null;
        final categories =
            await LocalDatabaseService.queryProductCategoriesFromSqlite() ??
                const <String>[];
        final costSnapshots =
            await widget.store.productCostSnapshotsForProducts(page.items);
        return _ProductsQueryResult(
          items: page.items,
          totalCount: page.totalCount,
          categories: _categoryItemsForSql(categories),
          costSnapshots: costSnapshots,
        );
      }();
    }
    return _productsQueryFuture!;
  }

  List<String> _categoryItemsForSql(List<String> categories) {
    final tail = categories
        .where((item) => item.trim().isNotEmpty && item != 'All')
        .toSet()
        .toList()
      ..sort();
    if (categoryFilter != 'All' && !tail.contains(categoryFilter)) {
      tail.add(categoryFilter);
      tail.sort();
    }
    return <String>['All', ...tail];
  }

  void _loadMoreProducts(int totalCount) {
    setState(() {
      _productRevealTimer?.cancel();
      _productRevealTimer = null;
      _visibleProductCount = math.min(totalCount, _visibleProductCount + 100);
    });
  }

  Widget _buildProductsView(
    BuildContext context,
    AppLocalizations tr, {
    required String localeTag,
    required List<Product> products,
    required int totalCount,
    required List<String> categories,
    Map<String, ProductCostSnapshot> costSnapshots =
        const <String, ProductCostSnapshot>{},
    bool loading = false,
    VoidCallback? onLoadMore,
  }) {
    final canBulkAdjustPrices = widget.store.hasAnyPermission(<String>{
      AppPermission.productsManage,
      AppPermission.productsEdit,
    });
    final categoryItems = categories.contains(categoryFilter)
        ? categories
        : <String>[
            'All',
            ...categories.where((item) => item != 'All'),
            if (categoryFilter != 'All') categoryFilter,
          ];
    final selectedCategory =
        categoryItems.contains(categoryFilter) ? categoryFilter : 'All';
    final hasLoadMore = onLoadMore != null;

    return Padding(
      padding: VentioResponsive.pageInsets(context),
      child: Column(
        children: [
          AppSectionHeader(
            title: tr.text('products'),
            subtitle: tr.text('products_page_desc'),
            action: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                PageDataLoadIndicator(
                  loadedCount: products.length,
                  totalCount: totalCount,
                ),
                FilledButton.tonalIcon(
                  onPressed:
                      canBulkAdjustPrices && _selectedProductIds.isNotEmpty
                          ? () => _openBulkPriceAdjustment(context)
                          : null,
                  icon: const Icon(Icons.percent_outlined),
                  label: Text(
                    Localizations.localeOf(context).languageCode == 'ar'
                        ? 'تعديل الأسعار (${_selectedProductIds.length})'
                        : 'Adjust prices (${_selectedProductIds.length})',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _openPriceList(context),
                  icon: const Icon(Icons.print_outlined),
                  label: Text(tr.text('price_list')),
                ),
                OutlinedButton.icon(
                  onPressed: widget.store.canManageProducts
                      ? () => _openCatalogManager(context, 'category')
                      : null,
                  icon: const Icon(Icons.category_outlined),
                  label: Text(tr.text('manage_categories')),
                ),
                OutlinedButton.icon(
                  onPressed: widget.store.canManageProducts
                      ? () => _openCatalogManager(context, 'brand')
                      : null,
                  icon: const Icon(Icons.label_outline),
                  label: Text(tr.text('brand')),
                ),
                OutlinedButton.icon(
                  onPressed: widget.store.canManageProducts
                      ? () => _openCatalogManager(context, 'unit')
                      : null,
                  icon: const Icon(Icons.straighten_outlined),
                  label: Text(tr.text('manage_units')),
                ),
                FilledButton.icon(
                  onPressed: widget.store.canManageProducts
                      ? () => _openProductForm(context)
                      : null,
                  icon: const Icon(Icons.add),
                  label: Text(tr.text('add_product')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final searchField = TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: tr.text('search_products_pro'),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    tooltip: tr.text('scan_with_camera'),
                    onPressed: _scanProductSearchBarcode,
                    icon: const Icon(Icons.camera_alt_outlined),
                  ),
                ),
                onChanged: (value) => setState(() {
                  query = value;
                  _resetProductReveal();
                }),
              );
              final categoryField = DropdownButtonFormField<String>(
                initialValue: selectedCategory,
                decoration: InputDecoration(labelText: tr.text('category')),
                items: categoryItems
                    .map((item) => DropdownMenuItem(
                        value: item,
                        child: Text(item == 'All' ? tr.text('all') : item)))
                    .toList(),
                onChanged: (value) => setState(() {
                  categoryFilter = value ?? 'All';
                  _resetProductReveal();
                }),
              );
              if (constraints.maxWidth < 620) {
                return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      searchField,
                      const SizedBox(height: 12),
                      categoryField
                    ]);
              }
              return Row(children: [
                Expanded(child: searchField),
                const SizedBox(width: 12),
                SizedBox(
                    width: VentioResponsive.adaptiveWidth(context,
                        mobile: 160, tablet: 200, desktop: 220),
                    child: categoryField)
              ]);
            },
          ),
          const SizedBox(height: 12),
          if (canBulkAdjustPrices)
            _ProductSelectionBar(
              selectedCount: _selectedProductIds.length,
              visibleCount: products.length,
              allVisibleSelected: products.isNotEmpty &&
                  products
                      .every((item) => _selectedProductIds.contains(item.id)),
              someVisibleSelected:
                  products.any((item) => _selectedProductIds.contains(item.id)),
              onToggleVisible: (selected) {
                setState(() {
                  if (selected) {
                    _selectedProductIds.addAll(products.map((item) => item.id));
                  } else {
                    _selectedProductIds
                        .removeAll(products.map((item) => item.id));
                  }
                });
              },
              onClear: () => setState(_selectedProductIds.clear),
            ),
          if (canBulkAdjustPrices) const SizedBox(height: 12),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator.adaptive())
                : totalCount == 0
                    ? EmptyStateCard(
                        icon: Icons.inventory_2_outlined,
                        title: tr.text('no_products'),
                        subtitle: tr.text('no_products_desc'))
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final rowExtent =
                              constraints.maxWidth < 620 ? 158.0 : 94.0;
                          return ListView.builder(
                            itemExtent: rowExtent,
                            itemCount: products.length + (hasLoadMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index >= products.length) {
                                return Center(
                                  child: TextButton.icon(
                                    onPressed: onLoadMore,
                                    icon: const Icon(Icons.expand_more),
                                    label: Text(
                                      '${tr.text('more')} '
                                      '(${products.length}/$totalCount)',
                                    ),
                                  ),
                                );
                              }
                              final product = products[index];
                              final row = _rowDataFor(
                                product,
                                tr,
                                localeTag,
                                costSnapshot: costSnapshots[product.id],
                              );
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _ProductTile(
                                  row: row,
                                  compact: constraints.maxWidth < 620,
                                  selected:
                                      _selectedProductIds.contains(product.id),
                                  onSelectedChanged: canBulkAdjustPrices
                                      ? (value) => setState(() {
                                            if (value == true) {
                                              _selectedProductIds
                                                  .add(product.id);
                                            } else {
                                              _selectedProductIds
                                                  .remove(product.id);
                                            }
                                          })
                                      : null,
                                  onHistory: () => _openProductPriceHistory(
                                    context,
                                    row.product,
                                  ),
                                  onEdit: widget.store.canManageProducts
                                      ? () => _openProductForm(context,
                                          product: row.product)
                                      : null,
                                  onDelete: widget.store
                                          .hasAnyPermission(<String>{
                                    AppPermission.productsDelete,
                                    AppPermission.productsManage,
                                  })
                                      ? () =>
                                          _deleteProduct(context, row.product)
                                      : null,
                                ),
                              );
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  String _priceTypeLabel(String priceListId, bool isArabic) {
    switch (priceListId) {
      case 'wholesale':
        return isArabic ? 'الجملة' : 'Wholesale';
      case 'wholesale_bulk':
        return isArabic ? 'جملة الجملة' : 'Wholesale bulk';
      case 'retail':
      default:
        return isArabic ? 'المفرق' : 'Retail';
    }
  }

  double _roundedPreviewPrice(double amount, String currencyCode) {
    final decimals = widget.store.storeProfile
        .currencyByCode(currencyCode)
        .decimalPlaces
        .clamp(0, 6);
    final factor = math.pow(10, decimals).toDouble();
    return (amount * factor).round() / factor;
  }

  Future<void> _openBulkPriceAdjustment(BuildContext context) async {
    if (_selectedProductIds.isEmpty) return;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    await widget.store.ensureProductsLoaded();
    await widget.store.ensureProductPricesLoaded();
    if (!context.mounted) return;
    var priceListId = 'retail';
    var increase = true;
    final percentController = TextEditingController(text: '3');
    var submitting = false;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final percentage = double.tryParse(
                  percentController.text.trim().replaceAll(',', '.')) ??
              0;
          final selectedProducts = widget.store.products
              .where((item) => _selectedProductIds.contains(item.id))
              .toList(growable: false);
          final previewRows = <String>[];
          var missingCount = 0;
          var adjustableCount = 0;
          var unchangedPreviewCount = 0;
          final validPercent = percentage > 0 &&
              percentage.isFinite &&
              (increase || percentage <= 100);
          for (final product in selectedProducts) {
            final price = widget.store.productPriceFor(
              product.id,
              priceListId,
            );
            if (price == null) {
              missingCount += 1;
              continue;
            }
            if (!validPercent) continue;
            final factor =
                increase ? 1 + percentage / 100 : 1 - percentage / 100;
            final next = _roundedPreviewPrice(
              price.baseAmount * factor,
              price.baseCurrencyCode,
            );
            if ((next - price.baseAmount).abs() < 0.0000001) {
              unchangedPreviewCount += 1;
              continue;
            }
            adjustableCount += 1;
            if (previewRows.length < 5) {
              previewRows.add(
                '${product.name}: ${price.baseAmount} ${price.baseCurrencyCode} → $next ${price.baseCurrencyCode}',
              );
            }
          }
          return AlertDialog(
            title: Text(
                isArabic ? 'تعديل الأسعار الجماعي' : 'Bulk price adjustment'),
            content: SizedBox(
              width: 620,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      isArabic
                          ? 'تم تحديد ${_selectedProductIds.length} منتج.'
                          : '${_selectedProductIds.length} products selected.',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: priceListId,
                      decoration: InputDecoration(
                        labelText: isArabic
                            ? 'السعر المطلوب تعديله'
                            : 'Price to adjust',
                      ),
                      items: <String>['retail', 'wholesale', 'wholesale_bulk']
                          .map((id) => DropdownMenuItem(
                                value: id,
                                child: Text(_priceTypeLabel(id, isArabic)),
                              ))
                          .toList(),
                      onChanged: submitting
                          ? null
                          : (value) => setDialogState(
                                () => priceListId = value ?? 'retail',
                              ),
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<bool>(
                      segments: [
                        ButtonSegment<bool>(
                          value: true,
                          icon: const Icon(Icons.trending_up),
                          label: Text(isArabic ? 'زيادة' : 'Increase'),
                        ),
                        ButtonSegment<bool>(
                          value: false,
                          icon: const Icon(Icons.trending_down),
                          label: Text(isArabic ? 'إنقاص' : 'Decrease'),
                        ),
                      ],
                      selected: <bool>{increase},
                      onSelectionChanged: submitting
                          ? null
                          : (value) => setDialogState(
                                () => increase = value.first,
                              ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: percentController,
                      enabled: !submitting,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      decoration: InputDecoration(
                        labelText: isArabic ? 'النسبة %' : 'Percentage %',
                        suffixText: '%',
                        errorText: percentController.text.trim().isNotEmpty &&
                                !validPercent
                            ? (isArabic
                                ? 'أدخل نسبة صحيحة. الإنقاص لا يمكن أن يتجاوز 100%.'
                                : 'Enter a valid percentage. Decrease cannot exceed 100%.')
                            : null,
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isArabic
                                ? 'سيتم تعديل $adjustableCount منتج.'
                                : '$adjustableCount products will be updated.',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          if (missingCount > 0) ...[
                            const SizedBox(height: 4),
                            Text(
                              isArabic
                                  ? '$missingCount منتج لا يملك سعر ${_priceTypeLabel(priceListId, true)} وسيتم تجاهله.'
                                  : '$missingCount products do not have a ${_priceTypeLabel(priceListId, false)} price and will be skipped.',
                            ),
                          ],
                          if (unchangedPreviewCount > 0) ...[
                            const SizedBox(height: 4),
                            Text(
                              isArabic
                                  ? '$unchangedPreviewCount منتج لن يتغير سعره بعد التقريب.'
                                  : '$unchangedPreviewCount products remain unchanged after rounding.',
                            ),
                          ],
                          if (previewRows.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Text(isArabic ? 'معاينة:' : 'Preview:'),
                            const SizedBox(height: 4),
                            ...previewRows.map((line) => Padding(
                                  padding: const EdgeInsets.only(top: 3),
                                  child: Text(line),
                                )),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: submitting
                    ? null
                    : () => Navigator.pop(dialogContext, false),
                child: Text(isArabic ? 'إلغاء' : 'Cancel'),
              ),
              FilledButton.icon(
                icon: submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: Text(isArabic ? 'تحديث الأسعار' : 'Update prices'),
                onPressed: submitting || !validPercent || adjustableCount == 0
                    ? null
                    : () async {
                        setDialogState(() => submitting = true);
                        try {
                          final result =
                              await widget.store.bulkAdjustProductPrices(
                            productIds: _selectedProductIds,
                            priceListId: priceListId,
                            percentage: percentage,
                            increase: increase,
                          );
                          if (!dialogContext.mounted) return;
                          Navigator.pop(dialogContext, true);
                          if (!mounted) return;
                          setState(() {
                            _selectedProductIds.clear();
                            _invalidateProductViewCaches();
                          });
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            SnackBar(
                              content: Text(
                                isArabic
                                    ? 'تم تحديث ${result.updatedCount} سعر بنجاح${result.skippedMissingPriceCount > 0 ? '، وتجاهل ${result.skippedMissingPriceCount} بدون سعر' : ''}${result.unchangedCount > 0 ? '، و${result.unchangedCount} بدون تغيير بعد التقريب' : ''}.'
                                    : '${result.updatedCount} prices updated successfully${result.skippedMissingPriceCount > 0 ? '; ${result.skippedMissingPriceCount} missing prices skipped' : ''}${result.unchangedCount > 0 ? '; ${result.unchangedCount} unchanged after rounding' : ''}.',
                              ),
                            ),
                          );
                        } catch (error) {
                          if (!dialogContext.mounted) return;
                          setDialogState(() => submitting = false);
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            SnackBar(content: Text(error.toString())),
                          );
                        }
                      },
              ),
            ],
          );
        },
      ),
    );
    percentController.dispose();
    if (confirmed == true && mounted) setState(() {});
  }

  String _formatHistoryDate(DateTime value) {
    String two(int v) => v.toString().padLeft(2, '0');
    final local = value.toLocal();
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }
}
