part of 'batch_inventory_service.dart';

extension BatchInventoryServiceSplitPart5 on BatchInventoryService {

  Future<void> _refreshBatchLifecycleStatusInTransaction({
    required String batchId,
    required String storeId,
    required DateTime updatedAt,
    required String deviceId,
    String syncStatus = 'pending',
  }) async {
    // Negative-stock deficit batches have their own lifecycle/status contract.
    if (BatchInventoryService.isDeficitBatchId(batchId)) return;
    final hasPositiveBalance = await db.customSelect(
      '''
      SELECT 1
      FROM inventory_batch_balances
      WHERE store_id = ? AND batch_id = ? AND quantity > 0.000001
      LIMIT 1
      ''',
      variables: <Variable<Object>>[
        Variable<String>(storeId),
        Variable<String>(batchId),
      ],
    ).getSingleOrNull();
    final nextStatus = hasPositiveBalance == null ? 'depleted' : 'active';
    final currentOpposite = nextStatus == 'depleted' ? 'active' : 'depleted';
    await db.customStatement(
      '''
      UPDATE inventory_batches
      SET status = ?, updated_at = ?, version = version + 1,
          last_modified_by_device_id = ?, sync_status = ?
      WHERE id = ? AND store_id = ? AND status = ?
      ''',
      <Object?>[
        nextStatus,
        updatedAt.toUtc().toIso8601String(),
        deviceId,
        syncStatus,
        batchId,
        storeId,
        currentOpposite,
      ],
    );
  }

  void _validateUnifiedExpiryContract({
    required Product product,
    required DateTime? expirationDate,
    required DateTime receivedAt,
  }) {
    if (product.expiryTrackingEnabled) {
      if (expirationDate == null) {
        throw LocalizedDomainException(
          'error_expiration_date_required',
          values: {'product': product.name},
          fallback: 'Expiration date is required for ${product.name}.',
        );
      }
      final receiptDay = _calendarDate(receivedAt);
      final minimumExpiry = receiptDay.add(
        Duration(days: product.minimumReceiptShelfLifeDays),
      );
      if (_calendarDate(expirationDate).isBefore(minimumExpiry)) {
        throw LocalizedDomainException(
          'error_minimum_shelf_life',
          values: {'product': product.name},
          fallback:
              'The remaining shelf life for ${product.name} is below the allowed minimum.',
        );
      }
      return;
    }
    if (expirationDate != null) {
      throw LocalizedDomainException(
        'error_expiration_not_allowed',
        values: {'product': product.name},
        fallback: 'Expiration date is disabled for ${product.name}.',
      );
    }
  }

  DateTime _calendarDate(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);

  String _calendarDateText(DateTime value) =>
      _calendarDate(value).toIso8601String().substring(0, 10);

  bool _sameCalendarDate(DateTime? left, DateTime? right) {
    if (left == null || right == null) return left == null && right == null;
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }
}
