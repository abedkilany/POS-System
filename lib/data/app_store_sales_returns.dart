part of 'app_store.dart';

extension _AppStoreSplitSalesReturns on AppStore {
  Future<SaleQuotation> createSaleQuotation({
    required String customerName,
    String customerId = '',
    required List<SaleItem> items,
    double discount = 0,
    String invoiceCurrency = 'USD',
    String note = '',
    DateTime? validUntil,
  }) async {
    requirePermission(AppPermission.quotationsManage);
    if (items.isEmpty) {
      throw ArgumentError('Quotation must contain at least one item.');
    }
    final cleanedDiscount =
        discount.isFinite ? discount.clamp(0, double.infinity).toDouble() : 0.0;
    final subtotal = items.fold<double>(0, (sum, item) => sum + item.lineTotal);
    if (cleanedDiscount > subtotal) {
      throw ArgumentError('Discount cannot be greater than subtotal.');
    }
    for (final item in items) {
      if (item.quantity <= 0 || item.unitPrice < 0) {
        throw ArgumentError('Invalid quotation item values.');
      }
      if (_findProductById(item.productId) == null) {
        throw ArgumentError('Product not found: ${item.productName}');
      }
    }
    final now = DateTime.now();
    final quotation = SaleQuotation(
      id: now.microsecondsSinceEpoch.toString(),
      quotationNo:
          'QTN-$_invoiceDevicePrefix-${(saleQuotations.length + 1).toString().padLeft(6, '0')}',
      customerName: customerName.trim().isEmpty
          ? AppStore.walkInCustomerName
          : customerName.trim(),
      customerId: customerId.trim().isEmpty
          ? AppStore.walkInCustomerId
          : customerId.trim(),
      date: now,
      validUntil: validUntil,
      status: 'Draft',
      items: items,
      discount: cleanedDiscount,
      invoiceCurrency: invoiceCurrency.toUpperCase() == 'LBP' ? 'LBP' : 'USD',
      note: note.trim(),
      createdAt: now,
      updatedAt: now,
      deviceId: _deviceId,
      syncStatus: 'pending',
      storeId: appIdentity.storeId,
      branchId: appIdentity.branchId,
      version: 1,
      lastModifiedByDeviceId: _deviceId,
    );
    _saleQuotations.add(quotation);
    _recordSyncChange(
      entityType: 'sale_quotation',
      entityId: quotation.id,
      operation: 'create',
      payload: quotation.toJson(),
    );
    await _saveDirty(saleQuotations: true, sync: true);
    notifyListeners();
    return quotation;
  }

  Future<Sale> convertSaleQuotationToSale(
    String quotationId, {
    String paymentMethod = 'Cash',
    String paymentStatus = 'paid',
  }) async {
    requireAllPermissions(<String>{
      AppPermission.quotationsManage,
      AppPermission.salesCreate,
    });
    final index = _saleQuotations.indexWhere((item) => item.id == quotationId);
    if (index == -1) throw ArgumentError('Quotation not found.');
    final quotation = _saleQuotations[index];
    if (quotation.isDeleted) throw StateError('Quotation is deleted.');
    if (quotation.isConverted) {
      throw StateError('Quotation is already converted.');
    }
    final sale = await createSale(
      customerName: quotation.customerName,
      customerId: quotation.customerId,
      items: quotation.items,
      discount: quotation.discount,
      originalDiscount: quotation.discount,
      invoiceCurrency: quotation.invoiceCurrency,
      paymentCurrency: quotation.invoiceCurrency,
      paymentMethod: paymentMethod,
      paymentStatus: paymentStatus,
    );
    final now = DateTime.now();
    final updated = _withSyncMeta<SaleQuotation>(
      quotation.copyWith(
        status: 'Converted',
        convertedSaleId: sale.id,
        updatedAt: now,
      ),
      now,
    );
    _saleQuotations[index] = updated;
    _recordSyncChange(
      entityType: 'sale_quotation',
      entityId: updated.id,
      operation: 'convert',
      payload: updated.toJson(),
    );
    await _saveDirty(saleQuotations: true, sync: true);
    notifyListeners();
    return sale;
  }

