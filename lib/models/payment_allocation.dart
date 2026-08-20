class PaymentAllocation {
  PaymentAllocation({
    required this.id,
    required this.voucherType,
    required this.voucherId,
    required this.referenceType,
    required this.referenceId,
    required this.referenceNumber,
    required this.amount,
    this.referenceAmount = 0,
    this.currency = 'USD',
    this.referenceCurrency = 'USD',
    this.exchangeRate = 1,
    this.status = 'active',
    this.reversalReason = '',
    this.reversedBy = '',
    this.reversedByUserId = '',
    this.reversedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deletedAt,
    this.syncStatus = 'pending',
    this.version = 1,
    this.lastModifiedByDeviceId = '',
  })  : createdAt = createdAt ?? DateTime.now().toUtc(),
        updatedAt = updatedAt ?? createdAt ?? DateTime.now().toUtc();

  final String id;
  final String voucherType; // receipt | payment
  final String voucherId;
  final String referenceType; // sale | purchase
  final String referenceId;
  final String referenceNumber;
  final double amount; // amount consumed from the voucher currency
  final double referenceAmount; // amount applied to the target document currency
  final String currency;
  final String referenceCurrency;
  final double exchangeRate;
  final String status, reversalReason, reversedBy, reversedByUserId;
  final DateTime? reversedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String syncStatus;
  final int version;
  final String lastModifiedByDeviceId;

  bool get isDeleted => deletedAt != null;
  double get effectiveReferenceAmount => referenceAmount > 0 ? referenceAmount : amount;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'voucherType': voucherType,
        'voucherId': voucherId,
        'referenceType': referenceType,
        'referenceId': referenceId,
        'referenceNumber': referenceNumber,
        'amount': amount,
        'referenceAmount': referenceAmount,
        'currency': currency,
        'referenceCurrency': referenceCurrency,
        'exchangeRate': exchangeRate,
        'status': status,
        'reversalReason': reversalReason,
        'reversedBy': reversedBy,
        'reversedByUserId': reversedByUserId,
        'reversedAt': reversedAt?.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'deletedAt': deletedAt?.toIso8601String(),
        'syncStatus': syncStatus,
        'version': version,
        'lastModifiedByDeviceId': lastModifiedByDeviceId,
      };

  factory PaymentAllocation.fromJson(Map<String, dynamic> json) {
    double value(dynamic raw) => raw is num
        ? raw.toDouble()
        : double.tryParse(raw?.toString() ?? '') ?? 0;
    final now = DateTime.now().toUtc();
    return PaymentAllocation(
      id: json['id']?.toString() ?? '',
      voucherType: json['voucherType']?.toString() ?? '',
      voucherId: json['voucherId']?.toString() ?? '',
      referenceType: json['referenceType']?.toString() ?? '',
      referenceId: json['referenceId']?.toString() ?? '',
      referenceNumber: json['referenceNumber']?.toString() ?? '',
      amount: value(json['amount']),
      referenceAmount: value(json['referenceAmount']),
      currency: json['currency']?.toString() ?? 'USD',
      referenceCurrency: json['referenceCurrency']?.toString() ?? 'USD',
      exchangeRate: value(json['exchangeRate']) <= 0 ? 1 : value(json['exchangeRate']),
      status: json['status']?.toString() ?? 'active',
      reversalReason: json['reversalReason']?.toString() ?? '',
      reversedBy: json['reversedBy']?.toString() ?? '',
      reversedByUserId: json['reversedByUserId']?.toString() ?? '',
      reversedAt: DateTime.tryParse(json['reversedAt']?.toString() ?? ''),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? now,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? now,
      deletedAt: DateTime.tryParse(json['deletedAt']?.toString() ?? ''),
      syncStatus: json['syncStatus']?.toString() ?? 'pending',
      version: (json['version'] as num? ?? 1).toInt(),
      lastModifiedByDeviceId: json['lastModifiedByDeviceId']?.toString() ?? '',
    );
  }
}

class PaymentAllocationDraft {
  const PaymentAllocationDraft({
    required this.referenceId,
    this.referenceNumber = '',
    required this.amount,
    this.referenceAmount = 0,
    this.referenceCurrency = '',
    this.exchangeRate = 1,
  });

  final String referenceId;
  final String referenceNumber;
  final double amount;
  final double referenceAmount;
  final String referenceCurrency;
  final double exchangeRate;
}
