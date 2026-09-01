import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:archive/archive.dart';
import 'package:pointycastle/export.dart' as pc;

import '../core/repositories/business_session_context.dart';
import '../core/services/local_database_service.dart';
import '../core/services/direct_sync_settings.dart';
import '../core/services/accounting_service.dart';
import '../core/services/account_auth_service.dart';
import '../core/services/app_logging_service.dart';
import '../core/services/startup_timing_service.dart';
import '../core/services/sync_diagnostics_log.dart';
import '../core/services/stock_transaction_service.dart';
import '../core/services/batch_inventory_service.dart';
import '../core/services/inventory_traceability_service.dart';
import '../core/services/unified_batch_phase4_closure_service.dart';
import '../core/services/payment_voucher_service.dart';
import '../core/services/posted_document_snapshot_service.dart';
import '../core/services/posted_document_edit_framework.dart';
import '../core/services/cash_reversal_service.dart';
import '../core/services/cash_ledger_service.dart';
import '../core/localization/localized_domain_exception.dart';
import '../core/sync_unified/sync_device_state.dart';
import '../core/snapshot/unified_snapshot.dart';
import '../core/storage/sqlite/business_sqlite_store.dart';
import '../core/storage/sqlite/sqlite_migration_manager.dart';
import '../core/storage/sqlite/ventio_drift_database.dart';
import '../core/storage/sqlite/sync_sqlite_store.dart';
import '../core/utils/currency_utils.dart';
import 'backup_inventory_normalizer.dart';

import '../models/account_transaction.dart';
import '../models/catalog_item.dart';
import '../models/customer.dart';
import '../models/delivery_note.dart';
import '../models/manufacturing.dart';
import '../models/expense.dart';
import '../models/inventory_count.dart';
import '../models/product.dart';
import '../models/product_pricing.dart';
import '../models/product_costing.dart';
import '../models/inventory_cost_layer.dart';
import '../models/inventory_batch.dart';
import '../models/purchase.dart';
import '../models/purchase_item.dart';
import '../models/supplier_purchase_price.dart';
import '../models/supplier_product_price.dart';
import '../models/stock_movement.dart';
import '../models/warehouse.dart';
import '../models/warehouse_transfer_order.dart';
import '../models/sale.dart';
import '../models/sale_item.dart';
import '../models/sale_quotation.dart';
import '../models/credit_note.dart';
import '../models/store_profile.dart';
import '../models/tax_profile.dart';
import '../models/supplier.dart';
import '../models/sync_change.dart';
import '../models/sync_queue_item.dart';
import '../models/user_role.dart';
import '../models/app_user.dart';
import '../models/app_identity.dart';
import '../models/payment_allocation.dart';
import '../models/receipt_voucher.dart';
import '../models/payment_voucher.dart';

part 'app_store_backup.dart';
part 'app_store_purchase_insights.dart';
part 'app_store_catalog_read.dart';
part 'app_store_party_read.dart';
part 'app_store_core_loading.dart';
part 'app_store_access_auth.dart';
part 'app_store_supplier_insights.dart';
part 'app_store_startup_migrations.dart';
part 'app_store_identity_users.dart';
part 'app_store_persistence_sync_core.dart';
part 'app_store_pricing_costing.dart';
part 'app_store_catalog_parties_expenses.dart';
part 'app_store_warehouse_cash.dart';
part 'app_store_purchases.dart';
part 'app_store_inventory.dart';
part 'app_store_manufacturing.dart';
part 'app_store_sales_returns.dart';
part 'app_store_backup_recovery.dart';
part 'app_store_sync_apply.dart';
part 'app_store_recovery.dart';
part 'app_store_state.dart';
part 'app_store_forwarding_api.dart';
part 'app_store_orchestration.dart';
part 'app_store_domains.dart';

String _encodePrettyBackupPayload(Map<String, dynamic> payload) =>
    const JsonEncoder.withIndent('  ').convert(payload);

