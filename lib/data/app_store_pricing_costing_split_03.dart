part of 'app_store.dart';

extension _AppStoreSplitPricingCostingPart3 on AppStore {
  InventoryCostResult _resolveCostForSaleItem(SaleItem item, DateTime now) {
    final product = _findProductById(item.productId);
    final cost = _productCostFor(item.productId);
    if (_inventoryCostingMethod == InventoryCostingMethod.lastPurchaseCost) {
      return InventoryCostResult(
        method: _inventoryCostingMethod,
        unitCost: cost.lastCost > 0 ? cost.lastCost : (product?.usdCost ?? 0),
      );
    }
    if (_inventoryCostingMethod == InventoryCostingMethod.fifo) {
      var qtyToConsume = item.effectiveBaseQuantity;
      final consumptions = <InventoryCostLayerConsumption>[];
      final indexes = <int>[];
      for (var i = 0; i < _inventoryCostLayers.length; i += 1) {
        final layer = _inventoryCostLayers[i];
        if (layer.productId == item.productId &&
            !layer.isClosed &&
            layer.quantityRemaining > 0) {
          indexes.add(i);
        }
      }
      indexes.sort((a, b) => _inventoryCostLayers[a]
          .createdAt
          .compareTo(_inventoryCostLayers[b].createdAt));
      for (final index in indexes) {
        if (qtyToConsume <= 0) break;
        final layer = _inventoryCostLayers[index];
        final consumed = min(qtyToConsume, layer.quantityRemaining);
        if (consumed <= 0) continue;
        consumptions.add(InventoryCostLayerConsumption(
          layerId: layer.id,
          quantity: consumed,
          unitCost: layer.unitCost,
          currencyCode: layer.currencyCode,
        ));
        final remaining = layer.quantityRemaining - consumed;
        _inventoryCostLayers[index] = layer.copyWith(
          quantityRemaining: remaining,
          isClosed: remaining <= 0,
          updatedAt: now,
        );
        qtyToConsume -= consumed;
      }
      if (qtyToConsume > 0) {
        final fallbackCost = cost.averageCost > 0
            ? cost.averageCost
            : (cost.lastCost > 0 ? cost.lastCost : (product?.usdCost ?? 0));
        if (fallbackCost > 0) {
          consumptions.add(InventoryCostLayerConsumption(
            layerId:
                'negative_stock_${item.productId}_${now.microsecondsSinceEpoch}',
            quantity: qtyToConsume,
            unitCost: fallbackCost,
            currencyCode: 'USD',
          ));
        }
      }
      final totalQty =
          item.effectiveBaseQuantity <= 0 ? 0 : item.effectiveBaseQuantity;
      final totalCost =
          consumptions.fold<double>(0, (sum, entry) => sum + entry.totalCost);
      final unitCost = totalQty <= 0 ? 0.0 : totalCost / totalQty;
      return InventoryCostResult(
        method: _inventoryCostingMethod,
        unitCost: unitCost,
        consumptions: consumptions,
      );
    }
    return InventoryCostResult(
      method: _inventoryCostingMethod,
      unitCost:
          cost.averageCost > 0 ? cost.averageCost : (product?.usdCost ?? 0),
    );
  }