  Future<void> deleteSaleQuotation(String id) async {
    requirePermission(AppPermission.quotationsManage);
    final index = _saleQuotations.indexWhere((item) => item.id == id);
    if (index == -1) return;
    final now = DateTime.now();
    final deleted = _withSyncMeta<SaleQuotation>(
      _saleQuotations[index].copyWith(deletedAt: now, updatedAt: now),
      now,
    );
    _saleQuotations[index] = deleted;
    _recordSyncChange(
      entityType: 'sale_quotation',
      entityId: id,
      operation: 'delete',
      payload: deleted.toJson(),
    );
    await _saveDirty(saleQuotations: true, sync: true);
    notifyListeners();
  }

  DeliveryNote? deliveryNoteForSale(String saleId) {
    _ensureDeliveryNoteLookupCache();
    return _cachedDeliveryNoteBySaleId?[saleId];
  }

  Future<DeliveryNote> createDeliveryNoteFromSale(
    String saleId, {
    String note = '',
  }) async {
    requirePermission(AppPermission.deliveryNotesManage);
    final saleIndex = _sales.indexWhere((item) => item.id == saleId);
    final sale =
        saleIndex == -1 ? await _saleByIdFromSqlite(saleId) : _sales[saleIndex];
    if (sale == null) throw ArgumentError('Sale not found.');
    if (sale.isDeleted) throw StateError('Sale is deleted.');
    if (sale.isCancelled) {
      throw StateError(
        'Cannot create a delivery note for a cancelled or returned sale.',
      );
    }
    final existing = deliveryNoteForSale(saleId);
    if (existing != null) return existing;
    final now = DateTime.now();
    final deliveryNote = DeliveryNote(
      id: '${now.microsecondsSinceEpoch}-delivery',
      deliveryNo:
          'DLV-$_invoiceDevicePrefix-${(_deliveryNotes.where((item) => !item.isDeleted).length + 1).toString().padLeft(6, '0')}',
      saleId: sale.id,
      invoiceNo: sale.invoiceNo,
      customerName: sale.customerName,
      customerId: sale.customerId,
      date: now,
      status: 'Draft',
      items: sale.items,
      note: note.trim(),
      createdAt: now,
      updatedAt: now,
      deviceId: _deviceId,
      syncStatus: 'pending',
      storeId: appIdentity.storeId,
      branchId: appIdentity.branchId,
      version: 1,
      lastModifiedByDeviceId: _deviceId,
    );
    _deliveryNotes.add(deliveryNote);
    _recordSyncChange(
      entityType: 'delivery_note',
      entityId: deliveryNote.id,
      operation: 'create',
      payload: deliveryNote.toJson(),
    );
    await _saveDirty(deliveryNotes: true, sync: true);
    _touchDataRevisions(deliveryNotes: true);
    _invalidateDerivedDataCaches();
    notifyListeners();
    return deliveryNote;
  }

  Future<void> markDeliveryNoteDelivered(String id) async {
    requirePermission(AppPermission.deliveryNotesManage);
    final index = _deliveryNotes.indexWhere((item) => item.id == id);
    if (index == -1) throw ArgumentError('Delivery note not found.');
    final current = _deliveryNotes[index];
    if (current.isDeleted || current.isDelivered) return;
    final now = DateTime.now();
    final updated = _withSyncMeta<DeliveryNote>(
      current.copyWith(status: 'Delivered', deliveredAt: now, updatedAt: now),
      now,
    );
    _deliveryNotes[index] = updated;
    _recordSyncChange(
      entityType: 'delivery_note',
      entityId: id,
      operation: 'deliver',
      payload: updated.toJson(),
    );
    await _saveDirty(deliveryNotes: true, sync: true);
    _touchDataRevisions(deliveryNotes: true);
    _invalidateDerivedDataCaches();
    notifyListeners();
  }

  Future<void> deleteDeliveryNote(String id) async {
    requirePermission(AppPermission.deliveryNotesManage);
    final index = _deliveryNotes.indexWhere((item) => item.id == id);
    if (index == -1) return;
    final now = DateTime.now();
    final deleted = _withSyncMeta<DeliveryNote>(
      _deliveryNotes[index].copyWith(deletedAt: now, updatedAt: now),
      now,
    );
    _deliveryNotes[index] = deleted;
    _recordSyncChange(
      entityType: 'delivery_note',
      entityId: id,
      operation: 'delete',
      payload: deleted.toJson(),
    );
    await _saveDirty(deliveryNotes: true, sync: true);
    _touchDataRevisions(deliveryNotes: true);
    _invalidateDerivedDataCaches();
    notifyListeners();
  }
}
