
String _safeCurrencyRoundingMethod(String? value) {
  final method = (value ?? 'nearest').trim().toLowerCase();
  return const {'nearest', 'up', 'down'}.contains(method) ? method : 'nearest';
}

class FinancialCurrency {
  const FinancialCurrency({
    required this.code,
    required this.name,
    required this.symbol,
    required this.decimalPlaces,
    required this.cashDecimalPlaces,
    this.roundingStep = 0,
    this.roundingMethod = 'nearest',
    this.isBase = false,
    this.isActive = true,
  });

  final String code;
  final String name;
  final String symbol;
  /// Accounting precision for this currency.
  final int decimalPlaces;
  /// Physical/payment precision. Usually the same as [decimalPlaces], but can
  /// differ for cash-heavy currencies.
  final int cashDecimalPlaces;
  /// Optional cash rounding step in the currency minor unit. Example: for LBP
  /// cash rounding to 1,000, use 1000.
  final double roundingStep;
  /// Cash rounding method: nearest, up, or down. Used only when roundingStep > 0.
  final String roundingMethod;
  bool get cashRoundingEnabled => roundingStep > 0;
  final bool isBase;
  final bool isActive;

  FinancialCurrency copyWith({
    String? code,
    String? name,
    String? symbol,
    int? decimalPlaces,
    int? cashDecimalPlaces,
    double? roundingStep,
    String? roundingMethod,
    bool? isBase,
    bool? isActive,
  }) {
    return FinancialCurrency(
      code: (code ?? this.code).toUpperCase(),
      name: name ?? this.name,
      symbol: symbol ?? this.symbol,
      decimalPlaces: decimalPlaces ?? this.decimalPlaces,
      cashDecimalPlaces: cashDecimalPlaces ?? this.cashDecimalPlaces,
      roundingStep: roundingStep ?? this.roundingStep,
      roundingMethod: roundingMethod ?? this.roundingMethod,
      isBase: isBase ?? this.isBase,
      isActive: isActive ?? this.isActive,
    );
  }

  Map<String, dynamic> toJson() => {
        'code': code.toUpperCase(),
        'name': name,
        'symbol': symbol,
        'decimalPlaces': decimalPlaces,
        'cashDecimalPlaces': cashDecimalPlaces,
        'roundingStep': roundingStep,
        'roundingMethod': roundingMethod,
        'isBase': isBase,
        'isActive': isActive,
      };

  factory FinancialCurrency.fromJson(Map<String, dynamic> json) {
    final code = (json['code'] as String? ?? '').trim().toUpperCase();
    final safeCode = code.isEmpty ? 'USD' : code;
    final decimals = (json['decimalPlaces'] as num? ?? 2).toInt().clamp(0, 6).toInt();
    final cashDecimals =
        (json['cashDecimalPlaces'] as num? ?? decimals).toInt().clamp(0, 6).toInt();
    return FinancialCurrency(
      code: safeCode,
      name: (json['name'] as String? ?? safeCode).trim().isEmpty
          ? safeCode
          : (json['name'] as String? ?? safeCode).trim(),
      symbol: (json['symbol'] as String? ?? safeCode).trim().isEmpty
          ? safeCode
          : (json['symbol'] as String? ?? safeCode).trim(),
      decimalPlaces: decimals,
      cashDecimalPlaces: cashDecimals,
      roundingStep: (json['roundingStep'] as num? ?? 0).toDouble(),
      roundingMethod: _safeCurrencyRoundingMethod(json['roundingMethod'] as String?),
      isBase: json['isBase'] as bool? ?? false,
      isActive: json['isActive'] as bool? ?? true,
    );
  }
}

class CurrencyExchangeRate {
  const CurrencyExchangeRate({
    required this.id,
    required this.fromCurrency,
    required this.toCurrency,
    required this.rate,
    required this.effectiveAt,
    this.source = 'manual',
    this.isActive = true,
    this.note = '',
  });

  final String id;
  final String fromCurrency;
  final String toCurrency;
  final double rate;
  final DateTime effectiveAt;
  final String source;
  final bool isActive;
  final String note;

