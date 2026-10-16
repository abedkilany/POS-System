import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pointycastle/export.dart' as pc;

import '../core/contracts/application_session.dart';
import '../core/localization/localized_domain_exception.dart';
import '../core/repositories/business_session_context.dart';
import '../core/services/account_auth_service.dart';
import '../core/services/account_ledger_read_service.dart';
import '../core/services/accounting_service.dart';
import '../core/services/app_logging_service.dart';
import '../core/services/batch_inventory_service.dart';
import '../core/services/cash_ledger_service.dart';
import '../core/services/cash_reversal_service.dart';
import '../core/services/catalog_read_service.dart';
import '../core/services/commerce_read_service.dart';
import '../core/services/direct_sync_settings.dart';
import '../core/services/inventory_posting_service.dart';
import '../core/services/inventory_read_service.dart';
import '../core/services/inventory_traceability_service.dart';
import '../core/services/journal_posting_guard.dart';
import '../core/services/local_database_service.dart';
import '../core/services/payment_voucher_service.dart';
import '../core/services/permission_service.dart';
import '../core/services/posted_document_edit_framework.dart';
import '../core/services/posted_document_snapshot_service.dart';
import '../core/services/purchase_draft_service.dart';
import '../core/services/purchase_receipt_service.dart';
import '../core/services/recovery_file_service.dart';
import '../core/services/sale_cost_service.dart';
import '../core/services/sale_posting_service.dart';
import '../core/services/sale_workflow_service.dart';
import '../core/services/startup_timing_service.dart';
import '../core/services/stock_transaction_service.dart';
import '../core/services/sync_diagnostics_log.dart';
import '../core/services/sync_queue_recovery_service.dart';
import '../core/services/unified_batch_phase4_closure_service.dart';
import '../core/snapshot/unified_snapshot.dart';
import '../core/storage/sqlite/business_sqlite_store.dart';
import '../core/storage/sqlite/sqlite_migration_manager.dart';
import '../core/storage/sqlite/sync_sqlite_store.dart';
import '../core/storage/sqlite/ventio_drift_database.dart';
import '../core/sync_unified/sync_device_state.dart';
import '../core/utils/currency_utils.dart';
import '../models/account_transaction.dart';
import '../models/app_identity.dart';
import '../models/app_user.dart';
import '../models/catalog_item.dart';
import '../models/credit_note.dart';
import '../models/customer.dart';
import '../models/delivery_note.dart';
import '../models/expense.dart';
import '../models/inventory_batch.dart';
import '../models/inventory_cost_layer.dart';
import '../models/inventory_count.dart';
import '../models/journal_entry.dart';
import '../models/manufacturing.dart';
import '../models/payment_allocation.dart';
import '../models/posted_document_snapshot.dart';
import '../models/product.dart';
import '../models/product_costing.dart';
import '../models/product_pricing.dart';
import '../models/purchase.dart';
import '../models/purchase_item.dart';
import '../models/sale.dart';
import '../models/sale_item.dart';
import '../models/sale_quotation.dart';
import '../models/stock_movement.dart';
import '../models/store_profile.dart';
import '../models/supplier.dart';
import '../models/supplier_product_price.dart';
import '../models/supplier_purchase_price.dart';
import '../models/sync_change.dart';
import '../models/sync_queue_item.dart';
import '../models/tax_profile.dart';
import '../models/user_role.dart';
import '../models/warehouse.dart';
import '../models/warehouse_transfer_order.dart';
import 'backup_inventory_normalizer.dart';
import 'state/accounting_state.dart';
import 'state/catalog_state.dart';
import 'state/commerce_state.dart';
import 'state/inventory_state.dart';
import 'state/runtime_state.dart';
import 'state/security_state.dart';
import 'state/sync_state.dart';