  Future<InventoryCostResult> _resolveCostForSaleItemInTransaction(
    VentioDriftDatabase db,
    SaleItem item,
    DateTime now,
  ) async {
    final product = _findProductById(item.productId);
    final cost = _productCostFor(item.productId);
    final providedUnitCost = item.unitCost > 0 ? item.unitCost : 0.0;

    double fallbackCost() {
      if (providedUnitCost > 0) return providedUnitCost;
      if (_inventoryCostingMethod == InventoryCostingMethod.lastPurchaseCost &&
          cost.lastCost > 0) {
        return cost.lastCost;
      }
      if (cost.averageCost > 0) return cost.averageCost;
      if (cost.lastCost > 0) return cost.lastCost;
      return product?.usdCost ?? 0.0;
    }

    if (product == null || !product.trackStock) {
      return InventoryCostResult(
        method: _inventoryCostingMethod,
        unitCost: fallbackCost(),
      );
    }

    if (_inventoryCostingMethod != InventoryCostingMethod.fifo) {
      return InventoryCostResult(
        method: _inventoryCostingMethod,
        unitCost: fallbackCost(),
      );
    }

    var qtyToConsume = item.effectiveBaseQuantity;
    final consumptions = <InventoryCostLayerConsumption>[];
    final layers = (await BusinessSqliteStore.readInventoryCostLayers(db))
        .where((layer) =>
            layer.productId == item.productId &&
            layer.quantityRemaining > 0.000001)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    for (final layer in layers) {
      if (qtyToConsume <= 0.000001) break;
      final consumed = min(qtyToConsume, layer.quantityRemaining);
      if (consumed <= 0.000001) continue;
      consumptions.add(InventoryCostLayerConsumption(
        layerId: layer.id,
        quantity: consumed,
        unitCost: layer.unitCost,
        currencyCode: layer.currencyCode,
      ));
      final remaining = max(0.0, layer.quantityRemaining - consumed);
      // inventory_cost_layers is the authoritative FIFO valuation table. Consume
      // the exact layer directly inside the outer sale transaction instead of
      // round-tripping through the generic entity upsert path. Besides being
      // atomic with stock/batch/accounting posting, the optimistic quantity
      // predicate prevents a stale layer snapshot from overwriting a concurrent
      // change.
      final changed = await db.customUpdate(
        r'''
        UPDATE inventory_cost_layers
        SET quantity_remaining = ?,
            is_closed = ?,
            updated_at = ?
        WHERE id = ?
          AND deleted_at = ''
          AND ABS(quantity_remaining - ?) <= 0.000001
        ''',
        variables: <Variable<Object>>[
          Variable<double>(remaining),
          Variable<int>(remaining <= 0.000001 ? 1 : 0),
          Variable<String>(now.toUtc().toIso8601String()),
          Variable<String>(layer.id),
          Variable<double>(layer.quantityRemaining),
        ],
      );
      if (changed != 1) {
        throw StateError(
          'FIFO layer ${layer.id} changed before sale consumption could be committed safely.',
        );
      }
      final persisted = await db.customSelect(
        r'''
        SELECT quantity_remaining
        FROM inventory_cost_layers
        WHERE id = ? AND deleted_at = ''
        LIMIT 1
        ''',
        variables: <Variable<Object>>[Variable<String>(layer.id)],
      ).getSingleOrNull();
      final persistedRemaining =
          (persisted?.data['quantity_remaining'] as num? ?? double.nan)
              .toDouble();
      if (!persistedRemaining.isFinite ||
          (persistedRemaining - remaining).abs() > 0.000001) {
        throw StateError(
          'FIFO layer ${layer.id} consumption was not persisted atomically.',
        );
      }
      qtyToConsume -= consumed;
    }

    if (qtyToConsume > 0.000001) {
      if (!_storeProfile.allowNegativeStock) {
        throw StateError(
          'FIFO cost layers are insufficient for ${product.name}. Reconcile inventory costing before completing the sale.',
        );
      }
      final fallback = fallbackCost();
      consumptions.add(InventoryCostLayerConsumption(
        layerId:
            'negative_stock_${item.productId}_${now.microsecondsSinceEpoch}',
        quantity: qtyToConsume,
        unitCost: fallback,
        currencyCode: 'USD',
      ));
    }

    final totalQty = item.effectiveBaseQuantity;
    final totalCost =
        consumptions.fold<double>(0, (sum, entry) => sum + entry.totalCost);
    return InventoryCostResult(
      method: _inventoryCostingMethod,
      unitCost: totalQty <= 0 ? 0.0 : totalCost / totalQty,
      consumptions: consumptions,
    );
  }

