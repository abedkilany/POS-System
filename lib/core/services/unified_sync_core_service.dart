import '../../data/app_store.dart';
import '../repositories/business_repositories.dart';
import '../storage/sqlite/business_sqlite_store.dart';
import '../../models/catalog_item.dart';
import '../../models/delivery_note.dart';
import '../../models/manufacturing.dart';
import '../../models/sale_quotation.dart';
import '../../models/supplier_product_price.dart';
import '../../models/sync_change.dart';
import 'sync_diagnostics_log.dart';

/// Transport-independent Host-authority sync logic.
///
/// LAN and Cloud should keep only their network/HTTP details locally. Shared
/// rules such as pending queue selection, Host acceptance, stale reset
/// protection, echo filtering, applying authoritative changes, and ACK handling
/// live here so a sync bug is fixed once for both transports.
class UnifiedSyncCoreService {
  UnifiedSyncCoreService(this.store);

  final AppStore store;

  Future<List<SyncChange>> pendingChangesForTarget(
    String target, {
    int? limit,
  }) {
    return store.syncState.pendingSyncChangesForTarget(
      store,
      target,
      limit: limit,
    );
  }

  List<String> changeIds(Iterable<SyncChange> changes) {
    return changes.map((item) => item.id).toList();
  }

  Future<void> markPushInProgress(Iterable<String> changeIds) {
    return store.syncState.markSyncQueueChangesInProgress(store, changeIds);
  }

  Future<void> markPushSubmitted(Iterable<String> ackIds,
      {Iterable<String> fallbackIds = const <String>[]}) {
    final ids = ackIds.isEmpty ? fallbackIds : ackIds;
    return store.syncState.markSyncChangesSubmittedByIds(store, ids);
  }

  Future<void> markPushAcknowledged(Iterable<String> ackIds,
      {Iterable<String> fallbackIds = const <String>[]}) {
    final ids = ackIds.isEmpty ? fallbackIds : ackIds;
    return store.syncState.markSyncChangesSyncedByIds(store, ids);
  }

  Future<void> markPushFailed(Iterable<String> changeIds, String message) {
    return store.syncState.markSyncQueueChangesFailed(
      store,
      changeIds,
      message,
    );
  }

  Future<List<SyncChange>> submittedChangesForTarget(String target) {
    return store.syncState.submittedSyncChangesForTarget(store, target);
  }

  Future<void> markPushRejected(Map<String, String> rejected) {
    return store.syncState.markSyncChangesRejectedByIds(store, rejected);
  }