bool _verifyPasswordInBackground(Map<String, String> request) {
  const prefix = 'pbkdf2sha256:';
  final password = request['password'] ?? '';
  final storedHash = request['storedHash'] ?? '';
  if (!storedHash.startsWith(prefix)) return false;
  final parts = storedHash.split(':');
  if (parts.length != 4) return false;
  final iterations = int.tryParse(parts[1]);
  if (iterations == null || iterations < 100000) return false;
  final derivator = pc.PBKDF2KeyDerivator(pc.HMac(pc.SHA256Digest(), 64));
  derivator.init(
    pc.Pbkdf2Parameters(base64Url.decode(parts[2]), iterations, 32),
  );
  final hash = derivator.process(
    Uint8List.fromList(utf8.encode('ventio|password|$password')),
  );
  return storedHash ==
      '$prefix$iterations:${parts[2]}:${base64UrlEncode(hash)}';
}

class _ManufacturingCostResolution {
  const _ManufacturingCostResolution({
    required this.unitCost,
    required this.totalCost,
    this.layerConsumptions = const <Map<String, dynamic>>[],
  });

  final double unitCost, totalCost;
  final List<Map<String, dynamic>> layerConsumptions;
}

String _hashPasswordInBackground(Map<String, String> request) {
  const prefix = 'pbkdf2sha256:';
  final password = request['password'] ?? '';
  final salt = request['salt'] ?? '';
  final iterations = int.tryParse(request['iterations'] ?? '') ?? 210000;
  final derivator = pc.PBKDF2KeyDerivator(pc.HMac(pc.SHA256Digest(), 64));
  derivator.init(pc.Pbkdf2Parameters(base64Url.decode(salt), iterations, 32));
  final hash = derivator.process(
    Uint8List.fromList(utf8.encode('ventio|password|$password')),
  );
  return '$prefix$iterations:$salt:${base64UrlEncode(hash)}';
}

List<Map<String, dynamic>> _decodeJsonListPayload(String rawJson) {
  try {
    final decoded = jsonDecode(rawJson);
    if (decoded is! List) return const <Map<String, dynamic>>[];
    return decoded
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  } catch (_) {
    return const <Map<String, dynamic>>[];
  }
}

class DataConflict {
  const DataConflict({
    required this.entityType,
    required this.keyName,
    required this.keyValue,
    required this.recordIds,
    this.blocking = false,
    this.message = '',
  });

  final String entityType;
  final String keyName;
  final String keyValue;
  final List<String> recordIds;
  final bool blocking;
  final String message;

  String get title => '$entityType duplicate $keyName: $keyValue';
}

class BusinessDataIntegrityResult {
  const BusinessDataIntegrityResult({
    required this.ok,
    required this.message,
    this.problemCount = 0,
  });
  final bool ok;
  final String message;
  final int problemCount;
}

/// Result of the safe, explicit repair for historical documents that refer to
/// products that are no longer present in the active catalog.
class BusinessDataIntegrityRepairResult {
  const BusinessDataIntegrityRepairResult({
    required this.reactivatedProducts,
    required this.archivedProductsCreated,
    required this.unresolvedProductIds,
  });

  final int reactivatedProducts;
  final int archivedProductsCreated;
  final List<String> unresolvedProductIds;

  bool get changed => reactivatedProducts > 0 || archivedProductsCreated > 0;
}

class PurchasesOverview {
  const PurchasesOverview({
    required this.totalCount,
    required this.totalPurchasesAmount,
    required this.monthlyTotal,
    required this.monthlyCount,
    required this.draftTotal,
    required this.draftCount,
    required this.receivedCount,
    required this.returnedCount,
    required this.cancelledCount,
    required this.pendingPurchaseCount,
  });

  final int totalCount;
  final double totalPurchasesAmount;
  final double monthlyTotal;
  final int monthlyCount;
  final double draftTotal;
  final int draftCount;
  final int receivedCount;
  final int returnedCount;
  final int cancelledCount;
  final int pendingPurchaseCount;
}

class ExpensesOverview {
  const ExpensesOverview({
    required this.totalCount,
    required this.totalExpensesAmount,
    required this.draftCount,
    required this.postedCount,
    required this.cancelledCount,
    required this.categoryCount,
  });

  final int totalCount;
  final double totalExpensesAmount;
  final int draftCount;
  final int postedCount;
  final int cancelledCount;
  final int categoryCount;
}

