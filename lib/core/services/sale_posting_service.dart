import '../../models/account_transaction.dart';
import '../../models/customer.dart';
import '../../models/product.dart';
import '../../models/product_costing.dart';
import '../../models/inventory_cost_layer.dart';
import '../../models/sale.dart';
import '../../models/sale_item.dart';
import '../../models/stock_movement.dart';
import '../../models/user_role.dart';
import '../repositories/business_session_context.dart';
import '../storage/sqlite/business_sqlite_store.dart';
import '../storage/sqlite/ventio_drift_database.dart';
import 'accounting_service.dart';
import 'batch_inventory_service.dart';
import 'inventory_posting_service.dart';
import 'journal_posting_guard.dart';
import 'posted_document_snapshot_service.dart';
import 'sale_cost_service.dart';
import 'stock_transaction_service.dart';

/// Owns one transaction for the invoice, batch allocation, stock movements,
/// accounting journal and customer ledger. Cache and transport updates happen
/// only after this service returns a committed result.
class SalePostingService {
  SalePostingService({
    required this.sqliteDb,
    required this.session,
    required this.productsById,
    required this.costsByProductId,
    required this.syncTarget,
    Future<void> Function(Sale)? postAccounting,
  }) : postAccounting = postAccounting ?? _postAccounting;

  final VentioDriftDatabase sqliteDb;
  final BusinessSessionContext session;
  final Map<String, Product> productsById;
  final Map<String, ProductCost> costsByProductId;
  final String syncTarget;
  final Future<void> Function(Sale) postAccounting;

  static Future<void> _postAccounting(Sale sale) =>
      AccountingService.recordSale(sale,
          paymentPostedSeparately: true, withinExistingTransaction: true);

