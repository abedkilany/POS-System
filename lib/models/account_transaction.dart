class AccountTransaction {
  AccountTransaction({
    required this.id,
    required this.accountType,
    required this.accountId,
    required this.accountName,
    required this.date,
    required this.type,
    required this.referenceId,
    required this.referenceNo,
    this.debit = 0,
    this.credit = 0,
    this.currency = 'USD',
    this.paymentMethod = '',
    this.note = '',
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deletedAt,
    this.deviceId = '',
    this.syncStatus = 'pending',
    this.storeId = '',
    this.branchId = '',
    this.version = 1,
    this.lastModifiedByDeviceId = '',
  })  : createdAt = createdAt ?? updatedAt ?? date,
        updatedAt = updatedAt ?? createdAt ?? date;

  final String id, accountType, accountId, accountName, type, referenceId, referenceNo, currency, paymentMethod, note;
  final DateTime date, createdAt, updatedAt;
  final DateTime? deletedAt;
  final double debit, credit;
  final String deviceId, syncStatus, storeId, branchId, lastModifiedByDeviceId;
  final int version;

  bool get isDeleted => deletedAt != null;
  bool get isCustomer => accountType.toLowerCase() == 'customer';
  bool get isSupplier => accountType.toLowerCase() == 'supplier';
  double get signedAmount => debit - credit;

  AccountTransaction copyWith({
    String? id,
    String? accountType,
    String? accountId,
    String? accountName,
    DateTime? date,
    String? type,
    String? referenceId,
    String? referenceNo,
    double? debit,
    double? credit,
    String? currency,
    String? paymentMethod,
    String? note,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
    String? deviceId,
    String? syncStatus,
    String? storeId,
    String? branchId,
    int? version,
    String? lastModifiedByDeviceId,
  }) =>
      AccountTransaction(
        id: id ?? this.id,
        accountType: accountType ?? this.accountType,
        accountId: accountId ?? this.accountId,
        accountName: accountName ?? this.accountName,
        date: date ?? this.date,
        type: type ?? this.type,
        referenceId: referenceId ?? this.referenceId,
        referenceNo: referenceNo ?? this.referenceNo,
        debit: debit ?? this.debit,
        credit: credit ?? this.credit,
        currency: currency ?? this.currency,
        paymentMethod: paymentMethod ?? this.paymentMethod,
        note: note ?? this.note,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
        deviceId: deviceId ?? this.deviceId,
        syncStatus: syncStatus ?? this.syncStatus,
        storeId: storeId ?? this.storeId,
        branchId: branchId ?? this.branchId,
        version: version ?? this.version,
        lastModifiedByDeviceId: lastModifiedByDeviceId ?? this.lastModifiedByDeviceId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'accountType': accountType,
        'accountId': accountId,
        'accountName': accountName,
        'date': date.toIso8601String(),
        'type': type,
        'referenceId': referenceId,
        'referenceNo': referenceNo,
        'debit': debit,
        'credit': credit,
        'currency': currency,
        'paymentMethod': paymentMethod,
        'note': note,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'deletedAt': deletedAt?.toIso8601String(),
        'deviceId': deviceId,
        'syncStatus': syncStatus,
        'storeId': storeId,
        'branchId': branchId,
        'version': version,
        'lastModifiedByDeviceId': lastModifiedByDeviceId,
      };

  factory AccountTransaction.fromJson(Map<String, dynamic> json) {
    final date = DateTime.tryParse(json['date']?.toString() ?? '') ?? DateTime.now();
    final updated = DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? date;
    return AccountTransaction(
      id: json['id']?.toString() ?? '',
      accountType: json['accountType']?.toString() ?? '',
      accountId: json['accountId']?.toString() ?? '',
      accountName: json['accountName']?.toString() ?? '',
      date: date,
      type: json['type']?.toString() ?? '',
      referenceId: json['referenceId']?.toString() ?? '',
      referenceNo: json['referenceNo']?.toString() ?? '',
      debit: (json['debit'] as num? ?? 0).toDouble(),
      credit: (json['credit'] as num? ?? 0).toDouble(),
      currency: (json['currency']?.toString().trim().isEmpty ?? true) ? 'USD' : json['currency'].toString().trim().toUpperCase(),
      paymentMethod: json['paymentMethod']?.toString() ?? '',
      note: json['note']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? updated,
      updatedAt: updated,
      deletedAt: DateTime.tryParse(json['deletedAt']?.toString() ?? ''),
      deviceId: json['deviceId']?.toString() ?? '',
      syncStatus: json['syncStatus']?.toString() ?? 'synced',
      storeId: json['storeId']?.toString() ?? '',
      branchId: json['branchId']?.toString() ?? '',
      version: (json['version'] as num? ?? 1).toInt(),
      lastModifiedByDeviceId: json['lastModifiedByDeviceId']?.toString() ?? json['deviceId']?.toString() ?? '',
    );
  }
}
