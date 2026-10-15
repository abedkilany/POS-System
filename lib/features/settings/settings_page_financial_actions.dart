part of 'settings_page.dart';

extension _FinancialActions on SettingsPage {
  String _priceDisplayModeLabel(AppLocalizations tr, StoreProfile profile) {
    switch (profile.priceDisplayMode) {
      case 'multiple':
        final codes = profile.priceDisplayCurrencies.isEmpty
            ? profile.currencies
                .where((item) => item.isActive)
                .map((item) => item.code)
                .join(', ')
            : profile.priceDisplayCurrencies.join(', ');
        return '${tr.text('price_display_multiple')} · $codes';
      case 'selectable':
        return tr.text('price_display_selectable');
      case 'default':
      default:
        return tr.text('price_display_default');
    }
  }

  Future<void> _editFinancialSettings(
      BuildContext context, StoreProfile profile) async {
    final tr = AppLocalizations.of(context);
    final activeCodes = profile.currencies
        .where((item) => item.isActive)
        .map((item) => item.code)
        .toList();
    String baseCurrency = activeCodes.contains(profile.baseCurrency)
        ? profile.baseCurrency
        : activeCodes.first;
    String displayMode =
        {'default', 'selectable', 'multiple'}.contains(profile.priceDisplayMode)
            ? profile.priceDisplayMode
            : 'default';
    final displayCurrencies = profile.priceDisplayCurrencies
        .where((code) => activeCodes.contains(code))
        .toSet()
        .toList();
    if (displayCurrencies.isEmpty) {
      displayCurrencies.add(
          activeCodes.contains(profile.defaultSaleInvoiceCurrency)
              ? profile.defaultSaleInvoiceCurrency
              : baseCurrency);
    }
    String defaultCurrency =
        activeCodes.contains(profile.defaultProductCurrency)
            ? profile.defaultProductCurrency
            : baseCurrency;
    String defaultSaleInvoiceCurrency =
        activeCodes.contains(profile.defaultSaleInvoiceCurrency)
            ? profile.defaultSaleInvoiceCurrency
            : defaultCurrency;
    String defaultSalePaymentCurrency =
        activeCodes.contains(profile.defaultSalePaymentCurrency)
            ? profile.defaultSalePaymentCurrency
            : defaultCurrency;
    int priceStorageDecimals = profile.priceStorageDecimals;

    final result = await showDialog<StoreProfile>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text(tr.text('financial_settings')),
            content: ResponsiveDialogBox(
              maxWidth: VentioResponsive.modalMaxWidth(context, 560),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: baseCurrency,
                      decoration:
                          InputDecoration(labelText: tr.text('base_currency')),
                      items: [
                        for (final code in activeCodes)
                          DropdownMenuItem(value: code, child: Text(code)),
                      ],
                      onChanged: (value) =>
                          setState(() => baseCurrency = value ?? baseCurrency),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      initialValue: priceStorageDecimals,
                      decoration: InputDecoration(
                          labelText: tr.text('price_storage_decimals')),
                      items: const [
                        DropdownMenuItem(value: 2, child: Text('2')),
                        DropdownMenuItem(value: 3, child: Text('3')),
                        DropdownMenuItem(value: 4, child: Text('4')),
                        DropdownMenuItem(value: 5, child: Text('5')),
                        DropdownMenuItem(value: 6, child: Text('6')),
                      ],
                      onChanged: (value) =>
                          setState(() => priceStorageDecimals = value ?? 4),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: displayMode,
                      decoration: InputDecoration(
                          labelText: tr.text('price_display_mode')),
                      items: [
                        DropdownMenuItem(
                            value: 'default',
                            child: Text(tr.text('price_display_default'))),
                        DropdownMenuItem(
                            value: 'selectable',
                            child: Text(tr.text('price_display_selectable'))),
                        DropdownMenuItem(
                            value: 'multiple',
                            child: Text(tr.text('price_display_multiple'))),
                      ],
                      onChanged: (value) =>
                          setState(() => displayMode = value ?? 'default'),
                    ),
                    if (displayMode == 'multiple') ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(tr.text('displayed_currencies')),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final code in activeCodes)
                            FilterChip(
                              label: Text(code),
                              selected: displayCurrencies.contains(code),
                              onSelected: (selected) {
                                setState(() {
                                  if (selected) {
                                    if (!displayCurrencies.contains(code)) {
                                      displayCurrencies.add(code);
                                    }
                                  } else if (displayCurrencies.length > 1) {
                                    displayCurrencies.remove(code);
                                  }
                                });
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          tr.text('displayed_currencies_hint'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: defaultCurrency,
                      decoration: InputDecoration(
                          labelText: tr.text('default_product_currency')),
                      items: [
                        for (final code in activeCodes)
                          DropdownMenuItem(value: code, child: Text(code)),
                      ],
                      onChanged: (value) => setState(
                          () => defaultCurrency = value ?? baseCurrency),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: defaultSaleInvoiceCurrency,
                      decoration: InputDecoration(
                          labelText: tr.text('default_sale_invoice_currency')),
                      items: [
                        for (final code in activeCodes)
                          DropdownMenuItem(value: code, child: Text(code)),
                      ],
                      onChanged: (value) => setState(() =>
                          defaultSaleInvoiceCurrency =
                              value ?? defaultCurrency),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: defaultSalePaymentCurrency,
                      decoration: InputDecoration(
                          labelText: tr.text('default_sale_payment_currency')),
                      items: [
                        for (final code in activeCodes)
                          DropdownMenuItem(value: code, child: Text(code)),
                      ],
                      onChanged: (value) => setState(() =>
                          defaultSalePaymentCurrency =
                              value ?? defaultCurrency),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(tr.text('cancel'))),
              FilledButton(
                onPressed: () {
                  final nextCurrencies = profile.currencies
                      .map((item) =>
                          item.copyWith(isBase: item.code == baseCurrency))
                      .toList(growable: false);
                  final nextDisplayCurrencies = displayMode == 'multiple'
                      ? displayCurrencies
                          .where((code) => activeCodes.contains(code))
                          .toSet()
                          .toList(growable: false)
                      : <String>[defaultSaleInvoiceCurrency];
                  Navigator.pop(
                    dialogContext,
                    profile.copyWith(
                      currency: baseCurrency,
                      baseCurrency: baseCurrency,
                      priceStorageDecimals: priceStorageDecimals,
                      currencies: nextCurrencies,
                      priceDisplayMode: displayMode,
                      priceDisplayCurrencies: nextDisplayCurrencies.isEmpty
                          ? <String>[defaultSaleInvoiceCurrency]
                          : nextDisplayCurrencies,
                      defaultProductCurrency: defaultCurrency,
                      defaultSaleInvoiceCurrency: defaultSaleInvoiceCurrency,
                      defaultSalePaymentCurrency: defaultSalePaymentCurrency,
                    ),
                  );
                },
                child: Text(tr.text('save')),
              ),
            ],
          ),
        );
      },
    );

    if (result != null) {
      await store.runtime.updateStoreProfile(result);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr.text('financial_settings_updated'))));
      }
    }
  }

  Future<void> _editCurrency(
    BuildContext context,
    StoreProfile profile, {
    FinancialCurrency? currency,
  }) async {
    final tr = AppLocalizations.of(context);
    final isEditing = currency != null;
    final codeController = TextEditingController(text: currency?.code ?? '');
    final nameController = TextEditingController(text: currency?.name ?? '');
    final symbolController =
        TextEditingController(text: currency?.symbol ?? '');
    final decimalsController =
        TextEditingController(text: (currency?.decimalPlaces ?? 2).toString());
    final cashDecimalsController = TextEditingController(
        text: (currency?.cashDecimalPlaces ?? currency?.decimalPlaces ?? 2)
            .toString());
    final roundingController = TextEditingController(
        text: (currency?.roundingStep ?? 0) <= 0
            ? ''
            : (currency?.roundingStep ?? 0).toStringAsFixed(0));
    bool cashRoundingEnabled = (currency?.roundingStep ?? 0) > 0;
    String roundingMethod = currency?.roundingMethod ?? 'nearest';
    bool isBase = currency?.isBase ?? false;
    bool isActive = currency?.isActive ?? true;

    final result = await showDialog<FinancialCurrency>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
              isEditing ? tr.text('edit_currency') : tr.text('add_currency')),
          content: ResponsiveDialogBox(
            maxWidth: VentioResponsive.modalMaxWidth(context, 520),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: codeController,
                    enabled: !isEditing,
                    decoration:
                        InputDecoration(labelText: tr.text('currency_code')),
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z]')),
                      LengthLimitingTextInputFormatter(3),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: nameController,
                    decoration:
                        InputDecoration(labelText: tr.text('currency_name')),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: symbolController,
                    decoration: InputDecoration(labelText: tr.text('symbol')),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: decimalsController,
                    decoration: InputDecoration(
                        labelText: tr.text('accounting_decimals')),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: cashDecimalsController,
                    decoration:
                        InputDecoration(labelText: tr.text('cash_decimals')),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr.text('enable_cash_rounding')),
                    subtitle: Text(tr.text('enable_cash_rounding_hint')),
                    value: cashRoundingEnabled,
                    onChanged: (value) =>
                        setState(() => cashRoundingEnabled = value),
                  ),
                  if (cashRoundingEnabled) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: roundingController,
                      decoration: InputDecoration(
                        labelText: tr.text('cash_rounding_increment'),
                        helperText: tr.text('cash_rounding_increment_hint'),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: roundingMethod,
                      decoration: InputDecoration(
                        labelText: tr.text('cash_rounding_method'),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'nearest',
                          child: Text(tr.text('cash_rounding_nearest')),
                        ),
                        DropdownMenuItem(
                          value: 'up',
                          child: Text(tr.text('cash_rounding_up')),
                        ),
                        DropdownMenuItem(
                          value: 'down',
                          child: Text(tr.text('cash_rounding_down')),
                        ),
                      ],
                      onChanged: (value) =>
                          setState(() => roundingMethod = value ?? 'nearest'),
                    ),
                  ],
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr.text('base_currency')),
                    value: isBase,
                    onChanged: (value) => setState(() => isBase = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr.text('active')),
                    value: isActive,
                    onChanged: (value) => setState(() => isActive = value),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(tr.text('cancel'))),
            FilledButton(
              onPressed: () {
                final code = codeController.text.trim().toUpperCase();
                if (code.length != 3) return;
                final decimals =
                    int.tryParse(decimalsController.text.trim()) ?? 2;
                final cashDecimals =
                    int.tryParse(cashDecimalsController.text.trim()) ??
                        decimals;
                final rounding = cashRoundingEnabled
                    ? (double.tryParse(roundingController.text.trim()) ?? 0.0)
                    : 0.0;
                Navigator.pop(
                  dialogContext,
                  FinancialCurrency(
                    code: code,
                    name: nameController.text.trim().isEmpty
                        ? code
                        : nameController.text.trim(),
                    symbol: symbolController.text.trim().isEmpty
                        ? code
                        : symbolController.text.trim(),
                    decimalPlaces: decimals.clamp(0, 6).toInt(),
                    cashDecimalPlaces: cashDecimals.clamp(0, 6).toInt(),
                    roundingStep: rounding < 0 ? 0.0 : rounding,
                    roundingMethod: roundingMethod,
                    isBase: isBase,
                    isActive: isActive,
                  ),
                );
              },
              child: Text(tr.text('save')),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;
    final code = result.code;
    final existing = profile.currencies.where((item) => item.code != code);
    final nextCurrencies = [
      ...existing,
      result,
    ];
    final nextBase = result.isBase ? result.code : profile.baseCurrency;
    final normalizedCurrencies = nextCurrencies
        .map((item) => item.copyWith(isBase: item.code == nextBase))
        .toList(growable: false);
    await store.runtime.updateStoreProfile(profile.copyWith(
      baseCurrency: nextBase,
      currency: nextBase,
      currencies: normalizedCurrencies,
      defaultProductCurrency:
          profile.defaultProductCurrency == code || result.isActive
              ? profile.defaultProductCurrency
              : nextBase,
    ));
  }

  Future<void> _editExchangeRate(
    BuildContext context,
    StoreProfile profile, {
    CurrencyExchangeRate? rate,
  }) async {
    final tr = AppLocalizations.of(context);
    final codes = profile.currencies
        .where((item) => item.isActive)
        .map((item) => item.code)
        .toList();
    String fromCurrency =
        rate?.fromCurrency ?? (codes.contains('USD') ? 'USD' : codes.first);
    String toCurrency =
        rate?.toCurrency ?? (codes.contains('LBP') ? 'LBP' : codes.last);
    final rateController =
        TextEditingController(text: rate?.rate.toString() ?? '');
    final noteController = TextEditingController(text: rate?.note ?? '');
    bool isActive = rate?.isActive ?? true;

    final result = await showDialog<CurrencyExchangeRate>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(rate == null
              ? tr.text('add_exchange_rate')
              : tr.text('edit_exchange_rate')),
          content: ResponsiveDialogBox(
            maxWidth: VentioResponsive.modalMaxWidth(context, 500),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: fromCurrency,
                    decoration:
                        InputDecoration(labelText: tr.text('from_currency')),
                    items: [
                      for (final code in codes)
                        DropdownMenuItem(value: code, child: Text(code)),
                    ],
                    onChanged: (value) =>
                        setState(() => fromCurrency = value ?? fromCurrency),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: toCurrency,
                    decoration:
                        InputDecoration(labelText: tr.text('to_currency')),
                    items: [
                      for (final code in codes)
                        DropdownMenuItem(value: code, child: Text(code)),
                    ],
                    onChanged: (value) =>
                        setState(() => toCurrency = value ?? toCurrency),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: rateController,
                    decoration:
                        InputDecoration(labelText: tr.text('exchange_rate')),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: noteController,
                    decoration: InputDecoration(labelText: tr.text('note')),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr.text('active')),
                    value: isActive,
                    onChanged: (value) => setState(() => isActive = value),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(tr.text('cancel'))),
            FilledButton(
              onPressed: () {
                final parsedRate =
                    double.tryParse(rateController.text.trim()) ?? 0;
                if (parsedRate <= 0 || fromCurrency == toCurrency) return;
                Navigator.pop(
                  dialogContext,
                  CurrencyExchangeRate(
                    id: rate?.id ??
                        'fx_${DateTime.now().microsecondsSinceEpoch}',
                    fromCurrency: fromCurrency,
                    toCurrency: toCurrency,
                    rate: parsedRate,
                    effectiveAt: rate?.effectiveAt ?? DateTime.now(),
                    source: 'manual',
                    isActive: isActive,
                    note: noteController.text.trim(),
                  ),
                );
              },
              child: Text(tr.text('save')),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;
    final nextRates = [
      ...profile.exchangeRates.where((item) => item.id != result.id),
      result,
    ];
    final legacyUsdLbp =
        result.fromCurrency == 'USD' && result.toCurrency == 'LBP'
            ? result.rate
            : profile.usdToLbpRate;
    await store.runtime.updateStoreProfile(profile.copyWith(
      exchangeRates: nextRates,
      usdToLbpRate: legacyUsdLbp,
    ));
  }

  Future<void> _editDocumentNumbering(
      BuildContext context, StoreProfile profile) async {
    final docs = profile.documentNumbering;
    final invoiceController = TextEditingController(text: docs.invoicePrefix);
    final quoteController = TextEditingController(text: docs.quotePrefix);
    final purchaseController = TextEditingController(text: docs.purchasePrefix);
    final deliveryController =
        TextEditingController(text: docs.deliveryNotePrefix);
    final returnController = TextEditingController(text: docs.returnPrefix);
    final tr = AppLocalizations.of(context);

    final result = await showDialog<DocumentNumberingSettings>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(tr.text('document_settings')),
          content: ResponsiveDialogBox(
            maxWidth: VentioResponsive.modalMaxWidth(context, 560),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: invoiceController,
                    decoration:
                        InputDecoration(labelText: tr.text('invoice_prefix')),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: quoteController,
                    decoration:
                        InputDecoration(labelText: tr.text('quote_prefix')),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: purchaseController,
                    decoration:
                        InputDecoration(labelText: tr.text('purchase_prefix')),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: deliveryController,
                    decoration: InputDecoration(
                        labelText: tr.text('delivery_note_prefix')),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: returnController,
                    decoration:
                        InputDecoration(labelText: tr.text('return_prefix')),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(tr.text('cancel'))),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  DocumentNumberingSettings(
                    invoicePrefix: invoiceController.text.trim().isEmpty
                        ? 'INV-'
                        : invoiceController.text.trim(),
                    quotePrefix: quoteController.text.trim().isEmpty
                        ? 'QUO-'
                        : quoteController.text.trim(),
                    purchasePrefix: purchaseController.text.trim().isEmpty
                        ? 'PO-'
                        : purchaseController.text.trim(),
                    deliveryNotePrefix: deliveryController.text.trim().isEmpty
                        ? 'DN-'
                        : deliveryController.text.trim(),
                    returnPrefix: returnController.text.trim().isEmpty
                        ? 'RET-'
                        : returnController.text.trim(),
                  ),
                );
              },
              child: Text(tr.text('save')),
            ),
          ],
        );
      },
    );

    if (result != null) {
      if (!context.mounted) return;
      await _saveOrganizationProfile(
          context, profile.copyWith(documentNumbering: result));
    }
  }
}
