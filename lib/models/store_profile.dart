class StoreProfile {
  const StoreProfile({
    required this.name,
    required this.phone,
    required this.address,
    required this.currency,
    required this.footerNote,
    this.usdToLbpRate = 89500,
    this.priceDisplayMode = 'usd',
    this.defaultProductCurrency = 'USD',
    this.lbpRounding = 0,
  });

  final String name;
  final String phone;
  final String address;
  /// Legacy display currency kept for backward compatibility with older backups.
  final String currency;
  final String footerNote;
  final double usdToLbpRate;
  /// Supported values: usd, lbp, both.
  final String priceDisplayMode;
  /// Supported values: USD, LBP.
  final String defaultProductCurrency;
  /// LBP rounding step. 0 means no rounding.
  final int lbpRounding;

  StoreProfile copyWith({
    String? name,
    String? phone,
    String? address,
    String? currency,
    String? footerNote,
    double? usdToLbpRate,
    String? priceDisplayMode,
    String? defaultProductCurrency,
    int? lbpRounding,
  }) {
    return StoreProfile(
      name: name ?? this.name,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      currency: currency ?? this.currency,
      footerNote: footerNote ?? this.footerNote,
      usdToLbpRate: usdToLbpRate ?? this.usdToLbpRate,
      priceDisplayMode: priceDisplayMode ?? this.priceDisplayMode,
      defaultProductCurrency: defaultProductCurrency ?? this.defaultProductCurrency,
      lbpRounding: lbpRounding ?? this.lbpRounding,
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
        'defaultProductCurrency': defaultProductCurrency,
        'lbpRounding': lbpRounding,
      };

  factory StoreProfile.fromJson(Map<String, dynamic> json) {
    final displayModeRaw = json['priceDisplayMode'] as String? ?? 'usd';
    final displayMode = {'usd', 'lbp', 'both'}.contains(displayModeRaw) ? displayModeRaw : 'usd';
    final defaultCurrencyRaw = (json['defaultProductCurrency'] as String? ?? json['currency'] as String? ?? 'USD').toUpperCase();
    final defaultCurrency = defaultCurrencyRaw == 'LBP' ? 'LBP' : 'USD';
    final rounding = (json['lbpRounding'] as num? ?? 0).toInt();
    final safeRounding = {0, 1000, 5000, 10000}.contains(rounding) ? rounding : 0;
    final legacyCurrencyRaw = (json['currency'] as String? ?? defaultCurrency).toUpperCase();
    final legacyCurrency = legacyCurrencyRaw == 'LBP' ? 'LBP' : 'USD';

    return StoreProfile(
      name: json['name'] as String? ?? 'Ventio',
      phone: json['phone'] as String? ?? '',
      address: json['address'] as String? ?? '',
      currency: legacyCurrency,
      footerNote: json['footerNote'] as String? ?? 'Thank you for shopping with us.',
      usdToLbpRate: (json['usdToLbpRate'] as num? ?? 89500).toDouble(),
      priceDisplayMode: displayMode,
      defaultProductCurrency: defaultCurrency,
      lbpRounding: safeRounding,
    );
  }

  static const defaults = StoreProfile(
    name: 'Ventio',
    phone: '',
    address: '',
    currency: 'USD',
    footerNote: 'Thank you for shopping with us.',
    usdToLbpRate: 89500,
    priceDisplayMode: 'usd',
    defaultProductCurrency: 'USD',
    lbpRounding: 0,
  );
}
