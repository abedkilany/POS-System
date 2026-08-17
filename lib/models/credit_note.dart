import 'sale_item.dart';

class CreditNote {
  CreditNote({
    required this.id,
    required this.creditNoteNo,
    required this.originalSaleId,
    required this.originalInvoiceNo,
    required this.customerName,
    required this.customerId,
    required this.date,
    required this.items,
    required this.amount,
    this.currency = 'USD',
    this.refundMethod = 'Customer balance',
    this.note = '',
    this.status = 'Issued',
    this.createdAt,
    this.updatedAt,
  });

  final String id, creditNoteNo, originalSaleId, originalInvoiceNo;
  final String customerName, customerId, currency, refundMethod, note, status;
  final DateTime date;
  final List<SaleItem> items;
  final double amount;
  final DateTime? createdAt, updatedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'creditNoteNo': creditNoteNo,
        'originalSaleId': originalSaleId,
        'originalInvoiceNo': originalInvoiceNo,
        'customerName': customerName,
        'customerId': customerId,
        'date': date.toIso8601String(),
        'items': items.map((item) => item.toJson()).toList(),
        'amount': amount,
        'currency': currency,
        'refundMethod': refundMethod,
        'note': note,
        'status': status,
        'createdAt': (createdAt ?? date).toIso8601String(),
        'updatedAt': (updatedAt ?? date).toIso8601String(),
      };

  factory CreditNote.fromJson(Map<String, dynamic> json) {
    final date =
        DateTime.tryParse(json['date']?.toString() ?? '') ?? DateTime.now();
    return CreditNote(
      id: json['id']?.toString() ?? '',
      creditNoteNo: json['creditNoteNo']?.toString() ?? '',
      originalSaleId: json['originalSaleId']?.toString() ?? '',
      originalInvoiceNo: json['originalInvoiceNo']?.toString() ?? '',
      customerName: json['customerName']?.toString() ?? '',
      customerId: json['customerId']?.toString() ?? '',
      date: date,
      items: ((json['items'] as List<dynamic>?) ?? const [])
          .map((item) =>
              SaleItem.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(),
      amount: (json['amount'] as num? ?? 0).toDouble(),
      currency: json['currency']?.toString() ?? 'USD',
      refundMethod: json['refundMethod']?.toString() ?? 'Customer balance',
      note: json['note']?.toString() ?? '',
      status: json['status']?.toString() ?? 'Issued',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
    );
  }
}