  CurrencyExchangeRate copyWith({
    String? id,
    String? fromCurrency,
    String? toCurrency,
    double? rate,
    DateTime? effectiveAt,
    String? source,
    bool? isActive,
    String? note,
  }) {
    return CurrencyExchangeRate(
      id: id ?? this.id,
      fromCurrency: (fromCurrency ?? this.fromCurrency).toUpperCase(),
      toCurrency: (toCurrency ?? this.toCurrency).toUpperCase(),
      rate: rate ?? this.rate,
      effectiveAt: effectiveAt ?? this.effectiveAt,
      source: source ?? this.source,
      isActive: isActive ?? this.isActive,
      note: note ?? this.note,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'fromCurrency': fromCurrency.toUpperCase(),
        'toCurrency': toCurrency.toUpperCase(),
        'rate': rate,
        'effectiveAt': effectiveAt.toIso8601String(),
        'source': source,
        'isActive': isActive,
        'note': note,
      };

  factory CurrencyExchangeRate.fromJson(Map<String, dynamic> json) {
    return CurrencyExchangeRate(
      id: json['id'] as String? ??
          'fx_${DateTime.now().microsecondsSinceEpoch}',
      fromCurrency:
          (json['fromCurrency'] as String? ?? 'USD').trim().toUpperCase(),
      toCurrency:
          (json['toCurrency'] as String? ?? 'LBP').trim().toUpperCase(),
      rate: (json['rate'] as num? ?? 1).toDouble(),
      effectiveAt: DateTime.tryParse(json['effectiveAt'] as String? ?? '') ??
          DateTime.now(),
      source: json['source'] as String? ?? 'manual',
      isActive: json['isActive'] as bool? ?? true,
      note: json['note'] as String? ?? '',
    );
  }
}

class StoreProfile {
  const StoreProfile({
    required this.name,
    required this.phone,
    required this.address,
    required this.currency,
    required this.footerNote,
    this.usdToLbpRate = 89500,
    this.priceDisplayMode = 'default',
    this.priceDisplayCurrencies = const <String>['USD'],
    this.defaultProductCurrency = 'USD',
    this.defaultSaleInvoiceCurrency = 'USD',
    this.defaultSalePaymentCurrency = 'USD',
    this.lbpRounding = 0,
    this.baseCurrency = 'USD',
    this.priceStorageDecimals = 4,
    this.currencies = StoreProfile.defaultCurrencies,
    this.exchangeRates = const <CurrencyExchangeRate>[],
    this.roundingDifferenceAccountId = '',
    this.exchangeGainAccountId = '',
    this.exchangeLossAccountId = '',
  });

  final String name;
  final String phone;
  final String address;
  /// Legacy display currency kept for backward compatibility with older backups.
  final String currency;
  final String footerNote;
  final double usdToLbpRate;
  /// Supported values: default, selectable, multiple. Legacy values usd/lbp/both are normalized on load.
  final String priceDisplayMode;
  /// Currencies shown when [priceDisplayMode] is multiple.
  final List<String> priceDisplayCurrencies;
  /// Preferred product entry currency.
  final String defaultProductCurrency;
  /// Preferred sales invoice currency.
  final String defaultSaleInvoiceCurrency;
  /// Preferred sales payment currency.
  final String defaultSalePaymentCurrency;
  /// Legacy LBP rounding step. Kept for compatibility; mirrored to LBP currency.
  final int lbpRounding;

  /// Company functional/base currency used by financial statements.
  final String baseCurrency;
  /// Product price storage precision. Accounting precision is per currency.
  final int priceStorageDecimals;
  final List<FinancialCurrency> currencies;
  final List<CurrencyExchangeRate> exchangeRates;
  final String roundingDifferenceAccountId;
  /// Account used when settlement creates a positive FX difference.
  final String exchangeGainAccountId;
  /// Account used when settlement creates a negative FX difference.
  final String exchangeLossAccountId;

