import 'package:drift/drift.dart';

import '../../models/inventory_batch.dart';
import '../../models/product.dart';
import '../localization/localized_domain_exception.dart';
import '../storage/sqlite/ventio_drift_database.dart';
import 'accounting_service.dart';
part 'batch_inventory_service_methods_01.dart';
part 'batch_inventory_service_methods_02.dart';
part 'batch_inventory_service_methods_03.dart';
part 'batch_inventory_service_methods_04.dart';
part 'batch_inventory_service_methods_05.dart';

class UnifiedBatchCostPreview {
  const UnifiedBatchCostPreview({
    required this.requestedQuantity,
    required this.physicalQuantity,
    required this.shortageQuantity,
    required this.totalCost,
    required this.unitCost,
    required this.usesProvisionalCost,
    required this.provisionalUnitCost,
  });

  final double requestedQuantity;
  final double physicalQuantity;
  final double shortageQuantity;
  final double totalCost;
  final double unitCost;
  final bool usesProvisionalCost;
  final double provisionalUnitCost;

  bool get hasShortage => shortageQuantity > 0.000001;
}

/// Transactional batch inventory operations.
///
/// Phase 1 introduces a unified batch engine for every stock-tracked product.
/// The legacy expiry-only entry points remain temporarily for compatibility
/// until purchase/sale write paths cut over in Phase 2.
///
/// Callers must execute these methods inside the same SQLite transaction used
/// for the corresponding stock movements so aggregate and batch balances can
/// never diverge.
class BatchInventoryService {
  const BatchInventoryService(this.db);

  final VentioDriftDatabase db;

  static bool isDeficitBatchId(String batchId) =>
      batchId.trim().startsWith('deficit:');
}