export '../core/contracts/application_session.dart';

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
part 'app_store_domains_runtime.dart';
part 'app_store_domains_catalog.dart';
part 'app_store_domains_commerce.dart';
part 'app_store_domains_accounting.dart';
part 'app_store_domains_inventory.dart';
part 'app_store_domains_security.dart';
part 'app_store_domains_sync.dart';
part 'app_store_domains_recovery.dart';
part 'app_store_backup_recovery_snapshot_crypto.dart';
part 'app_store_backup_recovery_import.dart';
part 'app_store_backup_recovery_merge.dart';
part 'app_store_catalog_parties_expenses_catalog_parties.dart';
part 'app_store_catalog_parties_expenses_expense_posting.dart';
part 'app_store_core_loading_projections.dart';
part 'app_store_forwarding_api_startup_identity.dart';
part 'app_store_forwarding_api_catalog_ledger.dart';
part 'app_store_forwarding_api_inventory_payments.dart';
part 'app_store_forwarding_api_sales_recovery.dart';
part 'app_store_identity_users_authentication.dart';
part 'app_store_identity_users_credentials_persistence.dart';
part 'app_store_inventory_count_reversal_batches.dart';
part 'app_store_inventory_batch_reversal.dart';
part 'app_store_inventory_adjustment_edit.dart';
part 'app_store_inventory_adjustments_waste.dart';
part 'app_store_inventory_purchase_movements.dart';
part 'app_store_manufacturing_order_lifecycle.dart';
part 'app_store_manufacturing_completion.dart';
part 'app_store_manufacturing_completed_edit.dart';
part 'app_store_manufacturing_reversal.dart';
part 'app_store_persistence_sync_core_dirty_writes.dart';
part 'app_store_persistence_sync_core_maintenance.dart';
part 'app_store_persistence_sync_core_outbox.dart';
part 'app_store_persistence_sync_core_ledger.dart';
part 'app_store_pricing_costing_policy.dart';
part 'app_store_pricing_costing_layers.dart';
part 'app_store_purchases_create.dart';
part 'app_store_purchases_draft_edit.dart';
part 'app_store_purchases_receipt.dart';
part 'app_store_purchases_return_edit.dart';
part 'app_store_purchases_return_create.dart';
part 'app_store_purchases_reversal.dart';
part 'app_store_sales_returns_create_sale.dart';
part 'app_store_sales_returns_edit_sale.dart';
part 'app_store_sales_returns_stock_links.dart';
part 'app_store_sales_returns_create_return.dart';
part 'app_store_sales_returns_edit_return.dart';
part 'app_store_sales_returns_cancel_return.dart';
part 'app_store_sales_returns_cancel_sale.dart';
part 'app_store_startup_migrations_deferred_loading.dart';
part 'app_store_startup_migrations_catalog_sync.dart';
part 'app_store_sync_apply_remote_changes.dart';
part 'app_store_sync_apply_payload_ack.dart';
part 'app_store_sync_apply_queue_recovery.dart';
part 'app_store_warehouse_cash_transfer_edit.dart';
part 'app_store_warehouse_cash_transfers_refunds.dart';
part 'app_store_warehouse_cash_settlement.dart';
part 'app_store_recovery_import.dart';
part 'app_store_recovery_reset.dart';

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

typedef AppStoreTraceSink = void Function(
  String section,
  String phase,
  int elapsedMs,
  Map<String, Object?> metadata,
);

class AppStore extends ChangeNotifier
    with
        _AppStoreStateAccessors,
        _AppStoreForwardingApi,
        _AppStoreForwardingApiStartupIdentity,
        _AppStoreForwardingApiCatalogLedger,
        _AppStoreForwardingApiInventoryPayments,
        _AppStoreForwardingApiSalesRecovery,
        _AppStoreOrchestration
    implements BusinessSessionContext, ApplicationSession {
  static AppStoreTraceSink? _traceSink;

  /// Preferred typed domain boundaries for new callers.
  @override
  late final AppRuntimeDomainPort runtime = _AppRuntimeDomain(this);
  @override
  late final CatalogDomainPort catalog = _CatalogDomain(this);
  @override
  late final CommerceDomainPort commerce = _CommerceDomain(this);
  @override
  late final AccountingDomainPort accounting = _AccountingDomain(this);
  @override
  late final InventoryDomainPort inventory = _InventoryDomain(this);
  @override
  late final SecurityDomainPort security = _SecurityDomain(this);
  @override
  late final SyncDomainPort sync = _SyncDomain(this);
  @override
  late final RecoveryDomainPort recovery = _RecoveryDomain(this);

  // Storage layers:
  // - SQLite is the source of truth when authoritative mode is enabled.
  // - The lists below are in-memory caches used to make screens and lookups fast.
  // - Derived caches are rebuilt from the source data and should stay disposable.
  // - Sync queues track pending outbound changes and must remain separate from the data store.

  static void setTraceSink(AppStoreTraceSink? sink) {
    _traceSink = sink;
  }

  static const String walkInCustomerId = CommerceDefaults.walkInCustomerId;
  static const String walkInCustomerName = CommerceDefaults.walkInCustomerName;

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
  static const _productPriceHistoryKey = 'product_price_history_v1';
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
  static const int _maxPurchaseAccountingBacklog = 200;

  @override
  void notifyListeners() {
    _storeRevision += 1;
    _invalidateDerivedDataCaches();
    final unsyncedChanges = _syncChanges.where((item) => !item.isSynced).length;
    final outboundChangeIds = _syncQueue
        .where((item) =>
            item.target == _activeClientSyncTarget ||
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

  static const int _syncMaintenanceKeepRecentChanges =
      SyncHistoryPolicy.keepRecentChanges;
  static const int _syncMaintenanceMinChangesBeforeCompact =
      SyncHistoryPolicy.minChangesBeforeCompact;

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
