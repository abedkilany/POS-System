import 'sale_item.dart';
import 'posted_document_snapshot.dart';

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
    this.operationReferenceId = '',
    this.version = 1,
    this.createdAt,
    this.updatedAt,
    this.postedSnapshot,
  });

  final String id, creditNoteNo, originalSaleId, originalInvoiceNo;
  final String customerName, customerId, currency, refundMethod, note, status;
  final String operationReferenceId;
  final DateTime date;
  final List<SaleItem> items;
  final double amount;
  final int version;
  final DateTime? createdAt, updatedAt;
  final PostedDocumentSnapshot? postedSnapshot;

  CreditNote copyWith({
    String? customerName,
    String? customerId,
    DateTime? date,
    List<SaleItem>? items,
    double? amount,
    String? currency,
    String? refundMethod,
    String? note,
    String? status,
    String? operationReferenceId,
    int? version,
    DateTime? updatedAt,
    PostedDocumentSnapshot? postedSnapshot,
    bool clearPostedSnapshot = false,
  }) =>
      CreditNote(
        id: id,
        creditNoteNo: creditNoteNo,
        originalSaleId: originalSaleId,
        originalInvoiceNo: originalInvoiceNo,
        customerName: customerName ?? this.customerName,
        customerId: customerId ?? this.customerId,
        date: date ?? this.date,
        items: items ?? this.items,
        amount: amount ?? this.amount,
        currency: currency ?? this.currency,
        refundMethod: refundMethod ?? this.refundMethod,
        note: note ?? this.note,
        status: status ?? this.status,
        operationReferenceId:
            operationReferenceId ?? this.operationReferenceId,
        version: version ?? this.version,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        postedSnapshot: clearPostedSnapshot
            ? null
            : (postedSnapshot ?? this.postedSnapshot),
      );

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
        'operationReferenceId': operationReferenceId,
        'version': version,
        'createdAt': (createdAt ?? date).toIso8601String(),
        'updatedAt': (updatedAt ?? date).toIso8601String(),
        'postedSnapshot': postedSnapshot?.toJson(),
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
      operationReferenceId:
          json['operationReferenceId']?.toString() ?? '',
      version: (json['version'] as num? ?? 1).toInt(),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
      postedSnapshot: json['postedSnapshot'] is Map
          ? PostedDocumentSnapshot.fromJson(
              Map<String, dynamic>.from(json['postedSnapshot'] as Map),
            )
          : null,
    );
  }
}
