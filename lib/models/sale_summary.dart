class SaleSummary {
  const SaleSummary({
    required this.id,
    required this.invoiceNo,
    required this.customerName,
    required this.date,
    required this.status,
    required this.paymentStatus,
    required this.total,
    required this.productCount,
    this.customerId = '',
  });

  final String id;
  final String invoiceNo;
  final String customerName;
  final String customerId;
  final DateTime date;
  final String status;
  final String paymentStatus;
  final double total;
  final int productCount;

  bool get isCancelled =>
      status.toLowerCase() == 'cancelled' || status.toLowerCase() == 'returned';

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'invoiceNo': invoiceNo,
        'customerName': customerName,
        'customerId': customerId,
        'date': date.toIso8601String(),
        'status': status,
        'paymentStatus': paymentStatus,
        'total': total,
        'productCount': productCount,
      };

  factory SaleSummary.fromJson(Map<String, dynamic> json) {
    return SaleSummary(
      id: json['id'] as String? ?? '',
      invoiceNo: json['invoiceNo'] as String? ?? '',
      customerName: json['customerName'] as String? ?? '',
      customerId: json['customerId'] as String? ?? '',
      date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
      status: json['status'] as String? ?? 'paid',
      paymentStatus: json['paymentStatus'] as String? ?? 'paid',
      total: (json['total'] as num?)?.toDouble() ?? 0,
      productCount: (json['productCount'] as num?)?.toInt() ?? 0,
    );
  }
}
