part of 'store_profile.dart';

class StoreProfile {
  const StoreProfile({
    required this.name,
    required this.phone,
    required this.address,
    required this.currency,
    required this.footerNote,
    this.legalName = '',
    this.tradeName = '',
    this.email = '',
    this.website = '',
    this.logoPath = '',
    this.logoDataBase64 = '',
    this.logoAssetId = '',
    this.historicalLogoAssetsBase64 = const <String, String>{},
    this.logoFileName = '',
    this.logoMimeType = '',
    this.vatNumber = '',
    this.taxRegistrationNumber = '',
    this.commercialRegisterNumber = '',
    this.country = '',
    this.governorate = '',
    this.city = '',
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
    this.documentNumbering = const DocumentNumberingSettings(),
    this.branches = const <OrganizationBranch>[],
    this.printSettings = const PrintSettings(),
    this.allowNegativeStock = false,
    this.allowNegativeCashBalance = false,
    this.taxProfiles = TaxProfile.defaults,
    this.defaultTaxProfileId = TaxProfile.standardId,
    this.taxConfigurationVersion = 0,
  });

  final String name;
  final String phone;
  final String address;
  final String legalName;
  final String tradeName;
  final String email;
  final String website;

  /// Legacy local file path retained only for backward compatibility.
  final String logoPath;

  /// Logo contents persisted inside the SQLite-backed store profile.
  final String logoDataBase64;

  /// Stable content-addressed id for the current logo. Posted documents freeze
  /// only this lightweight id instead of duplicating the base64 image.
  final String logoAssetId;

  /// Historical logo payloads keyed by [logoAssetId]. The current logo stays in
  /// [logoDataBase64], so each unique logo is persisted only once in the store
  /// profile while old posted documents can still render their original logo.
  final Map<String, String> historicalLogoAssetsBase64;

  final String logoFileName;
  final String logoMimeType;
  final String vatNumber;
  final String taxRegistrationNumber;
  final String commercialRegisterNumber;
  final String country;
  final String governorate;
  final String city;

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
  final DocumentNumberingSettings documentNumbering;
  final List<OrganizationBranch> branches;
  final PrintSettings printSettings;

  /// Whether stock-out movements may take a tracked product below zero.
  final bool allowNegativeStock;

  /// Whether cash outflows may take a cash location below zero.
  final bool allowNegativeCashBalance;

  /// Store-level tax profiles. Product rows reference these by id. Prices in
  /// Ventio are tax-inclusive, so standard VAT is extracted from the charged
  /// amount while zero-rated/exempt profiles keep tax at zero.
  final List<TaxProfile> taxProfiles;
  final String defaultTaxProfileId;

  /// 0 means legacy/default VAT compatibility has not been explicitly
  /// migrated into tax profiles yet. Phase 2 writes version 1.
  final int taxConfigurationVersion;

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