class StorageLayerSnapshot {
  const StorageLayerSnapshot({
    required this.sqliteAuthoritative,
    required this.productCacheCount,
    required this.salesCacheCount,
    required this.supplierCacheCount,
    required this.derivedCacheCount,
    required this.syncChangeCount,
    required this.syncQueueCount,
  });

  final bool sqliteAuthoritative;
  final int productCacheCount;
  final int salesCacheCount;
  final int supplierCacheCount;
  final int derivedCacheCount;
  final int syncChangeCount;
  final int syncQueueCount;

  String toLogLine() =>
      'sqliteAuthoritative=$sqliteAuthoritative products=$productCacheCount sales=$salesCacheCount '
      'suppliers=$supplierCacheCount derivedCaches=$derivedCacheCount syncChanges=$syncChangeCount '
      'syncQueue=$syncQueueCount';
}

class _ProductPurchaseMetrics {
  const _ProductPurchaseMetrics({
    this.lastCost,
    this.averageCost = 0,
    this.supplierCount = 0,
  });

  final double? lastCost;
  final double averageCost;
  final int supplierCount;
}

class AppStoreActionException implements Exception {
  const AppStoreActionException(this.message);

  final String message;

  @override
  String toString() => message;
}

typedef AppStoreTraceSink = void Function(
  String section,
  String phase,
  int elapsedMs,
  Map<String, Object?> metadata,
);

