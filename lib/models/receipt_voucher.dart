import 'payment_allocation.dart';

class ReceiptVoucher {
  ReceiptVoucher({
    required this.id,
    required this.voucherNo,
    required this.customerId,
    required this.customerName,
    required this.date,
    required this.amount,
    required this.unallocatedAmount,
    this.currency = 'USD',
    this.paymentMethod = 'Cash',
    this.cashLocationId = '',
    this.cashDrawerSessionId = '',
    this.status = 'posted',
    this.reversalReason = '',
    this.reversedBy = '',
    this.reversedByUserId = '',
    this.reversedAt,
    this.notes = '',
    this.createdBy = '',
    this.createdByUserId = '',
    this.deviceId = '',
    this.branchId = '',
    this.storeId = '',
    this.idempotencyKey = '',
    this.allocations = const <PaymentAllocation>[],
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deletedAt,
    this.syncStatus = 'pending',
    this.version = 1,
    this.lastModifiedByDeviceId = '',
  })  : createdAt = createdAt ?? DateTime.now().toUtc(),
        updatedAt = updatedAt ?? createdAt ?? DateTime.now().toUtc();

  final String id, voucherNo, customerId, customerName, currency, paymentMethod;
  final String cashLocationId, cashDrawerSessionId, status, notes;
  final String reversalReason, reversedBy, reversedByUserId;
  final String createdBy, createdByUserId, deviceId, branchId, storeId;
  final String idempotencyKey, syncStatus, lastModifiedByDeviceId;
  final DateTime date, createdAt, updatedAt;
  final DateTime? deletedAt, reversedAt;
  final double amount, unallocatedAmount;
  final int version;
  final List<PaymentAllocation> allocations;

  bool get isDeleted => deletedAt != null;
  bool get hasUnallocatedCredit => unallocatedAmount > 0.000001;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'voucherNo': voucherNo,
        'customerId': customerId,
        'customerName': customerName,
        'date': date.toIso8601String(),
        'amount': amount,
        'unallocatedAmount': unallocatedAmount,
        'currency': currency,
        'paymentMethod': paymentMethod,
        'cashLocationId': cashLocationId,
        'cashDrawerSessionId': cashDrawerSessionId,
        'status': status,
        'reversalReason': reversalReason,
        'reversedBy': reversedBy,
        'reversedByUserId': reversedByUserId,
        'reversedAt': reversedAt?.toIso8601String(),
        'notes': notes,
        'createdBy': createdBy,
        'createdByUserId': createdByUserId,
        'deviceId': deviceId,
        'branchId': branchId,
        'storeId': storeId,
        'idempotencyKey': idempotencyKey,
        'allocations': allocations.map((e) => e.toJson()).toList(growable: false),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'deletedAt': deletedAt?.toIso8601String(),
        'syncStatus': syncStatus,
        'version': version,
        'lastModifiedByDeviceId': lastModifiedByDeviceId,
      };
}