  CurrencyExchangeRate? exchangeRateForDate(String from, String to,
      {DateTime? effectiveAt}) {
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

  TaxProfile taxProfileById(String? id, {double? legacyDefaultRatePercent}) {
    final normalized = (id ?? '').trim();
    TaxProfile? found;
    for (final profile in taxProfiles) {
      if (profile.id == normalized && profile.isActive) {
        found = profile;
        break;
      }
    }
    if (found == null) {
      for (final profile in taxProfiles) {
        if (profile.id == defaultTaxProfileId && profile.isActive) {
          found = profile;
          break;
        }
      }
    }
    if (found == null) {
      for (final profile in taxProfiles) {
        if (profile.isActive) {
          found = profile;
          break;
        }
      }
    }
    found ??= TaxProfile.standardZero;
    if (taxConfigurationVersion <= 0 &&
        found.id == TaxProfile.standardId &&
        legacyDefaultRatePercent != null &&
        legacyDefaultRatePercent.isFinite &&
        legacyDefaultRatePercent > 0) {
      return found.copyWith(
        ratePercent: legacyDefaultRatePercent.clamp(0, 100).toDouble(),
      );
    }
    return found;
  }

  List<TaxProfile> get activeTaxProfiles =>
      taxProfiles.where((item) => item.isActive).toList(growable: false);

  StoreProfile copyWith({
    String? name,
    String? phone,
    String? address,
    String? legalName,
    String? tradeName,
    String? email,
    String? website,
    String? logoPath,
    String? logoDataBase64,
    String? logoAssetId,
    Map<String, String>? historicalLogoAssetsBase64,
    String? logoFileName,
    String? logoMimeType,
    String? vatNumber,
    String? taxRegistrationNumber,
    String? commercialRegisterNumber,
    String? country,
    String? governorate,
    String? city,
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
    DocumentNumberingSettings? documentNumbering,
    List<OrganizationBranch>? branches,
    PrintSettings? printSettings,
    bool? allowNegativeStock,
    bool? allowNegativeCashBalance,
    List<TaxProfile>? taxProfiles,
    String? defaultTaxProfileId,
    int? taxConfigurationVersion,
  }) {
    final nextCurrencies = currencies ?? this.currencies;
    final nextBaseCurrency =
        (baseCurrency ?? this.baseCurrency).trim().toUpperCase();

    final nextHistoricalLogoAssets = <String, String>{
      ...this.historicalLogoAssetsBase64,
      ...?historicalLogoAssetsBase64,
    };
    final logoWasExplicitlyChanged =
        logoDataBase64 != null && logoDataBase64 != this.logoDataBase64;
    final nextLogoData = logoDataBase64 ?? this.logoDataBase64;
    var nextLogoAssetId = logoAssetId ?? this.logoAssetId;
    if (logoWasExplicitlyChanged) {
      final currentAssetId = this.logoAssetId.isNotEmpty
          ? this.logoAssetId
          : logoAssetIdForData(this.logoDataBase64);
      if (this.logoDataBase64.isNotEmpty && currentAssetId.isNotEmpty) {
        nextHistoricalLogoAssets[currentAssetId] = this.logoDataBase64;
      }
      nextLogoAssetId =
          nextLogoData.isEmpty ? '' : logoAssetIdForData(nextLogoData);
    } else if (nextLogoData.isNotEmpty && nextLogoAssetId.isEmpty) {
      nextLogoAssetId = logoAssetIdForData(nextLogoData);
    }
    if (nextLogoAssetId.isNotEmpty) {
      // The active logo lives in logoDataBase64, never duplicate it in history.
      nextHistoricalLogoAssets.remove(nextLogoAssetId);
    }

    return StoreProfile(
      name: name ?? this.name,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      legalName: legalName ?? this.legalName,
      tradeName: tradeName ?? this.tradeName,
      email: email ?? this.email,
      website: website ?? this.website,
      logoPath: logoPath ?? this.logoPath,
      logoDataBase64: nextLogoData,
      logoAssetId: nextLogoAssetId,
      historicalLogoAssetsBase64:
          Map<String, String>.unmodifiable(nextHistoricalLogoAssets),
      logoFileName: logoFileName ?? this.logoFileName,
      logoMimeType: logoMimeType ?? this.logoMimeType,
      vatNumber: vatNumber ?? this.vatNumber,
      taxRegistrationNumber:
          taxRegistrationNumber ?? this.taxRegistrationNumber,
      commercialRegisterNumber:
          commercialRegisterNumber ?? this.commercialRegisterNumber,
      country: country ?? this.country,
      governorate: governorate ?? this.governorate,
      city: city ?? this.city,
      currency: currency ?? this.currency,
      footerNote: footerNote ?? this.footerNote,
      usdToLbpRate: usdToLbpRate ?? this.usdToLbpRate,
      priceDisplayMode: priceDisplayMode ?? this.priceDisplayMode,
      priceDisplayCurrencies:
          (priceDisplayCurrencies ?? this.priceDisplayCurrencies)
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
      priceStorageDecimals: (priceStorageDecimals ?? this.priceStorageDecimals)
          .clamp(0, 6)
          .toInt(),
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
      documentNumbering: documentNumbering ?? this.documentNumbering,
      branches: branches ?? this.branches,
      printSettings: printSettings ?? this.printSettings,
      allowNegativeStock: allowNegativeStock ?? this.allowNegativeStock,
      allowNegativeCashBalance:
          allowNegativeCashBalance ?? this.allowNegativeCashBalance,
      taxProfiles: taxProfiles ?? this.taxProfiles,
      defaultTaxProfileId: defaultTaxProfileId ?? this.defaultTaxProfileId,
      taxConfigurationVersion:
          taxConfigurationVersion ?? this.taxConfigurationVersion,
    );
  }

  /// Returns a deterministic content-addressed id for a logo payload.
  static String logoAssetIdForData(String rawBase64) {
    final normalized = rawBase64.trim();
    if (normalized.isEmpty) return '';
    try {
      final bytes = base64Decode(base64.normalize(normalized));
      return 'logo_${sha256.convert(bytes)}';
    } catch (_) {
      // Preserve compatibility with malformed legacy payloads while still
      // producing a stable id that can be referenced by historical snapshots.
      return 'logo_${sha256.convert(utf8.encode(normalized))}';
    }
  }

  String logoDataForAsset(String assetId) {
    final normalized = assetId.trim();
    if (normalized.isEmpty) return '';
    final currentAssetId = logoAssetId.isNotEmpty
        ? logoAssetId
        : logoAssetIdForData(logoDataBase64);
    if (normalized == currentAssetId && logoDataBase64.isNotEmpty) {
      return logoDataBase64;
    }
    return historicalLogoAssetsBase64[normalized] ?? '';
  }

  /// Keeps historical logo assets when a profile arrives from settings, sync,
  /// or another replacement path. This prevents an old posted document from
  /// losing access to the exact logo it froze by content id.
  StoreProfile withMergedLogoAssetsFrom(StoreProfile source) {
    final merged = <String, String>{
      ...source.historicalLogoAssetsBase64,
      ...historicalLogoAssetsBase64,
    };
    final sourceAssetId = source.logoAssetId.isNotEmpty
        ? source.logoAssetId
        : logoAssetIdForData(source.logoDataBase64);
    if (source.logoDataBase64.isNotEmpty &&
        sourceAssetId.isNotEmpty &&
        sourceAssetId != logoAssetId) {
      merged[sourceAssetId] = source.logoDataBase64;
    }
    if (logoAssetId.isNotEmpty) merged.remove(logoAssetId);
    return copyWith(
      logoAssetId: logoAssetId,
      historicalLogoAssetsBase64: merged,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'phone': phone,
        'address': address,
        'legalName': legalName,
        'tradeName': tradeName,
        'email': email,
        'website': website,
        'logoPath': logoPath,
        'logoDataBase64': logoDataBase64,
        'logoAssetId': logoAssetId,
        'historicalLogoAssetsBase64': historicalLogoAssetsBase64,
        'logoFileName': logoFileName,
        'logoMimeType': logoMimeType,
        'vatNumber': vatNumber,
        'taxRegistrationNumber': taxRegistrationNumber,
        'commercialRegisterNumber': commercialRegisterNumber,
        'country': country,
        'governorate': governorate,
        'city': city,
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
        'documentNumbering': documentNumbering.toJson(),
        'branches': branches.map((item) => item.toJson()).toList(),
        'printSettings': printSettings.toJson(),
        'allowNegativeStock': allowNegativeStock,
        'allowNegativeCashBalance': allowNegativeCashBalance,
        'taxProfiles': taxProfiles.map((item) => item.toJson()).toList(),
        'defaultTaxProfileId': defaultTaxProfileId,
        'taxConfigurationVersion': taxConfigurationVersion,
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
    final safeRounding =
        {0, 1000, 5000, 10000}.contains(rounding) ? rounding : 0;

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
    if (!exchangeRates.any(
        (item) => item.fromCurrency == 'USD' && item.toCurrency == 'LBP')) {
      exchangeRates.add(CurrencyExchangeRate(
        id: 'legacy_usd_lbp',
        fromCurrency: 'USD',
        toCurrency: 'LBP',
        rate: legacyRate <= 0 ? 89500 : legacyRate,
        effectiveAt: DateTime.now(),
        source: 'legacy',
      ));
    }

    final displayModeRaw =
        (json['priceDisplayMode'] as String? ?? 'default').trim().toLowerCase();
    final displayMode =
        {'default', 'selectable', 'multiple'}.contains(displayModeRaw)
            ? displayModeRaw
            : displayModeRaw == 'both'
                ? 'multiple'
                : 'default';
    final baseCurrencyRaw = (json['baseCurrency'] as String? ??
            json['currency'] as String? ??
            'USD')
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

    final rawTaxProfiles = json['taxProfiles'];
    var taxProfiles = rawTaxProfiles is List
        ? rawTaxProfiles
            .whereType<Map>()
            .map((item) => TaxProfile.fromJson(Map<String, dynamic>.from(item)))
            .where((item) => item.id.trim().isNotEmpty)
            .toList(growable: false)
        : <TaxProfile>[];
    if (taxProfiles.isEmpty) taxProfiles = TaxProfile.defaults;
    final rawDefaultTaxProfileId =
        json['defaultTaxProfileId']?.toString().trim() ?? '';
    final defaultTaxProfileId = taxProfiles.any(
      (item) => item.id == rawDefaultTaxProfileId && item.isActive,
    )
        ? rawDefaultTaxProfileId
        : (taxProfiles.any((item) => item.id == TaxProfile.standardId)
            ? TaxProfile.standardId
            : taxProfiles.first.id);
    final taxConfigurationVersion =
        (json['taxConfigurationVersion'] as num? ?? 0)
            .toInt()
            .clamp(0, 1)
            .toInt();

    final logoDataBase64 = json['logoDataBase64'] as String? ?? '';
    final rawLogoAssetId = json['logoAssetId']?.toString().trim() ?? '';
    final logoAssetId = logoDataBase64.isNotEmpty
        ? StoreProfile.logoAssetIdForData(logoDataBase64)
        : rawLogoAssetId;
    final historicalLogoAssetsBase64 = <String, String>{};
    final rawHistoricalLogoAssets = json['historicalLogoAssetsBase64'];
    if (rawHistoricalLogoAssets is Map) {
      for (final entry in rawHistoricalLogoAssets.entries) {
        final id = entry.key.toString().trim();
        final data = entry.value?.toString() ?? '';
        if (id.isNotEmpty && data.isNotEmpty) {
          historicalLogoAssetsBase64[id] = data;
        }
      }
    }
    if (logoAssetId.isNotEmpty) {
      historicalLogoAssetsBase64.remove(logoAssetId);
    }

    return StoreProfile(
      name: json['name'] as String? ?? 'Ventio',
      phone: json['phone'] as String? ?? '',
      address: json['address'] as String? ?? '',
      legalName: json['legalName'] as String? ?? '',
      tradeName: json['tradeName'] as String? ?? '',
      email: json['email'] as String? ?? '',
      website: json['website'] as String? ?? '',
      logoPath: json['logoPath'] as String? ?? '',
      logoDataBase64: logoDataBase64,
      logoAssetId: logoAssetId,
      historicalLogoAssetsBase64:
          Map<String, String>.unmodifiable(historicalLogoAssetsBase64),
      logoFileName: json['logoFileName'] as String? ?? '',
      logoMimeType: json['logoMimeType'] as String? ?? '',
      vatNumber: json['vatNumber'] as String? ?? '',
      taxRegistrationNumber: json['taxRegistrationNumber'] as String? ?? '',
      commercialRegisterNumber:
          json['commercialRegisterNumber'] as String? ?? '',
      country: json['country'] as String? ?? '',
      governorate: json['governorate'] as String? ?? '',
      city: json['city'] as String? ?? '',
      currency: legacyCurrency,
      footerNote:
          json['footerNote'] as String? ?? 'Thank you for shopping with us.',
      usdToLbpRate: legacyRate <= 0 ? 89500 : legacyRate,
      priceDisplayMode: displayMode,
      priceDisplayCurrencies: displayCurrencies,
      defaultProductCurrency: defaultCurrency,
      defaultSaleInvoiceCurrency: defaultSaleInvoiceCurrency,
      defaultSalePaymentCurrency: defaultSalePaymentCurrency,
      lbpRounding: safeRounding,
      baseCurrency: baseCurrency,
      priceStorageDecimals: (json['priceStorageDecimals'] as num? ?? 4)
          .toInt()
          .clamp(0, 6)
          .toInt(),
      currencies: currencies,
      exchangeRates: exchangeRates,
      roundingDifferenceAccountId:
          json['roundingDifferenceAccountId'] as String? ?? '',
      exchangeGainAccountId: json['exchangeGainAccountId'] as String? ?? '',
      exchangeLossAccountId: json['exchangeLossAccountId'] as String? ?? '',
      documentNumbering: json['documentNumbering'] is Map
          ? DocumentNumberingSettings.fromJson(
              Map<String, dynamic>.from(json['documentNumbering'] as Map))
          : const DocumentNumberingSettings(),
      branches: json['branches'] is List
          ? (json['branches'] as List)
              .whereType<Map>()
              .map((item) =>
                  OrganizationBranch.fromJson(Map<String, dynamic>.from(item)))
              .where((item) => item.name.trim().isNotEmpty)
              .toList(growable: false)
          : const <OrganizationBranch>[],
      printSettings: json['printSettings'] is Map
          ? PrintSettings.fromJson(
              Map<String, dynamic>.from(json['printSettings'] as Map))
          : const PrintSettings(),
      allowNegativeStock: json['allowNegativeStock'] == true,
      allowNegativeCashBalance: json['allowNegativeCashBalance'] == true,
      taxProfiles: taxProfiles,
      defaultTaxProfileId: defaultTaxProfileId,
      taxConfigurationVersion: taxConfigurationVersion,
    );
  }

  static const defaults = StoreProfile(
    name: 'Ventio',
    phone: '',
    address: '',
    legalName: '',
    tradeName: '',
    email: '',
    website: '',
    logoPath: '',
    logoDataBase64: '',
    logoFileName: '',
    logoMimeType: '',
    vatNumber: '',
    taxRegistrationNumber: '',
    commercialRegisterNumber: '',
    country: '',
    governorate: '',
    city: '',
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
    documentNumbering: DocumentNumberingSettings(),
    branches: <OrganizationBranch>[],
    printSettings: PrintSettings(),
    allowNegativeStock: false,
    allowNegativeCashBalance: false,
    taxProfiles: TaxProfile.defaults,
    defaultTaxProfileId: TaxProfile.standardId,
    taxConfigurationVersion: 0,
  );
}
