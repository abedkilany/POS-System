class CashLedgerTransaction {
  CashLedgerTransaction({
    required this.id,
    required this.type,
    required this.direction,
    required this.amount,
    this.currency = 'USD',
    required this.cashLocationId,
    this.cashDrawerSessionId = '',
    this.referenceType = '',
    this.referenceId = '',
    this.referenceNumber = '',
    this.partyType = '',
    this.partyId = '',
    this.partyName = '',
    this.paymentMethod = 'Cash',
    this.createdBy = '',
    this.createdByUserId = '',
    this.deviceId = '',
    this.branchId = '',
    this.storeId = '',
    this.notes = '',
    this.idempotencyKey = '',
    DateTime? occurredAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deletedAt,
    this.reversalOfId = '',
    this.syncStatus = 'pending',
    this.version = 1,
    this.lastModifiedByDeviceId = '',
  })  : occurredAt = occurredAt ?? DateTime.now().toUtc(),
        createdAt = createdAt ?? DateTime.now().toUtc(),
        updatedAt = updatedAt ?? createdAt ?? DateTime.now().toUtc();

  final String id;
  final String type;
  final String direction;
  final double amount;
  final String currency;
  final String cashLocationId;
  final String cashDrawerSessionId;
  final String referenceType;
  final String referenceId;
  final String referenceNumber;
  final String partyType;
  final String partyId;
  final String partyName;
  final String paymentMethod;
  final String createdBy;
  final String createdByUserId;
  final String deviceId;
  final String branchId;
  final String storeId;
  final String notes;
  final String idempotencyKey;
  final DateTime occurredAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String reversalOfId;
  final String syncStatus;
  final int version;
  final String lastModifiedByDeviceId;

  bool get isDeleted => deletedAt != null;
  bool get isCashIn => direction == 'in';
  bool get isCashOut => direction == 'out';
  double get signedAmount => isCashIn ? amount : -amount;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'type': type,
        'direction': direction,
        'amount': amount,
        'currency': currency,
        'cashLocationId': cashLocationId,
        'cashDrawerSessionId': cashDrawerSessionId,
        'referenceType': referenceType,
        'referenceId': referenceId,
        'referenceNumber': referenceNumber,
        'partyType': partyType,
        'partyId': partyId,
        'partyName': partyName,
        'paymentMethod': paymentMethod,
        'createdBy': createdBy,
        'createdByUserId': createdByUserId,
        'deviceId': deviceId,
        'branchId': branchId,
        'storeId': storeId,
        'notes': notes,
        'idempotencyKey': idempotencyKey,
        'occurredAt': occurredAt.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'deletedAt': deletedAt?.toIso8601String(),
        'reversalOfId': reversalOfId,
        'syncStatus': syncStatus,
        'version': version,
        'lastModifiedByDeviceId': lastModifiedByDeviceId,
      };

  factory CashLedgerTransaction.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now().toUtc();
    double amountOf(dynamic value) {
      final parsed = value is num
          ? value.toDouble()
          : double.tryParse(value?.toString() ?? '') ?? 0;
      return parsed.isFinite && parsed >= 0 ? parsed : 0;
    }

    return CashLedgerTransaction(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      direction: json['direction']?.toString() ?? '',
      amount: amountOf(json['amount']),
      currency: (json['currency']?.toString().trim().isEmpty ?? true)
          ? 'USD'
          : json['currency'].toString().trim().toUpperCase(),
      cashLocationId: json['cashLocationId']?.toString() ?? '',
      cashDrawerSessionId: json['cashDrawerSessionId']?.toString() ?? '',
      referenceType: json['referenceType']?.toString() ?? '',
      referenceId: json['referenceId']?.toString() ?? '',
      referenceNumber: json['referenceNumber']?.toString() ?? '',
      partyType: json['partyType']?.toString() ?? '',
      partyId: json['partyId']?.toString() ?? '',
      partyName: json['partyName']?.toString() ?? '',
      paymentMethod: json['paymentMethod']?.toString() ?? 'Cash',
      createdBy: json['createdBy']?.toString() ?? '',
      createdByUserId: json['createdByUserId']?.toString() ?? '',
      deviceId: json['deviceId']?.toString() ?? '',
      branchId: json['branchId']?.toString() ?? '',
      storeId: json['storeId']?.toString() ?? '',
      notes: json['notes']?.toString() ?? '',
      idempotencyKey: json['idempotencyKey']?.toString() ?? '',
      occurredAt: DateTime.tryParse(json['occurredAt']?.toString() ?? '') ?? now,
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? now,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? now,
      deletedAt: DateTime.tryParse(json['deletedAt']?.toString() ?? ''),
      reversalOfId: json['reversalOfId']?.toString() ?? '',
      syncStatus: json['syncStatus']?.toString() ?? 'pending',
      version: (json['version'] as num? ?? 1).toInt(),
      lastModifiedByDeviceId:
          json['lastModifiedByDeviceId']?.toString() ?? '',
    );
  }
}