class AppStore extends ChangeNotifier
    with _AppStoreStateAccessors, _AppStoreForwardingApi, _AppStoreOrchestration
    implements BusinessSessionContext {
  static AppStoreTraceSink? _traceSink;

  /// Preferred typed domain boundaries for new callers.
  late final CatalogDomainPort catalog = _CatalogDomain(this);
  late final CommerceDomainPort commerce = _CommerceDomain(this);
  late final AccountingDomainPort accounting = _AccountingDomain(this);
  late final InventoryDomainPort inventory = _InventoryDomain(this);
  late final SecurityDomainPort security = _SecurityDomain(this);
  late final SyncDomainPort sync = _SyncDomain(this);
  late final RecoveryDomainPort recovery = _RecoveryDomain(this);

  // Storage layers:
  // - SQLite is the source of truth when authoritative mode is enabled.
  // - The lists below are in-memory caches used to make screens and lookups fast.
  // - Derived caches are rebuilt from the source data and should stay disposable.
  // - Sync queues track pending outbound changes and must remain separate from the data store.

  static void setTraceSink(AppStoreTraceSink? sink) {
    _traceSink = sink;
  }

  static const String walkInCustomerId = 'walk_in';
  static const String walkInCustomerName = 'Walk-in Customer';

  static const _productsKey = 'products_v4';
  static const _phase8AccountingSyncCursorKey =
      'phase8_accounting_sync_cursor_v1';
  static const _customersKey = 'customers_v4';
  static const _salesKey = 'sales_v4';
  static const _creditNotesKey = 'credit_notes_v1';
  static const _saleQuotationsKey = 'sale_quotations_v1';
  static const _deliveryNotesKey = 'delivery_notes_v1';
  static const _billsOfMaterialsKey = 'bills_of_materials_v1';
  static const _manufacturingOrdersKey = 'manufacturing_orders_v1';
  static const _suppliersKey = 'suppliers_v4';
  static const _supplierProductPricesKey = 'supplier_product_prices_v1';
  static const _priceListsKey = 'price_lists_v1';
  static const _productPricesKey = 'product_prices_v1';
  static const _productPriceOverridesKey = 'product_price_overrides_v1';
  static const _productCostsKey = 'product_costs_v1';
  static const _costingMethodHistoryKey = 'costing_method_history_v1';
  static const _inventoryCostingMethodKey = 'inventory_costing_method_v1';
  static const _inventoryCostLayersKey = 'inventory_cost_layers_v1';
  static const _expensesKey = 'expenses_v4';
  static const _purchasesKey = 'purchases_v1';
  static const _stockMovementsKey = 'stock_movements_v1';
  static const _inventoryCountsKey = 'inventory_counts_v1';
  static const _warehousesKey = 'warehouses_v1';
  static const _accountTransactionsKey = 'account_transactions_v1';
  static const _purchaseCounterKey = 'purchase_counter_v1';
  static const _storeProfileKey = 'store_profile_v5';
  static const _categoriesKey = 'product_categories_v1';
  static const _brandsKey = 'product_brands_v1';
  static const _unitsKey = 'product_units_v1';
  static const _invoiceCounterKey = 'invoice_counter_v1';
  static const _deviceIdKey = 'sync_device_id_v1';
  static const _syncChangesKey = 'sync_changes_v1';
  static const _syncQueueKey = 'sync_queue_v1';
  static const _syncSequenceKey = 'sync_sequence_v1';
  static const _schemaVersionKey = 'schema_version_v1';
  static const _legacyLocalCredentialHashPrefix = 'sha256salt:';
  static const _passwordHashPrefix = 'pbkdf2sha256:';
  static const _passwordHashIterations = 210000;
  static const _currentRoleKey =
      'current_role_v1'; // legacy, no longer user-editable
  static const _rolesKey = 'roles_v1';
  static const _usersKey = 'users_v1';
  static const _activeUserKey = 'active_user_v1';
  static const _rememberLoginKey = 'remember_login_v1';
  static const _appIdentityKey = 'app_identity_v1';
  static const _themeModeKey = 'theme_mode_v1';
  static const _localeKey = 'locale_v1';
  static const _hostTransferApprovedDeviceKey =
      'host_transfer_approved_device_v1';
  static const _hostTransferRequestKey = 'host_transfer_request_v1';
  static const _hostTransferNotificationKey = 'host_transfer_notification_v1';
  static const _devFeatureFlagsKey = 'dev_feature_flags_v1';
  static const _stressLabEnabledFlag = 'stressLabEnabled';
  static const int _maxPurchaseAccountingBacklog = 200;

  @override
  void notifyListeners() {
    _storeRevision += 1;
    _invalidateDerivedDataCaches();
    final unsyncedChanges = _syncChanges.where((item) => !item.isSynced).length;
    final outboundChangeIds = _syncQueue
        .where((item) =>
            item.target == activeClientSyncTarget ||
            (appIdentity.isHost && item.target == 'host'))
        .where((item) => item.isReadyToSend)
        .map((item) => item.changeId)
        .toSet();
    final outboundChanges = _syncChanges
        .where((item) => !item.isSynced && outboundChangeIds.contains(item.id))
        .length;
    SyncDiagnosticsLog.add(
      '[SYNC_TRACE] notifyListeners device=$_deviceId '
      'role=${appIdentity.deviceRole.name} customers=${_customers.length} '
      'sales=${_sales.length} accounts=${_accountTransactions.length} '
      'seq=$_syncSequence queueEntries=${_syncQueue.length} '
      'syncHistoryEntries=${_syncChanges.length} '
      'unsyncedChanges=$unsyncedChanges outboundChanges=$outboundChanges',
    );
    super.notifyListeners();
  }

  static const List<String> databaseEditableEntities = [
    'products',
    'customers',
    'suppliers',
    'supplierProductPrices',
    'expenses',
    'categories',
    'brands',
    'units',
  ];

  static const int _syncMaintenanceKeepRecentChanges = 200;
  static const int _syncMaintenanceMinChangesBeforeCompact = 1000;

  static const Set<String> _businessBackupBlockedKeys = {
    'deviceId',
    'syncStatus',
    'lastModifiedByDeviceId',
    'syncChanges',
    'syncQueue',
    'direct_last_pull_cursor',
    'remoteCursor',
    'pairingCode',
    'pairingData',
    'deviceToken',
    'remoteToken',
    'lanSession',
    'hostDeviceId',
    'activeUser',
    'rememberLogin',
    'autoLoginSession',
    'debugLogs',
    'relayState',
    'runtimeCache',
    'pendingSyncOperations',
    'appIdentity',
    'storeEpoch',
    'transportType',
  };

  static const String _hostSnapshotGenerationKey =
      'host_snapshot_generation_v1';
  static const String _hostRestoreCommandIdKey = 'host_restore_command_id_v1';

  @override
  void dispose() {
    _productDerivedDataFlushTimer?.cancel();
    if (!_shutdownPrepared) {
      unawaited(_flushProductDerivedData());
      unawaited(LocalDatabaseService.flushPendingWrites());
    }
    super.dispose();
  }
}