  Future<void> _restoreInventoryCostLayersFromSaleItemsInTransaction(
    VentioDriftDatabase db,
    Iterable<SaleItem> items,
    DateTime now, {
    required DateTime originalSaleDate,
    required String restorationSourceType,
    required String restorationSourceId,
    bool preserveSaleProductIds = false,
  }) async {
    final materialized = items.toList(growable: false);
    if (materialized.isEmpty ||
        _inventoryCostingMethod != InventoryCostingMethod.fifo) {
      return;
    }
    final layers = await BusinessSqliteStore.readInventoryCostLayers(db);
    final byId = <String, InventoryCostLayer>{
      for (final layer in layers) layer.id: layer,
    };
    // A return/cancellation may refer to FIFO consumptions from an older FIFO
    // era. After switching away from FIFO and back, those historical layers
    // have already been rebased into the current opening layer and must not be
    // resurrected. Determine the boundary from actual method transitions after
    // the sale, rather than from the newest open FIFO row: older builds could
    // leave duplicate/open FIFO history rows that are not real transitions.
    final saleBelongsToCurrentFifoPeriod =
        _saleBelongsToCurrentFifoPeriod(originalSaleDate);

    for (var itemIndex = 0; itemIndex < materialized.length; itemIndex += 1) {
      final item = materialized[itemIndex];
      final canRestoreOriginalLayers = saleBelongsToCurrentFifoPeriod &&
          item.costingMethodAtSale == InventoryCostingMethod.fifo &&
          item.costLayerConsumptions.isNotEmpty &&
          item.costLayerConsumptions.every((consumption) {
            if (consumption.layerId.startsWith('negative_stock_') ||
                consumption.layerId.startsWith('negative_stock:')) {
              return false;
            }
            return byId.containsKey(consumption.layerId);
          });

      if (!canRestoreOriginalLayers) {
        final qty = item.effectiveBaseQuantity;
        if (qty <= 0.000001) continue;
        final layer = InventoryCostLayer(
          id: '$restorationSourceType-$restorationSourceId-${item.productId}-$itemIndex',
          productId: preserveSaleProductIds
              ? item.productId
              : _operationalProductIdForStorage(item.productId),
          productName: item.productName,
          quantityReceived: qty,
          quantityRemaining: qty,
          unitCost: max(0.0, item.unitCostPerBase),
          currencyCode: 'USD',
          exchangeRate: 1,
          sourceType: restorationSourceType,
          sourceId: restorationSourceId,
          createdAt: now,
          updatedAt: now,
        );
        await BusinessSqliteStore.upsertEntityPayloads(
          db,
          AppStore._inventoryCostLayersKey,
          <Map<String, dynamic>>[layer.toJson()],
          sortIndices: const <int?>[0],
        );
        byId[layer.id] = layer;
        continue;
      }

      for (final consumption in item.costLayerConsumptions) {
        if (consumption.layerId.startsWith('negative_stock_') ||
            consumption.layerId.startsWith('negative_stock:')) {
          continue;
        }
        final layer = byId[consumption.layerId];
        if (layer == null) {
          throw StateError(
            'Historical FIFO layer ${consumption.layerId} is missing for ${item.productName}.',
          );
        }
        final changed = await db.customUpdate(
          r'''
          UPDATE inventory_cost_layers
          SET quantity_remaining = quantity_remaining + ?,
              is_closed = 0,
              updated_at = ?
          WHERE id = ? AND deleted_at = ''
            AND quantity_remaining + ? <= quantity_received + 0.000001
          ''',
          variables: <Variable<Object>>[
            Variable<double>(consumption.quantity),
            Variable<String>(now.toUtc().toIso8601String()),
            Variable<String>(consumption.layerId),
            Variable<double>(consumption.quantity),
          ],
        );
        if (changed != 1) {
          throw StateError(
            'FIFO layer ${consumption.layerId} could not be restored safely for ${item.productName}.',
          );
        }
        final refreshed = await db.customSelect(
          r'''
          SELECT quantity_received, quantity_remaining
          FROM inventory_cost_layers
          WHERE id = ? AND deleted_at = ''
          LIMIT 1
          ''',
          variables: <Variable<Object>>[
            Variable<String>(consumption.layerId),
          ],
        ).getSingleOrNull();
        if (refreshed == null) {
          throw StateError(
            'FIFO layer ${consumption.layerId} disappeared during restoration.',
          );
        }
        final received =
            (refreshed.data['quantity_received'] as num? ?? 0).toDouble();
        final remaining =
            (refreshed.data['quantity_remaining'] as num? ?? 0).toDouble();
        if (remaining > received + 0.000001) {
          throw StateError(
            'FIFO layer ${consumption.layerId} was restored above its received quantity.',
          );
        }
        byId[consumption.layerId] = layer.copyWith(
          quantityRemaining: remaining,
          isClosed: remaining <= 0.000001,
          updatedAt: now,
        );
      }
    }
  }