  static const List<FinancialCurrency> defaultCurrencies = [
    FinancialCurrency(
      code: 'USD',
      name: 'US Dollar',
      symbol: r'$',
      decimalPlaces: 2,
      cashDecimalPlaces: 2,
      isBase: true,
    ),
    FinancialCurrency(
      code: 'LBP',
      name: 'Lebanese Pound',
      symbol: 'LBP',
      decimalPlaces: 0,
      cashDecimalPlaces: 0,
      roundingStep: 0,
    ),
  ];

  static const List<CurrencyExchangeRate> defaultExchangeRates =
      <CurrencyExchangeRate>[];

  FinancialCurrency currencyByCode(String code) {
    final normalized = code.trim().toUpperCase();
    return currencies.firstWhere(
      (item) => item.code.toUpperCase() == normalized,
      orElse: () => defaultCurrencies.first,
    );
  }

  CurrencyExchangeRate? exchangeRateForDate(String from, String to, {DateTime? effectiveAt}) {
    final cutoff = effectiveAt;
    final source = from.trim().toUpperCase();
    final target = to.trim().toUpperCase();
    if (source == target) {
      return CurrencyExchangeRate(
        id: 'same_${source}_$target',
        fromCurrency: source,
        toCurrency: target,
        rate: 1,
        effectiveAt: cutoff ?? DateTime.now(),
        source: 'system',
      );
    }

    List<CurrencyExchangeRate> filterRates(String rateFrom, String rateTo) {
      final rates = exchangeRates
          .where((rate) =>
              rate.isActive &&
              rate.fromCurrency.toUpperCase() == rateFrom &&
              rate.toCurrency.toUpperCase() == rateTo &&
              rate.rate > 0 &&
              (cutoff == null || !rate.effectiveAt.isAfter(cutoff)))
          .toList()
        ..sort((a, b) => b.effectiveAt.compareTo(a.effectiveAt));
      return rates;
    }

    final matches = filterRates(source, target);
    if (matches.isNotEmpty) return matches.first;
    final reverse = filterRates(target, source);
    if (reverse.isEmpty) return null;
    final latest = reverse.first;
    return latest.copyWith(
      id: 'reverse_${latest.id}',
      fromCurrency: source,
      toCurrency: target,
      rate: 1 / latest.rate,
      source: '${latest.source}_reverse',
    );
  }

  CurrencyExchangeRate? latestExchangeRate(String from, String to) {
    return exchangeRateForDate(from, to);
  }

