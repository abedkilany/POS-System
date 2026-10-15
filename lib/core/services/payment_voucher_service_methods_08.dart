part of 'payment_voucher_service.dart';

extension PaymentVoucherServiceSplitPart8 on PaymentVoucherService {

  ReceiptVoucher _receiptFromRow(
      Map<String, Object?> row, List<PaymentAllocation> allocations) {
    return ReceiptVoucher(
      id: row['id']?.toString() ?? '',
      voucherNo: row['voucher_no']?.toString() ?? '',
      customerId: row['customer_id']?.toString() ?? '',
      customerName: row['customer_name']?.toString() ?? '',
      date: _date(row['voucher_date']),
      amount: _number(row['amount']),
      discount: _number(row['discount']),
      unallocatedAmount: _number(row['unallocated_amount']),
      currency: row['currency']?.toString() ?? 'USD',
      paymentMethod: row['payment_method']?.toString() ?? 'Cash',
      cashLocationId: row['cash_location_id']?.toString() ?? '',
      cashDrawerSessionId: row['cash_drawer_session_id']?.toString() ?? '',
      status: row['status']?.toString() ?? 'posted',
      reversalReason: row['reversal_reason']?.toString() ?? '',
      reversedBy: row['reversed_by']?.toString() ?? '',
      reversedByUserId: row['reversed_by_user_id']?.toString() ?? '',
      reversedAt: _nullableDate(row['reversed_at']),
      notes: row['notes']?.toString() ?? '',
      createdBy: row['created_by']?.toString() ?? '',
      createdByUserId: row['created_by_user_id']?.toString() ?? '',
      deviceId: row['device_id']?.toString() ?? '',
      branchId: row['branch_id']?.toString() ?? '',
      storeId: row['store_id']?.toString() ?? '',
      idempotencyKey: row['idempotency_key']?.toString() ?? '',
      allocations: allocations,
      createdAt: _date(row['created_at']),
      updatedAt: _date(row['updated_at']),
      deletedAt: _nullableDate(row['deleted_at']),
      syncStatus: row['sync_status']?.toString() ?? 'pending',
      version: (row['version'] as num?)?.toInt() ?? 1,
      lastModifiedByDeviceId:
          row['last_modified_by_device_id']?.toString() ?? '',
    );
  }

  PaymentVoucher _paymentFromRow(
      Map<String, Object?> row, List<PaymentAllocation> allocations) {
    return PaymentVoucher(
      id: row['id']?.toString() ?? '',
      voucherNo: row['voucher_no']?.toString() ?? '',
      supplierId: row['supplier_id']?.toString() ?? '',
      supplierName: row['supplier_name']?.toString() ?? '',
      date: _date(row['voucher_date']),
      amount: _number(row['amount']),
      discount: _number(row['discount']),
      unallocatedAmount: _number(row['unallocated_amount']),
      currency: row['currency']?.toString() ?? 'USD',
      paymentMethod: row['payment_method']?.toString() ?? 'Cash',
      cashLocationId: row['cash_location_id']?.toString() ?? '',
      cashDrawerSessionId: row['cash_drawer_session_id']?.toString() ?? '',
      status: row['status']?.toString() ?? 'posted',
      reversalReason: row['reversal_reason']?.toString() ?? '',
      reversedBy: row['reversed_by']?.toString() ?? '',
      reversedByUserId: row['reversed_by_user_id']?.toString() ?? '',
      reversedAt: _nullableDate(row['reversed_at']),
      notes: row['notes']?.toString() ?? '',
      createdBy: row['created_by']?.toString() ?? '',
      createdByUserId: row['created_by_user_id']?.toString() ?? '',
      deviceId: row['device_id']?.toString() ?? '',
      branchId: row['branch_id']?.toString() ?? '',
      storeId: row['store_id']?.toString() ?? '',
      idempotencyKey: row['idempotency_key']?.toString() ?? '',
      allocations: allocations,
      createdAt: _date(row['created_at']),
      updatedAt: _date(row['updated_at']),
      deletedAt: _nullableDate(row['deleted_at']),
      syncStatus: row['sync_status']?.toString() ?? 'pending',
      version: (row['version'] as num?)?.toInt() ?? 1,
      lastModifiedByDeviceId:
          row['last_modified_by_device_id']?.toString() ?? '',
    );
  }

  PaymentAllocation _allocationFromRow(Map<String, Object?> row) =>
      PaymentAllocation(
        id: row['id']?.toString() ?? '',
        voucherType: row['voucher_type']?.toString() ?? '',
        voucherId: row['voucher_id']?.toString() ?? '',
        referenceType: row['reference_type']?.toString() ?? '',
        referenceId: row['reference_id']?.toString() ?? '',
        referenceNumber: row['reference_number']?.toString() ?? '',
        amount: _number(row['amount']),
        referenceAmount: _number(row['reference_amount']),
        currency: row['currency']?.toString() ?? 'USD',
        referenceCurrency: row['reference_currency']?.toString() ?? 'USD',
        exchangeRate: _number(row['exchange_rate']) <= 0
            ? 1
            : _number(row['exchange_rate']),
        status: row['status']?.toString() ?? 'active',
        allocationKind: row['allocation_kind']?.toString() ?? 'allocation',
        reversalOfId: row['reversal_of_id']?.toString() ?? '',
        reversalReason: row['reversal_reason']?.toString() ?? '',
        reversedBy: row['reversed_by']?.toString() ?? '',
        reversedByUserId: row['reversed_by_user_id']?.toString() ?? '',
        reversedAt: _nullableDate(row['reversed_at']),
        createdAt: _date(row['created_at']),
        updatedAt: _date(row['updated_at']),
        deletedAt: _nullableDate(row['deleted_at']),
        syncStatus: row['sync_status']?.toString() ?? 'pending',
        version: (row['version'] as num?)?.toInt() ?? 1,
        lastModifiedByDeviceId:
            row['last_modified_by_device_id']?.toString() ?? '',
      );

  bool _isCash(String method) {
    final value = method.trim().toLowerCase();
    return value.isEmpty || value == 'cash';
  }

  String _currency(String value) =>
      value.trim().isEmpty ? 'USD' : value.trim().toUpperCase();
  double _money(double value) => (value * 1000000).roundToDouble() / 1000000;
  double _number(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;
  DateTime _date(Object? value) =>
      DateTime.tryParse(value?.toString() ?? '') ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  DateTime? _nullableDate(Object? value) =>
      DateTime.tryParse(value?.toString() ?? '');
}
