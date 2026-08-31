enum TaxTreatment { standard, zeroRated, exempt, outOfScope }

extension TaxTreatmentCode on TaxTreatment {
  String get code => switch (this) {
        TaxTreatment.standard => 'standard',
        TaxTreatment.zeroRated => 'zero_rated',
        TaxTreatment.exempt => 'exempt',
        TaxTreatment.outOfScope => 'out_of_scope',
      };

  static TaxTreatment fromCode(String? value) {
    final normalized = value?.trim().toLowerCase() ?? '';
    if (normalized == 'zero_rated' ||
        normalized == 'zero-rated' ||
        normalized == 'zero') {
      return TaxTreatment.zeroRated;
    }
    if (normalized == 'exempt') return TaxTreatment.exempt;
    if (normalized == 'out_of_scope' ||
        normalized == 'out-of-scope' ||
        normalized == 'outside_scope') {
      return TaxTreatment.outOfScope;
    }
    return TaxTreatment.standard;
  }
}

class TaxProfile {
  const TaxProfile({
    required this.id,
    required this.code,
    required this.name,
    required this.ratePercent,
    this.treatment = TaxTreatment.standard,
    this.isActive = true,
  });

  static const String standardId = 'tax_standard';
  static const String zeroRatedId = 'tax_zero_rated';
  static const String exemptId = 'tax_exempt';

  static const TaxProfile standardZero = TaxProfile(
    id: standardId,
    code: 'VAT',
    name: 'Standard VAT',
    ratePercent: 0,
  );

  static const TaxProfile zeroRated = TaxProfile(
    id: zeroRatedId,
    code: 'VAT-ZR',
    name: 'Zero-rated',
    ratePercent: 0,
    treatment: TaxTreatment.zeroRated,
  );

  static const TaxProfile exempt = TaxProfile(
    id: exemptId,
    code: 'VAT-EX',
    name: 'Exempt',
    ratePercent: 0,
    treatment: TaxTreatment.exempt,
  );

  static const List<TaxProfile> defaults = <TaxProfile>[
    standardZero,
    zeroRated,
    exempt,
  ];

  final String id;
  final String code;
  final String name;
  final double ratePercent;
  final TaxTreatment treatment;
  final bool isActive;

  bool get appliesVat =>
      isActive && treatment == TaxTreatment.standard && ratePercent > 0;

  TaxProfile copyWith({
    String? id,
    String? code,
    String? name,
    double? ratePercent,
    TaxTreatment? treatment,
    bool? isActive,
  }) =>
      TaxProfile(
        id: id ?? this.id,
        code: code ?? this.code,
        name: name ?? this.name,
        ratePercent: ratePercent ?? this.ratePercent,
        treatment: treatment ?? this.treatment,
        isActive: isActive ?? this.isActive,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'code': code,
        'name': name,
        'ratePercent': ratePercent,
        'treatment': treatment.code,
        'isActive': isActive,
      };

  factory TaxProfile.fromJson(Map<String, dynamic> json) {
    final treatment = TaxTreatmentCode.fromCode(json['treatment']?.toString());
    final rawRate = (json['ratePercent'] as num? ?? 0).toDouble();
    final rate = treatment == TaxTreatment.standard && rawRate.isFinite
        ? rawRate.clamp(0, 100).toDouble()
        : 0.0;
    return TaxProfile(
      id: json['id']?.toString().trim().isNotEmpty == true
          ? json['id'].toString().trim()
          : standardId,
      code: json['code']?.toString().trim() ?? '',
      name: json['name']?.toString().trim() ?? '',
      ratePercent: rate,
      treatment: treatment,
      isActive: json['isActive'] != false,
    );
  }
}

class TaxAmountBreakdown {
  const TaxAmountBreakdown({
    required this.grossAmount,
    required this.taxableBase,
    required this.taxAmount,
    required this.ratePercent,
    required this.taxCode,
    required this.taxMode,
  });

  final double grossAmount;
  final double taxableBase;
  final double taxAmount;
  final double ratePercent;
  final String taxCode;
  final String taxMode;
}

class TaxCalculator {
  const TaxCalculator._();

  /// Ventio retail/catalog prices are tax-inclusive. Phase 2 therefore extracts
  /// VAT from the amount actually charged after line/document discounts.
  static TaxAmountBreakdown inclusive(
    double grossAmount,
    TaxProfile profile, {
    int decimals = 2,
  }) {
    final gross = _round(_clean(grossAmount), decimals);
    final normalizedRate = profile.ratePercent.isFinite
        ? profile.ratePercent.clamp(0, 100).toDouble()
        : 0.0;
    if (gross <= 0 ||
        !profile.isActive ||
        profile.treatment != TaxTreatment.standard ||
        normalizedRate <= 0) {
      return TaxAmountBreakdown(
        grossAmount: gross,
        taxableBase: gross,
        taxAmount: 0,
        ratePercent: profile.treatment == TaxTreatment.standard
            ? normalizedRate
            : 0,
        taxCode: profile.code,
        taxMode: profile.treatment.code,
      );
    }
    final net = _round(gross / (1 + normalizedRate / 100), decimals);
    final tax = _round(gross - net, decimals);
    return TaxAmountBreakdown(
      grossAmount: gross,
      taxableBase: net,
      taxAmount: tax,
      ratePercent: normalizedRate,
      taxCode: profile.code,
      taxMode: profile.treatment.code,
    );
  }

  static double _clean(double value) => value.isFinite && value > 0 ? value : 0;

  static double _round(double value, int decimals) {
    if (!value.isFinite) return 0;
    final safe = decimals.clamp(0, 6).toInt();
    final factor = <double>[1, 10, 100, 1000, 10000, 100000, 1000000][safe];
    return (value * factor).roundToDouble() / factor;
  }
}
