part of 'app_store.dart';

extension _AppStoreSplitPurchasesPart5 on AppStore {
  Future<Purchase> editPurchaseReturn({
    required String purchaseId,
    required int expectedVersion,
    required String supplierId,
    required String supplierName,
    required List<PurchaseItem> items,
    String warehouseId = '',
    String warehouseName = '',
  }) async {
    requirePermission(AppPermission.purchasesManage);
    requirePermission(AppPermission.purchasesCancel);
    requireSensitiveActionAuthorization(SensitiveAction.purchaseReverse);
    if (items.isEmpty) {
      throw ArgumentError('Purchase return must contain at least one item.');
    }
    for (final item in items) {
      if (item.quantity <= 0 ||
          item.conversionToBase <= 0 ||
          item.unitCost < 0 ||
          !item.quantity.isFinite ||
          !item.conversionToBase.isFinite ||
          !item.unitCost.isFinite) {
        throw ArgumentError('Invalid purchase return item values.');
      }
      if (_findProductById(item.productId) == null) {
        throw ArgumentError('Product not found: ${item.productName}');
      }
    }
    final db = SqliteMigrationManager.database;
    if (!LocalDatabaseService.isSqliteAuthoritative || db == null) {
      throw StateError(
        'Editing a returned purchase requires the authoritative SQLite store.',
      );
    }
    final normalizedPurchaseId = purchaseId.trim();
    if (normalizedPurchaseId.isEmpty) {
      throw ArgumentError('Purchase id is required.');
    }
    await _waitForPendingPurchaseAccounting(normalizedPurchaseId);

    final legacyDefaultVatRatePercent =
        await AccountingService.readDefaultVatRatePercent();
    final taxProfileIdByProductId = <String, String>{
      for (final product in _products) product.id: product.taxProfileId,
    };
    final stockService = StockTransactionService(
      db,
      deviceId: _deviceId,
      defaultStoreId: appIdentity.storeId,
      defaultBranchId: appIdentity.branchId,
      defaultSyncTarget: _stockTransactionSyncTarget,
      allowNegativeStockResolver: (_, __) => false,
    );
    final batchService = BatchInventoryService(db);
    late Purchase authoritative;
    late Purchase stagedReceived;
    late Purchase returned;
    late List<PurchaseItem> normalizedItems;
    var repostMovements = <StockMovement>[];
    final affectedProductIds = <String>{};
    final now = DateTime.now();
    DateTime? originalReceiptAt;

    await db.transaction(() async {
      final pipeline = PostedDocumentEditPipeline<Purchase>(
        loadAuthoritative: () async {
          final current = await _purchaseByIdFromSqlite(normalizedPurchaseId);
          if (current == null) throw StateError('Purchase was not found.');
          authoritative = current;
          return current;
        },
        validatePermission: (_) async {
          requirePermission(AppPermission.purchasesManage);
          requirePermission(AppPermission.purchasesCancel);
        },
        validateVersion: (current) async {
          if (current.version != expectedVersion) {
            throw StateError(
              'Purchase return changed by another user. Reload it before editing.',
            );
          }
        },
        validateDependencies: (current) async {
          if (!current.isReturned || !current.reversalApplied) {
            throw StateError(
                'Only a fully posted purchase return can be edited.');
          }
          await _requireNoActiveJournalInTransaction(
            db,
            referenceType: 'purchase',
            referenceId: current.id,
            includePurchaseEditFamily: true,
            failureMessage:
                'The returned purchase still has an active purchase journal and cannot be edited safely.',
          );
          final activeReceiptRow = await db.customSelect(
            '''
            SELECT COUNT(*) AS count
            FROM stock_movements sm
            WHERE sm.reference_id = ?
              AND sm.movement_type = 'purchase_receive'
              AND sm.deleted_at = ''
              AND NOT EXISTS (
                SELECT 1 FROM stock_movements reversal
                WHERE reversal.reversal_of_movement_id = sm.id
                  AND reversal.deleted_at = ''
              )
            ''',
            variables: <Variable<Object>>[
              Variable<String>(current.id),
            ],
          ).getSingle();
          if ((activeReceiptRow.data['count'] as num? ?? 0).toInt() > 0) {
            throw StateError(
              'The purchase return has an active stock receipt and must be repaired before editing.',
            );
          }
          final receiptDateRow = await db.customSelect(
            '''
            SELECT movement_date
            FROM stock_movements
            WHERE reference_id = ?
              AND movement_type = 'purchase_receive'
              AND deleted_at = ''
            ORDER BY movement_date ASC, created_at ASC
            LIMIT 1
            ''',
            variables: <Variable<Object>>[
              Variable<String>(current.id),
            ],
          ).getSingleOrNull();
          originalReceiptAt = DateTime.tryParse(
            receiptDateRow?.data['movement_date']?.toString() ?? '',
          );

          final requestedSupplierId = supplierId.trim();
          if (requestedSupplierId.isEmpty) {
            throw ArgumentError('Supplier is required.');
          }
          final supplierChanged =
              requestedSupplierId != current.supplierId.trim();
          if (supplierChanged) {
            final settlementRow = await db.customSelect(
              '''
              SELECT
                (SELECT COUNT(*)
                 FROM payment_allocations pa
                 INNER JOIN payment_vouchers pv ON pv.id = pa.voucher_id
                 WHERE pa.reference_type = 'purchase'
                   AND pa.reference_id = ?
                   AND pa.deleted_at = '' AND pa.status = 'active'
                   AND pv.deleted_at = '' AND pv.status = 'posted') AS allocations,
                (SELECT COUNT(*)
                 FROM cash_ledger_transactions refund_tx
                 WHERE refund_tx.reference_type = 'purchase_refund'
                   AND (refund_tx.reference_id = ? OR refund_tx.reference_id LIKE ?)
                   AND refund_tx.deleted_at = ''
                   AND NOT EXISTS (
                     SELECT 1 FROM cash_ledger_transactions reversal_tx
                     WHERE reversal_tx.reversal_of_id = refund_tx.id
                       AND reversal_tx.deleted_at = ''
                   )) AS refunds
              ''',
              variables: <Variable<Object>>[
                Variable<String>(current.id),
                Variable<String>(current.id),
                Variable<String>('${current.id}:%'),
              ],
            ).getSingle();
            final allocations =
                (settlementRow.data['allocations'] as num? ?? 0).toInt();
            final refunds =
                (settlementRow.data['refunds'] as num? ?? 0).toInt();
            if (current.paidAmount > 0.000001 ||
                allocations > 0 ||
                refunds > 0) {
              throw StateError(
                'Cannot change the supplier of a returned purchase with payment/refund history. Reverse those settlements first.',
              );
            }
          }

          final existingLineIds = current.items
              .map((item) => item.lineId.trim())
              .where((value) => value.isNotEmpty)
              .toSet();
          final usedLineIds = <String>{};
          normalizedItems = items.indexed.map((entry) {
            final item = entry.$2;
            final requestedLineId = item.lineId.trim();
            if (requestedLineId.isNotEmpty &&
                existingLineIds.contains(requestedLineId) &&
                usedLineIds.add(requestedLineId)) {
              return item;
            }
            var generatedLineId =
                '${current.id}:prl:v${current.version + 1}:${entry.$1}:${now.microsecondsSinceEpoch}';
            var suffix = 0;
            while (!usedLineIds.add(generatedLineId)) {
              suffix += 1;
              generatedLineId =
                  '${current.id}:prl:v${current.version + 1}:${entry.$1}:${now.microsecondsSinceEpoch}:$suffix';
            }
            return _copyPurchaseItemWith(item: item, lineId: generatedLineId);
          }).toList(growable: false);
          affectedProductIds
            ..addAll(current.items.map((item) => item.productId))
            ..addAll(normalizedItems.map((item) => item.productId));
        },
        reverseOperationalEffects: (_) async {
          // A fully returned purchase has no active stock effect. The integrity
          // checks above prove that state before we rebuild the edited version.
        },
        reverseAccountingEffects: (_) async {
          // The original purchase journal is already reversed by returnPurchase.
          // Rebuild below posts the edited version and reverses it again inside
          // this same transaction, preserving the final Returned state.
        },
        applyChanges: (current) async {
          final resolvedWarehouse =
              resolveWarehouseForPurchase(warehouseId: warehouseId);
          final total = normalizedItems.fold<double>(
            0,
            (sum, item) => sum + item.lineTotal,
          );
          stagedReceived = current.copyWith(
            supplierId: supplierId.trim(),
            supplierName:
                supplierName.trim().isEmpty ? 'Supplier' : supplierName.trim(),
            status: 'Received',
            items: normalizedItems,
            paymentStatus: _receivedPurchasePaymentStatus(
              paidAmount: current.paidAmount,
              total: total,
            ),
            warehouseId: resolvedWarehouse.id,
            warehouseName: warehouseName.trim().isEmpty
                ? resolvedWarehouse.name
                : warehouseName.trim(),
            reversalApplied: false,
            updatedAt: now,
            version: current.version + 1,
            lastModifiedByDeviceId: _deviceId,
            syncStatus: 'pending',
            clearCancelledAt: true,
            clearCancelReason: true,
            clearCancelledByDeviceId: true,
            clearPostedSnapshot: true,
          );
          return stagedReceived;
        },
        rebuildOperationalEffects: (updated) async {
          final ensuredUnifiedCutovers = <String>{};
          final resolvedItems = List<PurchaseItem>.of(updated.items);
          repostMovements = <StockMovement>[];
          for (var lineIndex = 0;
              lineIndex < updated.items.length;
              lineIndex += 1) {
            final item = updated.items[lineIndex];
            final product = _findProductById(item.productId);
            if (product == null) {
              throw StateError('Product ${item.productId} was not found.');
            }
            if (!product.trackStock) continue;
            final targetWarehouse = updated.warehouseId.trim().isEmpty
                ? Warehouse.defaultId
                : updated.warehouseId.trim();
            final allocation = await _receiveUnifiedPurchaseLineInTransaction(
              db,
              batchService: batchService,
              purchase: updated,
              item: item,
              lineIndex: lineIndex,
              product: product,
              warehouseId: targetWarehouse,
              receivedAt: originalReceiptAt ?? authoritative.date,
              inventoryUnitCost: _purchaseInventoryUnitCostPerBase(
                item,
                legacyDefaultVatRatePercent: legacyDefaultVatRatePercent,
              ),
              ensuredCutovers: ensuredUnifiedCutovers,
            );
            resolvedItems[lineIndex] = _copyPurchaseItemWith(
              item: item,
              batchAllocations: <BatchAllocation>[allocation],
            );
            repostMovements.add(StockMovement(
              id: '${updated.id}-${allocation.batchId}-purchase-return-edit-receive-v${updated.version}',
              productId: item.productId,
              productName: item.productName,
              type: 'purchase_receive',
              quantity: allocation.quantity,
              date: now,
              referenceId: updated.id,
              referenceNo: updated.purchaseNo,
              reason: 'Purchase return edited - rebuilt receipt',
              unitCost: allocation.unitCost,
              warehouseId: targetWarehouse,
              warehouseName: updated.warehouseName.trim().isEmpty
                  ? Warehouse.defaultName
                  : updated.warehouseName.trim(),
              batchId: allocation.batchId,
              movementGroupId:
                  '${updated.id}:purchase_return_edit:v${updated.version}:receive',
              documentLineId: _stablePurchaseLineId(updated, item, lineIndex),
              idempotencyKey:
                  '${updated.id}:purchase_return_edit:v${updated.version}:receive:$lineIndex',
              createdAt: now,
              updatedAt: now,
              deviceId: _deviceId,
              syncStatus: 'pending',
              storeId: appIdentity.storeId,
              branchId: appIdentity.branchId,
              version: updated.version,
              lastModifiedByDeviceId: _deviceId,
            ));
          }
          stagedReceived = updated.copyWith(items: resolvedItems);
          if (repostMovements.isNotEmpty) {
            await stockService.recordMovementsInTransaction(
              operationType: 'purchase_return_edit_rebuild',
              documentType: 'purchase',
              documentId: updated.id,
              movementGroupId:
                  '${updated.id}:purchase_return_edit:v${updated.version}:receive',
              idempotencyKey:
                  '${updated.id}:purchase_return_edit:v${updated.version}:receive',
              movements: repostMovements,
              storeId: appIdentity.storeId,
              branchId: appIdentity.branchId,
              deviceId: _deviceId,
            );
            await _assertUnifiedBatchMovementBalancesInTransaction(
              batchService,
              repostMovements,
            );
          }
          return stagedReceived;
        },
        buildPostedSnapshot: (updated) async {
          Supplier? snapshotSupplier;
          for (final candidate in _suppliers) {
            if (candidate.id == updated.supplierId && !candidate.isDeleted) {
              snapshotSupplier = candidate;
              break;
            }
          }
          stagedReceived = updated.copyWith(
            postedSnapshot: PostedDocumentSnapshotService.forPurchase(
              purchase: updated,
              profile: _storeProfile,
              supplier: snapshotSupplier,
              user: _activeUser,
              role: currentUserRole,
              displayedPaidAmount: updated.paidAmount,
              displayedPaymentStatus: updated.paymentStatus,
              taxProfileIdByProductId: taxProfileIdByProductId,
              legacyDefaultVatRatePercent: legacyDefaultVatRatePercent,
            ),
          );
          return stagedReceived;
        },
        repostAccounting: (updated) async {
          final journalReference =
              '${updated.id}:purchase_edit:v${updated.version}:return_rebuild';
          final posted = await AccountingService.recordPurchase(
            updated,
            accountingReferenceId: journalReference,
            paymentPostedSeparately: true,
            withinExistingTransaction: true,
          );
          if (!posted) {
            throw StateError(
              'Purchase return edit accounting rebuild failed; edit rolled back.',
            );
          }
          await _requirePostedJournalInTransaction(
            db,
            referenceType: 'purchase',
            referenceId: journalReference,
            failureMessage:
                'Purchase return edit journal was not persisted; edit rolled back.',
          );
        },
        rebuildDerivedState: (updated) async {
          for (final movement in repostMovements) {
            final product = _findProductById(movement.productId);
            if (product == null) {
              throw StateError('Product ${movement.productId} was not found.');
            }
            if (movement.batchId.trim().isNotEmpty) {
              await batchService.adjustUnifiedBatchInTransaction(
                product: product,
                warehouseId: movement.warehouseId,
                batchId: movement.batchId,
                quantityDelta: -movement.quantity,
                adjustedAt: now,
                storeId: appIdentity.storeId,
                deviceId: _deviceId,
              );
            }
            await stockService.recordReversalInTransaction(
              originalMovement: movement,
              operationType: 'purchase_return_edit',
              documentType: 'purchase',
              documentId: updated.id,
              reason: 'Edited purchase return reposted and returned',
              storeId: appIdentity.storeId,
              branchId: appIdentity.branchId,
              deviceId: _deviceId,
            );
            if (movement.batchId.trim().isNotEmpty) {
              await batchService.assertWarehouseBatchBalanceInTransaction(
                productId: movement.productId,
                warehouseId: movement.warehouseId.trim().isEmpty
                    ? Warehouse.defaultId
                    : movement.warehouseId.trim(),
                storeId: appIdentity.storeId,
              );
            }
          }
          await AccountingService.reversePurchaseEntriesForPurchase(
            purchaseId: updated.id,
            reason: 'Edited purchase return reposted',
            createdBy: _deviceId,
            adjustCashLocationBalance: false,
            notifyChange: false,
            withinExistingTransaction: true,
          );
          await _requireNoActiveJournalInTransaction(
            db,
            referenceType: 'purchase',
            referenceId: updated.id,
            includePurchaseEditFamily: true,
            failureMessage:
                'Purchase return edit journal reversal did not complete; edit rolled back.',
          );

          returned = updated.copyWith(
            status: 'Returned',
            cancelledAt: authoritative.cancelledAt ?? now,
            cancelledByDeviceId:
                authoritative.cancelledByDeviceId.trim().isEmpty
                    ? _deviceId
                    : authoritative.cancelledByDeviceId,
            cancelReason: authoritative.cancelReason,
            reversalApplied: true,
            note: 'Return edited on ${now.toIso8601String()}',
            updatedAt: now,
            deviceId: _deviceId,
            syncStatus: 'pending',
            storeId: appIdentity.storeId,
            branchId: appIdentity.branchId,
            lastModifiedByDeviceId: _deviceId,
          );
          await BusinessSqliteStore.upsertEntityPayloads(
            db,
            AppStore._purchasesKey,
            <Map<String, dynamic>>[returned.toJson()],
            sortIndices: const <int?>[0],
          );

          final rawTotal = returned.items.fold<double>(
            0,
            (sum, item) => sum + item.lineTotal,
          );
          if (returned.supplierId.trim().isNotEmpty) {
            await _persistAccountTransactionInExistingTransaction(
              db,
              AccountTransaction(
                id: '${returned.id}-purchase-invoice',
                accountType: 'supplier',
                accountId: returned.supplierId,
                accountName: returned.supplierName,
                date: returned.date,
                type: 'purchaseInvoice',
                referenceId: returned.id,
                referenceNo: returned.purchaseNo,
                credit: rawTotal,
                note: 'Purchase invoice ${returned.purchaseNo}',
                createdAt: returned.createdAt,
                updatedAt: now,
                deviceId: _deviceId,
                storeId: appIdentity.storeId,
                branchId: appIdentity.branchId,
                lastModifiedByDeviceId: _deviceId,
              ),
            );
            await _persistAccountTransactionInExistingTransaction(
              db,
              AccountTransaction(
                id: '${returned.id}-purchase-return',
                accountType: 'supplier',
                accountId: returned.supplierId,
                accountName: returned.supplierName,
                date: returned.cancelledAt ?? now,
                type: 'purchaseReturn',
                referenceId: returned.id,
                referenceNo: returned.purchaseNo,
                debit: rawTotal,
                note: returned.cancelReason.trim().isEmpty
                    ? 'Purchase return ${returned.purchaseNo}'
                    : returned.cancelReason.trim(),
                createdAt: returned.cancelledAt ?? now,
                updatedAt: now,
                deviceId: _deviceId,
                storeId: appIdentity.storeId,
                branchId: appIdentity.branchId,
                lastModifiedByDeviceId: _deviceId,
              ),
            );
          }
          await _rebuildProductCostsFromUnifiedBatchesInTransaction(
            db,
            productIds: affectedProductIds,
            now: now,
          );
        },
        verifyIntegrity: (_) async {
          final persisted = await _purchaseByIdFromSqlite(authoritative.id);
          if (persisted == null ||
              !persisted.isReturned ||
              !persisted.reversalApplied ||
              persisted.version != authoritative.version + 1) {
            throw StateError(
              'Edited purchase return failed document integrity verification.',
            );
          }
          await _requireNoActiveJournalInTransaction(
            db,
            referenceType: 'purchase',
            referenceId: authoritative.id,
            includePurchaseEditFamily: true,
            failureMessage:
                'Edited purchase return left an active purchase journal.',
          );
          final activeRebuild = await db.customSelect(
            '''
            SELECT COUNT(*) AS count
            FROM stock_movements sm
            WHERE sm.movement_group_id = ?
              AND sm.movement_type = 'purchase_receive'
              AND sm.deleted_at = ''
              AND NOT EXISTS (
                SELECT 1 FROM stock_movements reversal
                WHERE reversal.reversal_of_movement_id = sm.id
                  AND reversal.deleted_at = ''
              )
            ''',
            variables: <Variable<Object>>[
              Variable<String>(
                '${authoritative.id}:purchase_return_edit:v${authoritative.version + 1}:receive',
              ),
            ],
          ).getSingle();
          if ((activeRebuild.data['count'] as num? ?? 0).toInt() != 0) {
            throw StateError(
              'Edited purchase return left an active stock receipt.',
            );
          }
        },
      );
      await pipeline.execute();
    });

    final index = _purchaseIndexForId(returned.id);
    if (index == -1) {
      _putPurchaseAtIndex(returned, _purchases.length);
    } else {
      _putPurchaseAtIndex(returned, index);
    }
    _recordSyncChange(
      entityType: 'purchase',
      entityId: returned.id,
      operation: 'edit_return',
      payload: returned.toJson(),
    );
    await _refreshProductStockCompatibilityCache(affectedProductIds);
    await refreshAfterDatabaseChange(AppStore._productsKey);
    await refreshAfterDatabaseChange(AppStore._productCostsKey);
    await refreshAfterDatabaseChange(AppStore._stockMovementsKey);
    await refreshAccountTransactionsFromSqlite();
    await _saveDirty(sync: true);
    AccountingService.notifyCommittedMutation();
    _touchPurchasesData();
    notifyListeners();
    unawaited(
      AuditLogger.record(
        entityType: 'purchase',
        entityId: returned.id,
        action: 'edit_return',
        summary: 'Purchase return edited',
        details: jsonEncode(returned.toJson()),
        userId: _activeUser?.id ?? '',
        userName: _actorName(),
        storeId: appIdentity.storeId,
        branchId: appIdentity.branchId,
        sessionId: _deviceId,
        traceId: _deviceId,
        deviceId: _deviceId,
        sourceModule: 'purchases',
        isImportant: true,
      ),
    );
    return returned;
  }
}
