import 'dart:convert';

import 'package:drift/drift.dart';

import '../../models/stock_movement.dart';
import '../../models/warehouse_inventory.dart';
import '../../models/sync_change.dart';
import '../repositories/warehouse_inventory_repository.dart';
import '../localization/localized_domain_exception.dart';
import '../storage/sqlite/ventio_drift_database.dart';
part 'stock_transaction_service_methods_01.dart';
part 'stock_transaction_service_methods_02.dart';

class StockTransactionReceipt {
  const StockTransactionReceipt({
    required this.operationId,
    required this.operationType,
    required this.documentType,
    required this.documentId,
    required this.movementGroupId,
    required this.movementIds,
    required this.idempotencyKey,
    required this.completedAt,
  });

  final String operationId;
  final String operationType;
  final String documentType;
  final String documentId;
  final String movementGroupId;
  final List<String> movementIds;
  final String idempotencyKey;
  final DateTime completedAt;
}

class StockIntegrityIssue {
  const StockIntegrityIssue({
    required this.storeId,
    required this.warehouseId,
    required this.productId,
    required this.productName,
    required this.warehouseBalance,
    required this.ledgerBalance,
    required this.legacyProductStock,
    required this.difference,
    required this.classification,
  });

  final String storeId;
  final String warehouseId;
  final String productId;
  final String productName;
  final double warehouseBalance;
  final double ledgerBalance;
  final double legacyProductStock;
  final double difference;
  final String classification;
}

class StockIntegrityReport {
  const StockIntegrityReport({
    required this.ok,
    required this.message,
    required this.issues,
  });

  final bool ok;
  final String message;
  final List<StockIntegrityIssue> issues;
}

class _StockOperationInProgressException implements Exception {
  _StockOperationInProgressException(this.message);
  final String message;

  @override
  String toString() => message;
}

class _OperationAcquisition {
  const _OperationAcquisition._({
    required this.proceed,
    required this.completedReceipt,
    required this.inProgressMessage,
    required this.currentStatus,
    required this.attemptCount,
  });

  const _OperationAcquisition.proceed({
    required String currentStatus,
    required int attemptCount,
  }) : this._(
          proceed: true,
          completedReceipt: null,
          inProgressMessage: '',
          currentStatus: currentStatus,
          attemptCount: attemptCount,
        );

  const _OperationAcquisition.completed(this.completedReceipt)
      : proceed = false,
        inProgressMessage = '',
        currentStatus = 'completed',
        attemptCount = 0;

  const _OperationAcquisition.inProgress(this.inProgressMessage)
      : proceed = false,
        completedReceipt = null,
        currentStatus = 'pending',
        attemptCount = 0;

  final bool proceed;
  final StockTransactionReceipt? completedReceipt;
  final String inProgressMessage;
  final String currentStatus;
  final int attemptCount;
}

class _MovementInsertResult {
  const _MovementInsertResult({
    required this.movementId,
    required this.inserted,
  });

  final String movementId;
  final bool inserted;
}

typedef NegativeStockPolicyResolver = bool Function(
  String storeId,
  String warehouseId,
);

class StockTransactionService {
  StockTransactionService(
    this.db, {
    this.deviceId = '',
    this.defaultStoreId = '',
    this.defaultBranchId = 'main',
    this.defaultSyncTarget = 'direct',
    this.allowNegativeStockResolver,
  });

  final VentioDriftDatabase db;
  final String deviceId;
  final String defaultStoreId;
  final String defaultBranchId;
  final String defaultSyncTarget;
  final NegativeStockPolicyResolver? allowNegativeStockResolver;
  static final Map<int, int> _nextSyncSequenceByDb = <int, int>{};
}