  List<SyncChange> decodeRemoteChanges(List<dynamic>? raw) {
    return (raw ?? const <dynamic>[])
        .map((item) =>
            SyncChange.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  List<SyncChange> filterOutLocalEchoes(Iterable<SyncChange> changes) {
    final list = changes.toList();
    final filtered =
        list.where((item) => item.deviceId != store.deviceId).toList();
    if (list.length != filtered.length) {
      SyncDiagnosticsLog.add(
        '[SYNC_TRACE] core:echoFilter input=${list.length} output=${filtered.length} '
        'localDevice=${store.deviceId} removed=${list.length - filtered.length}',
      );
      for (final change
          in list.where((item) => item.deviceId == store.deviceId).take(20)) {
        SyncDiagnosticsLog.add(
          '[SYNC_TRACE] core:echoRemoved ${SyncDiagnosticsLog.summarizeChange(change)}',
        );
      }
    }
    return filtered;
  }

  bool containsHostOnlyOperation(Iterable<SyncChange> changes) {
    return changes.any((item) =>
        item.entityType == 'system' && item.operation == 'reset_store_data');
  }

  /// Applies Client drafts on the Host using the same acceptance rules for LAN
  /// and Cloud relay requests.
  Future<HostAcceptedChanges> acceptClientChangesOnHost(
    Iterable<SyncChange> remoteChanges, {
    required bool mirrorToCloud,
    bool verifyApplied = false,
  }) async {
    final received = filterOutLocalEchoes(remoteChanges);
    if (received.isEmpty) {
      return const HostAcceptedChanges(
          ackIds: <String>[],
          accepted: <SyncChange>[],
          discardedBecauseOfReset: 0);
    }

    final latestResetAt = await store.syncState.latestResetSyncAt(store);
    final hostReceivedAt = DateTime.now();
    final rejected = <String, String>{};
    final applicable = <SyncChange>[];
    for (final item in received) {
      if (latestResetAt != null && !item.createdAt.isAfter(latestResetAt)) {
        rejected[item.id] = 'Request is older than the latest Host reset.';
        continue;
      }
      final problem = await validateClientDraftForHostAcceptance(item);
      if (problem != null) {
        rejected[item.id] = problem;
        continue;
      }
      // Put accepted Client drafts on the Host timeline. This avoids a Client
      // with a newer cursor missing an older offline Client change.
      applicable.add(item.copyWith(createdAt: hostReceivedAt));
    }

    if (applicable.isNotEmpty) {
      await store.syncState.applyAuthoritativeSyncChangesToSqliteTransaction(
        store,
        applicable,
        markAppliedAsSynced: true,
        mirrorToCloud: mirrorToCloud,
      );
    }
    if (verifyApplied) {
      await assertRemoteSyncChangesApplied(applicable);
    }

    return HostAcceptedChanges(
      ackIds: applicable.map((item) => item.id).toList(),
      accepted: applicable,
      discardedBecauseOfReset:
          rejected.values.where((item) => item.contains('reset')).length,
      rejected: rejected,
    );
  }

  Future<int> applyAuthoritativeChanges(
    Iterable<SyncChange> remoteChanges, {
    bool cleanupSoftDeleted = false,
  }) async {
    final remoteList = remoteChanges.toList();
    SyncDiagnosticsLog.add(
      '[SYNC_TRACE] core:applyAuthoritative start remote=${remoteList.length} '
      'cleanupSoftDeleted=$cleanupSoftDeleted localDevice=${store.deviceId}',
    );
    for (final change in remoteList.take(40)) {
      SyncDiagnosticsLog.add(
        '[SYNC_TRACE] core:authoritative ${SyncDiagnosticsLog.summarizeChange(change)}',
      );
    }

    // Host confirmation rule: drafts pushed to a relay are only final after
    // the Host republishes them as authoritative changes. If this device is
    // the origin, the matching local queue row is confirmed here instead of
    // being confirmed by the relay ACK.
    await store.syncState.markSyncChangesSyncedByIds(store, remoteList.expand((item) {
      final meta = Map<String, dynamic>.from(
          item.payload['_syncV2'] as Map? ?? const {});
      return <String>[
        item.id,
        (meta['eventId'] ?? '').toString(),
        (meta['requestId'] ?? '').toString(),
        (meta['sourceCommandId'] ?? '').toString(),
      ].where((value) => value.isNotEmpty);
    }));

    final changes = filterOutLocalEchoes(remoteList);
    SyncDiagnosticsLog.add(
      '[SYNC_TRACE] core:applyAuthoritative afterEchoFilter=${changes.length}',
    );
    await store.syncState.applyAuthoritativeSyncChangesToSqliteTransaction(
      store,
      changes,
      markAppliedAsSynced: true,
    );
    if (cleanupSoftDeleted && changes.isNotEmpty) {
      await store.cleanupSoftDeletedRecords();
    }
    SyncDiagnosticsLog.add(
      '[SYNC_TRACE] core:applyAuthoritative done countedApplied=${changes.length}',
    );
    return changes.length;
  }

  Future<String?> validateClientDraftForHostAcceptance(
    SyncChange change,
  ) async {
    if (change.entityType == 'system' &&
        change.operation == 'reset_store_data') {
      return 'Reset data can only be initiated on the Host device.';
    }
    if (change.operation == 'delete') return null;
    final p = change.payload;
    switch (change.entityType) {
      case 'product':
        final code = (p['code'] ?? '').toString().trim();
        final barcode = (p['barcode'] ?? '').toString().trim();
        if (code.isEmpty && barcode.isEmpty) return null;
        final existing =
            await ProductRepository.findByCodeOrBarcode(code.isNotEmpty ? code : barcode);
        if (existing != null && existing.id != change.entityId) {
          return 'Product code or barcode already exists on the Host.';
        }
        return null;
      case 'sale':
        final invoiceNo = (p['invoiceNo'] ?? p['invoice_no'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        if (invoiceNo.isEmpty) return null;
        final sales = await SaleRepository.listAll();
        final duplicate = sales.any(
          (item) =>
              item.id != change.entityId &&
              !item.isDeleted &&
              item.invoiceNo.trim().toLowerCase() == invoiceNo,
        );
        if (duplicate) return 'Invoice number already exists on the Host.';
        return null;
    }
    return null;
  }

  Future<void> assertRemoteSyncChangesApplied(
    List<SyncChange> changes,
  ) async {
    final problems = <String>[];
    for (final change in changes) {
      final problem = await _remoteSyncChangeApplyProblem(change);
      if (problem != null) problems.add('${change.id}: $problem');
    }
    if (problems.isNotEmpty) {
      throw StateError(
        'Remote sync apply verification failed: ${problems.take(5).join('; ')}',
      );
    }
  }

  Future<String?> _remoteSyncChangeApplyProblem(SyncChange change) async {
    if (change.entityType == 'system') return null;

    bool deleteWithoutPayload() =>
        change.operation == 'delete' && change.payload.isEmpty;

    bool existsById<T>(
      Iterable<T> items,
      String Function(T item) idOf,
    ) =>
        items.any((item) => idOf(item) == change.entityId);

    switch (change.entityType) {
      case 'store_profile':
      case 'app_identity':
        return null;
      case 'role':
        return deleteWithoutPayload() ||
                await RoleRepository.getById(change.entityId) != null
            ? null
            : 'role ${change.entityId} was not stored locally';
      case 'user':
        return deleteWithoutPayload() ||
                await UserRepository.getById(change.entityId) != null
            ? null
            : 'user ${change.entityId} was not stored locally';
      case 'product':
        return deleteWithoutPayload() ||
                await ProductRepository.getById(change.entityId) != null
            ? null
            : 'product ${change.entityId} was not stored locally';
      case 'customer':
        return deleteWithoutPayload() ||
                await CustomerRepository.getById(change.entityId) != null
            ? null
            : 'customer ${change.entityId} was not stored locally';
      case 'supplier':
        return deleteWithoutPayload() ||
                await SupplierRepository.getById(change.entityId) != null
            ? null
            : 'supplier ${change.entityId} was not stored locally';
      case 'supplier_product_price':
        return deleteWithoutPayload() ||
                existsById(
                  await InventoryRepository.getSupplierProductPrices() ??
                      const <SupplierProductPrice>[],
                  (item) => item.id,
                )
            ? null
            : 'supplier product price ${change.entityId} was not stored locally';
      case 'expense':
        return deleteWithoutPayload() ||
                await ExpenseRepository.getById(change.entityId) != null
            ? null
            : 'expense ${change.entityId} was not stored locally';
      case 'category':
      case 'brand':
      case 'unit':
        return deleteWithoutPayload() ||
                existsById(
                  await InventoryRepository.getCatalogItems(
                    change.entityType == 'category'
                        ? BusinessSqliteStore.categoriesKey
                        : change.entityType == 'brand'
                            ? BusinessSqliteStore.brandsKey
                            : BusinessSqliteStore.unitsKey,
                  ) ??
                      const <CatalogItem>[],
                  (item) => item.id,
                )
            ? null
            : '${change.entityType} ${change.entityId} was not stored locally';
      case 'sale':
        return deleteWithoutPayload() ||
                await SaleRepository.getById(change.entityId) != null
            ? null
            : 'sale ${change.entityId} was not stored locally';
      case 'sale_quotation':
        return deleteWithoutPayload() ||
                existsById(
                  await SaleRepository.getQuotations() ?? const <SaleQuotation>[],
                  (item) => item.id,
                )
            ? null
            : 'sale quotation ${change.entityId} was not stored locally';
      case 'delivery_note':
        return deleteWithoutPayload() ||
                existsById(
                  await SaleRepository.getDeliveryNotes() ?? const <DeliveryNote>[],
                  (item) => item.id,
                )
            ? null
            : 'delivery note ${change.entityId} was not stored locally';
      case 'bill_of_materials':
        return deleteWithoutPayload() ||
                existsById(
                  await InventoryRepository.getBillOfMaterials() ??
                      const <BillOfMaterials>[],
                  (item) => item.id,
                )
            ? null
            : 'BOM ${change.entityId} was not stored locally';
      case 'manufacturing_order':
        return deleteWithoutPayload() ||
                existsById(
                  await InventoryRepository.getManufacturingOrders() ??
                      const <ManufacturingOrder>[],
                  (item) => item.id,
                )
            ? null
            : 'manufacturing order ${change.entityId} was not stored locally';
      case 'purchase':
        return deleteWithoutPayload() ||
                await PurchaseRepository.getById(change.entityId) != null
            ? null
            : 'purchase ${change.entityId} was not stored locally';
      case 'account_transaction':
        return deleteWithoutPayload() ||
                await AccountTransactionRepository.listAll().then(
                  (items) => existsById(items, (item) => item.id),
                )
            ? null
            : 'account transaction ${change.entityId} was not stored locally';
      case 'stock_movement':
        return existsById(
          await StockMovementRepository.listAll(),
          (item) => item.id,
        )
            ? null
            : 'stock movement ${change.entityId} was not stored locally';
    }
    return null;
  }
}

class HostAcceptedChanges {
  const HostAcceptedChanges({
    required this.ackIds,
    required this.accepted,
    required this.discardedBecauseOfReset,
    this.rejected = const <String, String>{},
  });

  final List<String> ackIds;
  final List<SyncChange> accepted;
  final int discardedBecauseOfReset;
  final Map<String, String> rejected;
}
