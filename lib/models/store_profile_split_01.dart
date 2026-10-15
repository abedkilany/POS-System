part of 'store_profile.dart';

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
    final decimals =
        (json['decimalPlaces'] as num? ?? 2).toInt().clamp(0, 6).toInt();
    final cashDecimals = (json['cashDecimalPlaces'] as num? ?? decimals)
        .toInt()
        .clamp(0, 6)
        .toInt();
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
      roundingMethod:
          _safeCurrencyRoundingMethod(json['roundingMethod'] as String?),
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
      toCurrency: (json['toCurrency'] as String? ?? 'LBP').trim().toUpperCase(),
      rate: (json['rate'] as num? ?? 1).toDouble(),
      effectiveAt: DateTime.tryParse(json['effectiveAt'] as String? ?? '') ??
          DateTime.now(),
      source: json['source'] as String? ?? 'manual',
      isActive: json['isActive'] as bool? ?? true,
      note: json['note'] as String? ?? '',
    );
  }
}

class DocumentNumberingSettings {
  const DocumentNumberingSettings({
    this.invoicePrefix = 'INV-',
    this.quotePrefix = 'QUO-',
    this.purchasePrefix = 'PO-',
    this.deliveryNotePrefix = 'DN-',
    this.returnPrefix = 'RET-',
  });

  final String invoicePrefix;
  final String quotePrefix;
  final String purchasePrefix;
  final String deliveryNotePrefix;
  final String returnPrefix;

  DocumentNumberingSettings copyWith({
    String? invoicePrefix,
    String? quotePrefix,
    String? purchasePrefix,
    String? deliveryNotePrefix,
    String? returnPrefix,
  }) {
    return DocumentNumberingSettings(
      invoicePrefix: invoicePrefix ?? this.invoicePrefix,
      quotePrefix: quotePrefix ?? this.quotePrefix,
      purchasePrefix: purchasePrefix ?? this.purchasePrefix,
      deliveryNotePrefix: deliveryNotePrefix ?? this.deliveryNotePrefix,
      returnPrefix: returnPrefix ?? this.returnPrefix,
    );
  }

  Map<String, dynamic> toJson() => {
        'invoicePrefix': invoicePrefix,
        'quotePrefix': quotePrefix,
        'purchasePrefix': purchasePrefix,
        'deliveryNotePrefix': deliveryNotePrefix,
        'returnPrefix': returnPrefix,
      };

  factory DocumentNumberingSettings.fromJson(Map<String, dynamic> json) {
    return DocumentNumberingSettings(
      invoicePrefix: json['invoicePrefix'] as String? ?? 'INV-',
      quotePrefix: json['quotePrefix'] as String? ?? 'QUO-',
      purchasePrefix: json['purchasePrefix'] as String? ?? 'PO-',
      deliveryNotePrefix: json['deliveryNotePrefix'] as String? ?? 'DN-',
      returnPrefix: json['returnPrefix'] as String? ?? 'RET-',
    );
  }
}

class OrganizationBranch {
  const OrganizationBranch({
    required this.id,
    required this.name,
    this.code = '',
    this.address = '',
    this.phone = '',
    this.isActive = true,
  });

  final String id;
  final String name;
  final String code;
  final String address;
  final String phone;
  final bool isActive;

  OrganizationBranch copyWith({
    String? id,
    String? name,
    String? code,
    String? address,
    String? phone,
    bool? isActive,
  }) {
    return OrganizationBranch(
      id: id ?? this.id,
      name: name ?? this.name,
      code: code ?? this.code,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      isActive: isActive ?? this.isActive,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'code': code,
        'address': address,
        'phone': phone,
        'isActive': isActive,
      };

  factory OrganizationBranch.fromJson(Map<String, dynamic> json) {
    return OrganizationBranch(
      id: json['id'] as String? ??
          'branch_${DateTime.now().microsecondsSinceEpoch}',
      name: json['name'] as String? ?? '',
      code: json['code'] as String? ?? '',
      address: json['address'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      isActive: json['isActive'] as bool? ?? true,
    );
  }
}
