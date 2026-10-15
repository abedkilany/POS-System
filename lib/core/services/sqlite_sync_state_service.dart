import 'dart:convert';

import 'package:drift/drift.dart';

import '../localization/localized_domain_exception.dart';
import 'local_database_service.dart';
import 'batch_inventory_service.dart';
import '../repositories/business_session_context.dart';
import '../storage/sqlite/business_sqlite_store.dart';
import '../storage/sqlite/sqlite_migration_manager.dart';
import '../storage/sqlite/sync_sqlite_store.dart';
import '../storage/sqlite/ventio_drift_database.dart';
import '../repositories/warehouse_inventory_repository.dart';
import '../../models/app_identity.dart';
import '../../models/sync_change.dart';
import '../../models/sync_queue_item.dart';
import '../../models/store_profile.dart';
import '../../models/stock_movement.dart';
import '../../models/warehouse.dart';
import '../../models/warehouse_inventory.dart';
part 'sqlite_sync_state_service_methods_01.dart';
part 'sqlite_sync_state_service_methods_02.dart';
part 'sqlite_sync_state_service_methods_03.dart';
part 'sqlite_sync_state_service_methods_04.dart';

const String _appIdentityKey = 'app_identity_v1';
const String _storeProfileKey = 'store_profile_v5';
const String _hostTransferRequestKey = 'host_transfer_request_v1';
const String _hostTransferApprovedDeviceKey =
    'host_transfer_approved_device_v1';
const String _directHostBootstrapMarkerPrefix = 'host_bootstrap_snapshot_v3_';
const String _invoiceCounterKey = 'invoice_counter_v1';
const String _purchaseCounterKey = 'purchase_counter_v1';

enum _StockOperationState {
  proceed,
  completed,
  inProgress,
}

class SqliteSyncStateService {
  const SqliteSyncStateService();
}