  Future<SalePostingResult> post(
    Sale draft, {
    required double displayedPaidAmount,
    required double legacyDefaultVatRatePercent,
    Customer? customer,
    UserRole? role,
  }) async {
    var sale = draft;
    final now = draft.date;
    final saleItems = draft.items;
    final stockMovements = <StockMovement>[];
    final inventoryPosting = InventoryPostingService(
        sqliteDb, session.appIdentity,
        productCostFor: (id) => costsByProductId[id]!);
    final costService = SaleCostService(
      db: sqliteDb,
      costingMethod: session.inventoryCostingMethod,
      allowNegativeStock: session.storeProfile.allowNegativeStock,
      productById: (id) => productsById[id],
      productCostFor: (id) => costsByProductId[id]!,
    );
    final taxProfileIdByProductId = {
      for (final product in productsById.values)
        product.id: product.taxProfileId,
    };
    final stockService = StockTransactionService(
      sqliteDb,
      deviceId: session.deviceId,
      defaultStoreId: session.appIdentity.storeId,
      defaultBranchId: session.appIdentity.branchId,
      defaultSyncTarget: syncTarget,
      allowNegativeStockResolver: (_, __) =>
          session.storeProfile.allowNegativeStock,
    );
    final batchService = BatchInventoryService(sqliteDb);
    await sqliteDb.transaction(() async {
      final ensuredUnifiedCutovers = <String>{};
      final allocatedItems = <SaleItem>[];
      for (var lineIndex = 0; lineIndex < saleItems.length; lineIndex += 1) {
        final item = saleItems[lineIndex];
        final product = productsById[item.productId];
        if (product == null || !product.trackStock) {
          final resolvedCost = await costService.resolve(item, now);
          allocatedItems.add(SaleItem(
            productId: item.productId,
            productName: item.productName,
            unitPrice: item.unitPrice,
            quantity: item.quantity,
            unitName: item.unitName,
            baseQuantity: item.effectiveBaseQuantity,
            conversionToBase: item.conversionToBase,
            unitCost: resolvedCost.unitCost,
            costingMethodAtSale: resolvedCost.method,
            costCurrency: resolvedCost.currencyCode,
            costExchangeRate: 1,
            costLayerConsumptions: resolvedCost.consumptions,
          ));
          continue;
        }

        final cutoverKey = '${product.id}::${sale.warehouseId}';
        if (ensuredUnifiedCutovers.add(cutoverKey)) {
          await inventoryPosting.ensureCutover(
            product: product,
            warehouseId: sale.warehouseId,
            at: now,
          );
        }
        final allocations = await batchService.allocateUnifiedInTransaction(
          product: product,
          warehouseId: sale.warehouseId,
          quantity: item.effectiveBaseQuantity,
          movementDate: now,
          storeId: session.appIdentity.storeId,
          deviceId: session.deviceId,
          branchId: session.appIdentity.branchId,
          allowNegativeStock: session.storeProfile.allowNegativeStock,
        );
        final totalBatchCost = allocations.fold<double>(
          0,
          (sum, allocation) =>
              sum + (allocation.quantity * allocation.unitCost),
        );
        final effectiveUnitCost = item.effectiveBaseQuantity <= 0.000001
            ? 0.0
            : totalBatchCost / item.effectiveBaseQuantity;
        final allocatedItem = SaleItem(
          productId: item.productId,
          productName: item.productName,
          unitPrice: item.unitPrice,
          quantity: item.quantity,
          unitName: item.unitName,
          baseQuantity: item.effectiveBaseQuantity,
          conversionToBase: item.conversionToBase,
          unitCost: effectiveUnitCost,
          costingMethodAtSale: InventoryCostingMethod.batch,
          costCurrency: 'USD',
          costExchangeRate: 1,
          costLayerConsumptions: const <InventoryCostLayerConsumption>[],
          batchAllocations: allocations,
        );
        allocatedItems.add(allocatedItem);
        for (var batchIndex = 0;
            batchIndex < allocations.length;
            batchIndex += 1) {
          final allocation = allocations[batchIndex];
          stockMovements.add(StockMovement(
            id: '${sale.id}-${item.productId}-${allocation.batchId}-sale-$lineIndex',
            productId: item.productId,
            productName: item.productName,
            type: 'sale',
            quantity: -allocation.quantity,
            date: now,
            referenceId: sale.id,
            referenceNo: sale.invoiceNo,
            reason: product.expiryTrackingEnabled
                ? 'Sale invoice (Unified FEFO)'
                : 'Sale invoice (Unified oldest batch)',
            unitCost: allocation.unitCost,
            warehouseId: sale.warehouseId,
            warehouseName: sale.warehouseName,
            batchId: allocation.batchId,
            movementGroupId: sale.id,
            documentLineId: '${sale.id}-line-$lineIndex',
            idempotencyKey: '${sale.id}:sale:$lineIndex:$batchIndex',
            createdAt: now,
            updatedAt: now,
            deviceId: session.deviceId,
            storeId: session.appIdentity.storeId,
            branchId: session.appIdentity.branchId,
            syncStatus: 'pending',
            lastModifiedByDeviceId: session.deviceId,
          ));
        }
      }
      sale = sale.copyWith(items: allocatedItems);
      sale = sale.copyWith(
        postedSnapshot: PostedDocumentSnapshotService.forSale(
          sale: sale,
          profile: session.storeProfile,
          customer: customer,
          user: session.activeUser,
          role: role,
          displayedPaidAmount: displayedPaidAmount,
          taxProfileIdByProductId: taxProfileIdByProductId,
          legacyDefaultVatRatePercent: legacyDefaultVatRatePercent,
        ),
      );
      await BusinessSqliteStore.upsertEntityPayloads(
        sqliteDb,
        'sales_v4',
        <Map<String, dynamic>>[sale.toJson()],
        sortIndices: <int?>[0],
      );
      await stockService.recordMovementsInTransaction(
        operationType: 'sale',
        documentType: 'sale',
        documentId: sale.id,
        movementGroupId: sale.id,
        idempotencyKey: sale.id,
        movements: stockMovements,
        storeId: session.appIdentity.storeId,
        branchId: session.appIdentity.branchId,
        deviceId: session.deviceId,
      );
      await inventoryPosting.assertMovementBalances(
        batchService,
        stockMovements,
      );
      await postAccounting(sale);
      await JournalPostingGuard(sqliteDb).requirePosted(
        referenceType: 'sale',
        referenceId: sale.id,
        failureMessage:
            'Sale journal was not persisted; the sale transaction was rolled back.',
      );
      final saleAccountId = sale.customerId.trim().isNotEmpty
          ? sale.customerId.trim()
          : sale.customerName.trim();
      if (saleAccountId.isNotEmpty) {
        await _persistCustomerLedger(
          AccountTransaction(
            id: '${sale.id}-sale-invoice',
            accountType: 'customer',
            accountId: saleAccountId,
            accountName: sale.customerName,
            date: sale.date,
            type: 'saleInvoice',
            referenceId: sale.id,
            referenceNo: sale.invoiceNo,
            debit: sale.invoiceTotal,
            currency: sale.invoiceCurrency,
            note: 'Sale invoice ${sale.invoiceNo}',
            createdAt: now,
            updatedAt: now,
            deviceId: session.deviceId,
            storeId: session.appIdentity.storeId,
            branchId: session.appIdentity.branchId,
            lastModifiedByDeviceId: session.deviceId,
          ),
        );
      }
    });
    return SalePostingResult(sale, List.unmodifiable(stockMovements));
  }

  Future<void> _persistCustomerLedger(AccountTransaction transaction) =>
      BusinessSqliteStore.upsertEntityPayloads(
          sqliteDb, 'account_transactions_v1', [transaction.toJson()],
          sortIndices: const [0]);
}

class SalePostingResult {
  const SalePostingResult(this.sale, this.stockMovements);
  final Sale sale;
  final List<StockMovement> stockMovements;
}