  Future<void> _closeInventoryCostLayersForPurchaseInTransaction(
    VentioDriftDatabase db,
    Purchase purchase,
    DateTime now,
  ) async {
    final purchaseLayers =
        (await BusinessSqliteStore.readInventoryCostLayers(db))
            .where((layer) => layer.purchaseId == purchase.id)
            .toList(growable: false);
    if (purchaseLayers.isEmpty) return;

    final versionSuffix = '-cost-layer-v${purchase.version}';
    final versionLayers = purchaseLayers
        .where((layer) => layer.id.endsWith(versionSuffix))
        .toList(growable: false);
    final activeLayers =
        versionLayers.isNotEmpty ? versionLayers : purchaseLayers;
    final fifoBasis = _inventoryCostingMethod == InventoryCostingMethod.fifo
        ? _currentOpenFifoEffectiveFrom()
        : null;
    if (fifoBasis != null &&
        activeLayers.any((layer) => layer.createdAt.isBefore(fifoBasis))) {
      throw StateError(
        'Cannot reverse a purchase that predates the current FIFO opening basis. Reverse it before changing costing method, or use a documented inventory adjustment.',
      );
    }

    final consumed = activeLayers.any(
        (layer) => layer.quantityRemaining + 0.000001 < layer.quantityReceived);
    if (consumed) {
      throw StateError(
        'Cannot reverse this purchase after its inventory cost layers have been consumed. Return/cancel the downstream sale or movement first.',
      );
    }

    // The current-version layers are the authority for the consumption guard.
    // Once that guard passes, the purchase reversal must close every persisted
    // layer linked to the purchase directly in SQLite. Do not round-trip these
    // rows through the generic entity upsert path: inventory_cost_layers is an
    // accounting/valuation authority and the reversal must be atomic with the
    // stock/batch reversal that follows in the same outer transaction.
    await db.customUpdate(
      r'''
      UPDATE inventory_cost_layers
      SET quantity_remaining = 0,
          is_closed = 1,
          updated_at = ?
      WHERE purchase_id = ?
        AND deleted_at = ''
      ''',
      variables: <Variable<Object>>[
        Variable<String>(now.toUtc().toIso8601String()),
        Variable<String>(purchase.id),
      ],
    );

    // Read back the authoritative table before allowing the outer transaction
    // to continue. A returned/cancelled purchase must never leave a ghost FIFO
    // balance behind, even if historical receive/repost versions exist.
    final residual = await db.customSelect(
      r'''
      SELECT COALESCE(SUM(quantity_remaining), 0) AS qty
      FROM inventory_cost_layers
      WHERE purchase_id = ?
        AND deleted_at = ''
      ''',
      variables: <Variable<Object>>[Variable<String>(purchase.id)],
    ).getSingle();
    final residualQuantity = (residual.data['qty'] as num? ?? 0).toDouble();
    if (residualQuantity.abs() > 0.000001) {
      throw StateError(
        'Purchase ${purchase.purchaseNo} cost layers did not close atomically; remaining quantity: $residualQuantity.',
      );
    }
  }