  StoreProfile copyWith({
    String? name,
    String? phone,
    String? address,
    String? currency,
    String? footerNote,
    double? usdToLbpRate,
    String? priceDisplayMode,
    List<String>? priceDisplayCurrencies,
    String? defaultProductCurrency,
    String? defaultSaleInvoiceCurrency,
    String? defaultSalePaymentCurrency,
    int? lbpRounding,
    String? baseCurrency,
    int? priceStorageDecimals,
    List<FinancialCurrency>? currencies,
    List<CurrencyExchangeRate>? exchangeRates,
    String? roundingDifferenceAccountId,
    String? exchangeGainAccountId,
    String? exchangeLossAccountId,
  }) {
    final nextCurrencies = currencies ?? this.currencies;
    final nextBaseCurrency =
        (baseCurrency ?? this.baseCurrency).trim().toUpperCase();
    return StoreProfile(
      name: name ?? this.name,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      currency: currency ?? this.currency,
      footerNote: footerNote ?? this.footerNote,
      usdToLbpRate: usdToLbpRate ?? this.usdToLbpRate,
      priceDisplayMode: priceDisplayMode ?? this.priceDisplayMode,
      priceDisplayCurrencies: (priceDisplayCurrencies ?? this.priceDisplayCurrencies)
          .map((item) => item.trim().toUpperCase())
          .where((item) => item.isNotEmpty)
          .toSet()
          .toList(growable: false),
      defaultProductCurrency:
          (defaultProductCurrency ?? this.defaultProductCurrency).toUpperCase(),
      defaultSaleInvoiceCurrency:
          (defaultSaleInvoiceCurrency ?? this.defaultSaleInvoiceCurrency)
              .toUpperCase(),
      defaultSalePaymentCurrency:
          (defaultSalePaymentCurrency ?? this.defaultSalePaymentCurrency)
              .toUpperCase(),
      lbpRounding: lbpRounding ?? this.lbpRounding,
      baseCurrency: nextBaseCurrency,
      priceStorageDecimals:
          (priceStorageDecimals ?? this.priceStorageDecimals).clamp(0, 6).toInt(),
      currencies: nextCurrencies
          .map((item) => item.copyWith(isBase: item.code == nextBaseCurrency))
          .toList(growable: false),
      exchangeRates: exchangeRates ?? this.exchangeRates,
      roundingDifferenceAccountId:
          roundingDifferenceAccountId ?? this.roundingDifferenceAccountId,
      exchangeGainAccountId:
          exchangeGainAccountId ?? this.exchangeGainAccountId,
      exchangeLossAccountId:
          exchangeLossAccountId ?? this.exchangeLossAccountId,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'phone': phone,
        'address': address,
        'currency': currency,
        'footerNote': footerNote,
        'usdToLbpRate': usdToLbpRate,
        'priceDisplayMode': priceDisplayMode,
        'priceDisplayCurrencies': priceDisplayCurrencies,
        'defaultProductCurrency': defaultProductCurrency,
        'defaultSaleInvoiceCurrency': defaultSaleInvoiceCurrency,
        'defaultSalePaymentCurrency': defaultSalePaymentCurrency,
        'lbpRounding': lbpRounding,
        'baseCurrency': baseCurrency,
        'priceStorageDecimals': priceStorageDecimals,
        'currencies': currencies.map((item) => item.toJson()).toList(),
        'exchangeRates': exchangeRates.map((item) => item.toJson()).toList(),
        'roundingDifferenceAccountId': roundingDifferenceAccountId,
        'exchangeGainAccountId': exchangeGainAccountId,
        'exchangeLossAccountId': exchangeLossAccountId,
      };

  factory StoreProfile.fromJson(Map<String, dynamic> json) {
    final rawCurrencies = json['currencies'];
    var currencies = rawCurrencies is List
        ? rawCurrencies
            .whereType<Map>()
            .map((item) =>
                FinancialCurrency.fromJson(Map<String, dynamic>.from(item)))
            .toList()
        : <FinancialCurrency>[];

    final legacyRate = (json['usdToLbpRate'] as num? ?? 89500).toDouble();
    final rounding = (json['lbpRounding'] as num? ?? 0).toInt();
    final safeRounding = {0, 1000, 5000, 10000}.contains(rounding) ? rounding : 0;

    if (currencies.isEmpty) {
      currencies = defaultCurrencies
          .map((item) => item.code == 'LBP'
              ? item.copyWith(roundingStep: safeRounding.toDouble())
              : item)
          .toList();
    }
    for (final required in defaultCurrencies) {
      if (!currencies.any((item) => item.code == required.code)) {
        currencies.add(required);
      }
    }

    final rawRates = json['exchangeRates'];
    var exchangeRates = rawRates is List
        ? rawRates
            .whereType<Map>()
            .map((item) =>
                CurrencyExchangeRate.fromJson(Map<String, dynamic>.from(item)))
            .toList()
        : <CurrencyExchangeRate>[];
    if (!exchangeRates.any((item) =>
        item.fromCurrency == 'USD' && item.toCurrency == 'LBP')) {
      exchangeRates.add(CurrencyExchangeRate(
        id: 'legacy_usd_lbp',
        fromCurrency: 'USD',
        toCurrency: 'LBP',
        rate: legacyRate <= 0 ? 89500 : legacyRate,
        effectiveAt: DateTime.now(),
        source: 'legacy',
      ));
    }

    final displayModeRaw = (json['priceDisplayMode'] as String? ?? 'default').trim().toLowerCase();
    final displayMode = {'default', 'selectable', 'multiple'}.contains(displayModeRaw)
        ? displayModeRaw
        : displayModeRaw == 'both'
            ? 'multiple'
            : 'default';
    final baseCurrencyRaw =
        (json['baseCurrency'] as String? ?? json['currency'] as String? ?? 'USD')
            .toUpperCase();
    final baseCurrency = currencies.any((item) => item.code == baseCurrencyRaw)
        ? baseCurrencyRaw
        : 'USD';
    currencies = currencies
        .map((item) => item.copyWith(isBase: item.code == baseCurrency))
        .toList(growable: false);

    String normalizeKnownCurrency(String? value, [String fallback = 'USD']) {
      final normalized = (value ?? fallback).trim().toUpperCase();
      return currencies.any((item) => item.code == normalized)
          ? normalized
          : fallback;
    }

    final defaultCurrency = normalizeKnownCurrency(
      json['defaultProductCurrency'] as String? ?? json['currency'] as String?,
      'USD',
    );
    final defaultSaleInvoiceCurrency = normalizeKnownCurrency(
      json['defaultSaleInvoiceCurrency'] as String?,
      defaultCurrency,
    );
    final defaultSalePaymentCurrency = normalizeKnownCurrency(
      json['defaultSalePaymentCurrency'] as String?,
      defaultCurrency,
    );

    final rawDisplayCurrencies = json['priceDisplayCurrencies'];
    List<String> displayCurrencies;
    if (rawDisplayCurrencies is List) {
      displayCurrencies = rawDisplayCurrencies
          .whereType<String>()
          .map((item) => item.trim().toUpperCase())
          .where((item) => currencies.any((currency) => currency.code == item))
          .toSet()
          .toList(growable: false);
    } else if (displayModeRaw == 'both') {
      displayCurrencies = ['USD', 'LBP']
          .where((item) => currencies.any((currency) => currency.code == item))
          .toList(growable: false);
    } else if (displayModeRaw == 'lbp') {
      displayCurrencies = ['LBP']
          .where((item) => currencies.any((currency) => currency.code == item))
          .toList(growable: false);
    } else {
      displayCurrencies = [defaultSaleInvoiceCurrency];
    }
    if (displayCurrencies.isEmpty) {
      displayCurrencies = [defaultSaleInvoiceCurrency];
    }
    final legacyCurrency = normalizeKnownCurrency(
      json['currency'] as String?,
      baseCurrency,
    );

    return StoreProfile(
      name: json['name'] as String? ?? 'Ventio',
      phone: json['phone'] as String? ?? '',
      address: json['address'] as String? ?? '',
      currency: legacyCurrency,
      footerNote: json['footerNote'] as String? ?? 'Thank you for shopping with us.',
      usdToLbpRate: legacyRate <= 0 ? 89500 : legacyRate,
      priceDisplayMode: displayMode,
      priceDisplayCurrencies: displayCurrencies,
      defaultProductCurrency: defaultCurrency,
      defaultSaleInvoiceCurrency: defaultSaleInvoiceCurrency,
      defaultSalePaymentCurrency: defaultSalePaymentCurrency,
      lbpRounding: safeRounding,
      baseCurrency: baseCurrency,
      priceStorageDecimals:
          (json['priceStorageDecimals'] as num? ?? 4).toInt().clamp(0, 6).toInt(),
      currencies: currencies,
      exchangeRates: exchangeRates,
      roundingDifferenceAccountId:
          json['roundingDifferenceAccountId'] as String? ?? '',
      exchangeGainAccountId: json['exchangeGainAccountId'] as String? ?? '',
      exchangeLossAccountId: json['exchangeLossAccountId'] as String? ?? '',
    );
  }

  static const defaults = StoreProfile(
    name: 'Ventio',
    phone: '',
    address: '',
    currency: 'USD',
    footerNote: 'Thank you for shopping with us.',
    usdToLbpRate: 89500,
    priceDisplayMode: 'default',
    priceDisplayCurrencies: ['USD'],
    defaultProductCurrency: 'USD',
    defaultSaleInvoiceCurrency: 'USD',
    defaultSalePaymentCurrency: 'USD',
    lbpRounding: 0,
    baseCurrency: 'USD',
    priceStorageDecimals: 4,
    currencies: defaultCurrencies,
    exchangeRates: defaultExchangeRates,
    exchangeGainAccountId: '',
    exchangeLossAccountId: '',
  );
}
