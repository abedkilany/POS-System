class Expense {
  Expense({
    required this.id,
    required this.title,
    required this.category,
    required this.amount,
    this.originalAmount,
    this.originalCurrency = 'USD',
    this.exchangeRateAtEntry = 0,
    required this.date,
    required this.notes,
    this.status = 'Draft',
    this.cancelReason = '',
    this.cancelledByDeviceId = '',
    this.cancelledAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deletedAt,
    this.deviceId = '',
    this.syncStatus = 'pending',
    this.storeId = '',
    this.branchId = '',
    this.version = 1,
    this.lastModifiedByDeviceId = '',
  })  : createdAt =
            createdAt ?? updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt =
            updatedAt ?? createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
        searchText = _buildSearchText(
          title,
          category,
          notes,
          status,
          cancelReason,
        );

  final String id,
      title,
      category,
      notes,
      status,
      cancelReason,
      cancelledByDeviceId,
      deviceId,
      syncStatus,
      storeId,
      branchId,
      lastModifiedByDeviceId;

  /// USD reference amount used for reports and calculations.
  final double amount;
  final double? originalAmount;
  final String originalCurrency;
  final double exchangeRateAtEntry;
  final DateTime date, createdAt, updatedAt;
  final DateTime? deletedAt, cancelledAt;
  final int version;
  final String searchText;

  bool get isDeleted => deletedAt != null;
  bool get isDraft => status.toLowerCase() == 'draft';
  bool get isPosted => status.toLowerCase() == 'posted';
  bool get isCancelled => status.toLowerCase() == 'cancelled';

  static double _safeAmount(double value) =>
      value.isFinite && value > 0 ? value : 0;

  static double _safeRate(double value) =>
      value.isFinite && value > 0 ? value : 0;

  static double _parseAmount(dynamic value) {
    if (value is num) return _safeAmount(value.toDouble());
    return _safeAmount(double.tryParse(value?.toString() ?? '') ?? 0);
  }

  static double _parseRate(dynamic value) {
    if (value is num) return _safeRate(value.toDouble());
    return _safeRate(double.tryParse(value?.toString() ?? '') ?? 0);
  }

  static String _normalizeSearchPart(String value) =>
      value.trim().toLowerCase();

  static String _buildSearchText(
    String title,
    String category,
    String notes,
    String status,
    String cancelReason,
  ) {
    final parts = <String>[
      title,
      category,
      notes,
      status,
      cancelReason,
    ];
    return parts
        .map(_normalizeSearchPart)
        .where((part) => part.isNotEmpty)
        .join(' ');
  }

  Expense copyWith({
    String? id,
    String? title,
    String? category,
    double? amount,
    double? originalAmount,
    String? originalCurrency,
    double? exchangeRateAtEntry,
    DateTime? date,
    String? notes,
    String? status,
    String? cancelReason,
    String? cancelledByDeviceId,
    DateTime? cancelledAt,
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
      Expense(
        id: id ?? this.id,
        title: title ?? this.title,
        category: category ?? this.category,
        amount: amount ?? this.amount,
        originalAmount: originalAmount ?? this.originalAmount,
        originalCurrency: originalCurrency ?? this.originalCurrency,
        exchangeRateAtEntry: exchangeRateAtEntry ?? this.exchangeRateAtEntry,
        date: date ?? this.date,
        notes: notes ?? this.notes,
        status: status ?? this.status,
        cancelReason: cancelReason ?? this.cancelReason,
        cancelledByDeviceId: cancelledByDeviceId ?? this.cancelledByDeviceId,
        cancelledAt: cancelledAt ?? this.cancelledAt,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
        deviceId: deviceId ?? this.deviceId,
        syncStatus: syncStatus ?? this.syncStatus,
        storeId: storeId ?? this.storeId,
        branchId: branchId ?? this.branchId,
        version: version ?? this.version,
        lastModifiedByDeviceId:
            lastModifiedByDeviceId ?? this.lastModifiedByDeviceId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'category': category,
        'amount': _safeAmount(amount),
        'originalAmount': _safeAmount(originalAmount ?? amount),
        'originalCurrency': originalCurrency,
        'exchangeRateAtEntry': _safeRate(exchangeRateAtEntry),
        'date': date.toIso8601String(),
        'notes': notes,
        'status': status,
        'cancelReason': cancelReason,
        'cancelledByDeviceId': cancelledByDeviceId,
        'cancelledAt': cancelledAt?.toIso8601String(),
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

  factory Expense.fromJson(Map<String, dynamic> json) {
    final updated =
        DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now();
    final originalCurrencyRaw =
        (json['originalCurrency'] as String? ?? 'USD').toUpperCase();
    final originalCurrency = originalCurrencyRaw == 'LBP' ? 'LBP' : 'USD';
    final amount = _parseAmount(json['amount']);
    final rawStatus = (json['status'] as String? ?? '').trim();
    final normalizedStatus = rawStatus.toLowerCase();
    final status = normalizedStatus == 'draft'
        ? 'Draft'
        : normalizedStatus == 'cancelled'
            ? 'Cancelled'
            : 'Posted';
    return Expense(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      category: json['category'] as String? ?? '',
      amount: amount,
      originalAmount: _parseAmount(json['originalAmount'] ?? amount),
      originalCurrency: originalCurrency,
      exchangeRateAtEntry: _parseRate(json['exchangeRateAtEntry']),
      date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
      notes: json['notes'] as String? ?? '',
      status: status,
      cancelReason: json['cancelReason'] as String? ?? '',
      cancelledByDeviceId: json['cancelledByDeviceId'] as String? ?? '',
      cancelledAt: DateTime.tryParse(json['cancelledAt'] as String? ?? ''),
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ?? updated,
      updatedAt: updated,
      deletedAt: DateTime.tryParse(json['deletedAt'] as String? ?? ''),
      deviceId: json['deviceId'] as String? ?? '',
      syncStatus: json['syncStatus'] as String? ?? 'synced',
      storeId: json['storeId'] as String? ?? '',
      branchId: json['branchId'] as String? ?? '',
      version: (json['version'] as num? ?? 1).toInt(),
      lastModifiedByDeviceId: json['lastModifiedByDeviceId'] as String? ??
          json['deviceId'] as String? ??
          '',
    );
  }
}