  Future<_ManufacturingCostResolution> _consumeManufacturingCostInTransaction(
    VentioDriftDatabase db, {
    required Product product,
    required double quantity,
    required String orderId,
    required DateTime now,
  }) async {
    if (quantity <= 0) {
      throw ArgumentError('Actual manufacturing consumption must be positive.');
    }
    final productCost = _productCostFor(product.id);
    double fallbackCost() {
      if (_inventoryCostingMethod == InventoryCostingMethod.lastPurchaseCost &&
          productCost.lastCost > 0) {
        return productCost.lastCost;
      }
      if (productCost.averageCost > 0) return productCost.averageCost;
      if (productCost.lastCost > 0) return productCost.lastCost;
      return _safeUsdCost(product);
    }

    if (_inventoryCostingMethod != InventoryCostingMethod.fifo) {
      final unitCost = fallbackCost();
      if (!unitCost.isFinite || unitCost < 0) {
        throw StateError('Invalid inventory cost for ${product.name}.');
      }
      return _ManufacturingCostResolution(
        unitCost: unitCost,
        totalCost: quantity * unitCost,
      );
    }

    final layers = (await BusinessSqliteStore.readInventoryCostLayers(db))
        .where((layer) =>
            layer.productId == product.id &&
            !layer.isClosed &&
            layer.quantityRemaining > 0)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    var remaining = quantity;
    var total = 0.0;
    final snapshots = <Map<String, dynamic>>[];
    for (final layer in layers) {
      if (remaining <= 0.000001) break;
      final consumed = min(remaining, layer.quantityRemaining);
      if (consumed <= 0) continue;
      total += consumed * layer.unitCost;
      snapshots.add(<String, dynamic>{
        'layerId': layer.id,
        'quantity': consumed,
        'unitCost': layer.unitCost,
        'currencyCode': layer.currencyCode,
        'orderId': orderId,
      });
      final nextRemaining = layer.quantityRemaining - consumed;
      final updated = layer.copyWith(
        quantityRemaining: nextRemaining,
        isClosed: nextRemaining <= 0.000001,
        updatedAt: now,
      );
      await BusinessSqliteStore.upsertEntityPayloads(
        db,
        AppStore._inventoryCostLayersKey,
        <Map<String, dynamic>>[updated.toJson()],
        sortIndices: const <int?>[0],
      );
      remaining -= consumed;
    }
    if (remaining > 0.000001) {
      final fallback = fallbackCost();
      if (!_storeProfile.allowNegativeStock) {
        throw StateError(
            'FIFO cost layers are insufficient for ${product.name}. Reconcile inventory costing before completing manufacturing.');
      }
      total += remaining * fallback;
      snapshots.add(<String, dynamic>{
        'layerId': 'negative_stock:${product.id}:$orderId',
        'quantity': remaining,
        'unitCost': fallback,
        'currencyCode': 'USD',
        'orderId': orderId,
      });
    }
    return _ManufacturingCostResolution(
      unitCost: total / quantity,
      totalCost: total,
      layerConsumptions: snapshots,
    );
  }

  void _restoreInventoryCostLayersFromSaleItem(SaleItem item, DateTime now) {
    if (item.costLayerConsumptions.isEmpty) return;
    for (final consumption in item.costLayerConsumptions) {
      final index = _inventoryCostLayers
          .indexWhere((layer) => layer.id == consumption.layerId);
      if (index == -1) continue;
      final layer = _inventoryCostLayers[index];
      final remaining = layer.quantityRemaining + consumption.quantity;
      _inventoryCostLayers[index] = layer.copyWith(
        quantityRemaining: remaining,
        isClosed: false,
        updatedAt: now,
      );
    }
  }

  void _closeInventoryCostLayersForPurchase(String purchaseId, DateTime now) {
    for (var i = 0; i < _inventoryCostLayers.length; i += 1) {
      final layer = _inventoryCostLayers[i];
      if (layer.purchaseId != purchaseId) continue;
      _inventoryCostLayers[i] = layer.copyWith(
        quantityRemaining: 0,
        isClosed: true,
        updatedAt: now,
      );
    }
  }
}
