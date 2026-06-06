import 'sale_item.dart';

class Sale {
  Sale({
    required this.id,
    required this.invoiceNo,
    required this.customerName,
    required this.date,
    required this.status,
    required this.items,
    required this.discount,
    this.customerId = '',
    this.paymentMethod = 'Cash',
    this.paymentStatus = 'paid',
    this.invoiceCurrency = 'USD',
    this.paymentCurrency = 'USD',
    this.exchangeRateAtPayment = 0,
    this.paidAmount = 0,
    this.cashReceivedAmount = 0,
    this.paidAmountInPaymentCurrency = 0,
    this.cashReceivedAmountInPaymentCurrency = 0,
    this.note = '',
    this.originalDiscount,
    this.discountCurrency = 'USD',
    this.discountExchangeRateAtEntry = 0,
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

  final String id, invoiceNo, customerName, customerId, status, paymentMethod, paymentStatus, invoiceCurrency, paymentCurrency, note, deviceId, syncStatus, storeId, branchId, lastModifiedByDeviceId;
  final DateTime date, createdAt, updatedAt;
  final DateTime? deletedAt;
  final List<SaleItem> items;
  final double discount, paidAmount, cashReceivedAmount, exchangeRateAtPayment, paidAmountInPaymentCurrency, cashReceivedAmountInPaymentCurrency;
  final double? originalDiscount;
  final String discountCurrency;
  final double discountExchangeRateAtEntry;
  final int version;

  bool get isDeleted => deletedAt != null;
  bool get isCancelled => status.toLowerCase() == 'cancelled' || status.toLowerCase() == 'returned';
  double get subtotal => items.fold<double>(0, (sum, item) => sum + item.lineTotal);
  double get total => isCancelled ? 0 : (subtotal - discount).clamp(0, double.infinity).toDouble();
  double get invoiceTotal {
    if (isCancelled) return 0;
    final rate = exchangeRateAtPayment <= 0 ? 1.0 : exchangeRateAtPayment;
    return invoiceCurrency.toUpperCase() == 'LBP' ? (total * rate) : total;
  }
  double get balanceDue => (invoiceTotal - paidAmount).clamp(0, double.infinity).toDouble();
  double get grossProfit => isCancelled ? 0 : items.fold<double>(0, (sum, item) => sum + item.lineProfit) - discount;

  Sale copyWith({
    String? id,
    String? invoiceNo,
    String? customerName,
    String? customerId,
    DateTime? date,
    String? status,
    List<SaleItem>? items,
    double? discount,
    double? originalDiscount,
    String? discountCurrency,
    double? discountExchangeRateAtEntry,
    String? paymentMethod,
    String? paymentStatus,
    String? invoiceCurrency,
    String? paymentCurrency,
    double? exchangeRateAtPayment,
    double? paidAmount,
    double? cashReceivedAmount,
    double? paidAmountInPaymentCurrency,
    double? cashReceivedAmountInPaymentCurrency,
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
      Sale(
        id: id ?? this.id,
        invoiceNo: invoiceNo ?? this.invoiceNo,
        customerName: customerName ?? this.customerName,
        customerId: customerId ?? this.customerId,
        date: date ?? this.date,
        status: status ?? this.status,
        items: items ?? this.items,
        discount: discount ?? this.discount,
        originalDiscount: originalDiscount ?? this.originalDiscount,
        discountCurrency: discountCurrency ?? this.discountCurrency,
        discountExchangeRateAtEntry: discountExchangeRateAtEntry ?? this.discountExchangeRateAtEntry,
        paymentMethod: paymentMethod ?? this.paymentMethod,
        paymentStatus: paymentStatus ?? this.paymentStatus,
        invoiceCurrency: invoiceCurrency ?? this.invoiceCurrency,
        paymentCurrency: paymentCurrency ?? this.paymentCurrency,
        exchangeRateAtPayment: exchangeRateAtPayment ?? this.exchangeRateAtPayment,
        paidAmount: paidAmount ?? this.paidAmount,
        cashReceivedAmount: cashReceivedAmount ?? this.cashReceivedAmount,
        paidAmountInPaymentCurrency: paidAmountInPaymentCurrency ?? this.paidAmountInPaymentCurrency,
        cashReceivedAmountInPaymentCurrency: cashReceivedAmountInPaymentCurrency ?? this.cashReceivedAmountInPaymentCurrency,
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
        'invoiceNo': invoiceNo,
        'customerName': customerName,
        'customerId': customerId,
        'date': date.toIso8601String(),
        'status': status,
        'discount': discount,
        'originalDiscount': originalDiscount ?? discount,
        'discountCurrency': discountCurrency,
        'discountExchangeRateAtEntry': discountExchangeRateAtEntry,
        'paymentMethod': paymentMethod,
        'paymentStatus': paymentStatus,
        'invoiceCurrency': invoiceCurrency,
        'paymentCurrency': paymentCurrency,
        'exchangeRateAtPayment': exchangeRateAtPayment,
        'paidAmount': paidAmount,
        'cashReceivedAmount': cashReceivedAmount,
        'paidAmountInPaymentCurrency': paidAmountInPaymentCurrency,
        'cashReceivedAmountInPaymentCurrency': cashReceivedAmountInPaymentCurrency,
        'note': note,
        'items': items.map((item) => item.toJson()).toList(),
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

  factory Sale.fromJson(Map<String, dynamic> json) {
    final date = DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now();
    final updated = DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? date;
    final items = (json['items'] as List<dynamic>).map((item) => SaleItem.fromJson(Map<String, dynamic>.from(item as Map))).toList();
    final discount = (json['discount'] as num? ?? 0).toDouble();
    final subtotal = items.fold<double>(0, (sum, item) => sum + item.lineTotal);
    final total = (subtotal - discount).clamp(0, double.infinity).toDouble();
    final legacyStatus = json['status'] as String? ?? 'Paid';
    final paymentStatus = json['paymentStatus'] as String? ?? (legacyStatus.toLowerCase() == 'paid' ? 'paid' : 'credit');
    final invoiceCurrency = ((json['invoiceCurrency'] as String? ?? 'USD').toUpperCase() == 'LBP') ? 'LBP' : 'USD';
    final paymentCurrency = ((json['paymentCurrency'] as String? ?? invoiceCurrency).toUpperCase() == 'LBP') ? 'LBP' : 'USD';
    final exchangeRateAtPayment = (json['exchangeRateAtPayment'] as num? ?? json['discountExchangeRateAtEntry'] as num? ?? 0).toDouble();
    final invoiceTotal = invoiceCurrency == 'LBP' ? total * (exchangeRateAtPayment <= 0 ? 89500 : exchangeRateAtPayment) : total;
    final paidAmount = (json['paidAmount'] as num?)?.toDouble() ?? (paymentStatus == 'paid' ? invoiceTotal : 0);
    final paymentMethod = json['paymentMethod'] as String? ?? 'Cash';
    final cashReceivedAmount = (json['cashReceivedAmount'] as num?)?.toDouble() ?? (paymentMethod == 'Cash' ? paidAmount : 0);
    final paidAmountInPaymentCurrency = (json['paidAmountInPaymentCurrency'] as num?)?.toDouble() ?? paidAmount;
    final cashReceivedAmountInPaymentCurrency = (json['cashReceivedAmountInPaymentCurrency'] as num?)?.toDouble() ?? cashReceivedAmount;
    return Sale(
      id: json['id'] as String,
      invoiceNo: json['invoiceNo'] as String,
      customerName: json['customerName'] as String,
      customerId: json['customerId'] as String? ?? '',
      date: date,
      status: legacyStatus,
      discount: discount,
      originalDiscount: (json['originalDiscount'] as num?)?.toDouble() ?? discount,
      discountCurrency: ((json['discountCurrency'] as String? ?? 'USD').toUpperCase() == 'LBP') ? 'LBP' : 'USD',
      discountExchangeRateAtEntry: (json['discountExchangeRateAtEntry'] as num? ?? 0).toDouble(),
      paymentMethod: paymentMethod,
      paymentStatus: paymentStatus,
      invoiceCurrency: invoiceCurrency,
      paymentCurrency: paymentCurrency,
      exchangeRateAtPayment: exchangeRateAtPayment,
      paidAmount: paidAmount,
      cashReceivedAmount: cashReceivedAmount,
      paidAmountInPaymentCurrency: paidAmountInPaymentCurrency,
      cashReceivedAmountInPaymentCurrency: cashReceivedAmountInPaymentCurrency,
      note: json['note'] as String? ?? '',
      items: items,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? date,
      updatedAt: updated,
      deletedAt: DateTime.tryParse(json['deletedAt'] as String? ?? ''),
      deviceId: json['deviceId'] as String? ?? '',
      syncStatus: json['syncStatus'] as String? ?? 'synced',
      storeId: json['storeId'] as String? ?? '',
      branchId: json['branchId'] as String? ?? '',
      version: (json['version'] as num? ?? 1).toInt(),
      lastModifiedByDeviceId: json['lastModifiedByDeviceId'] as String? ?? json['deviceId'] as String? ?? '',
    );
  }
}
