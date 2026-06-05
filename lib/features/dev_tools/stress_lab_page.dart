import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/cloud_sync_service.dart';
import '../../core/services/local_database_service.dart';
import '../../core/sync_unified/sync_unified.dart';
import '../../data/app_store.dart';
import '../../models/customer.dart';
import '../../models/expense.dart';
import '../../models/product.dart';
import '../../models/purchase_item.dart';
import '../../models/sale_item.dart';
import '../../models/supplier.dart';

class StressLabPage extends StatefulWidget {
  const StressLabPage({super.key, required this.store});

  final AppStore store;

  @override
  State<StressLabPage> createState() => _StressLabPageState();
}

class _StressLabPageState extends State<StressLabPage> {
  final _productsController = TextEditingController(text: '1000');
  final _customersController = TextEditingController(text: '500');
  final _suppliersController = TextEditingController(text: '100');
  final _salesController = TextEditingController(text: '500');
  final _progressEveryController = TextEditingController(text: '25');
  static final List<String> _persistentLog = <String>[];
  final _log = _persistentLog;
  final _random = Random(52);

  bool _running = false;
  double _progress = 0;
  String _status = 'Ready';
  String _currentBatchId = '';

  AppStore get store => widget.store;

  @override
  void dispose() {
    _productsController.dispose();
    _customersController.dispose();
    _suppliersController.dispose();
    _salesController.dispose();
    _progressEveryController.dispose();
    super.dispose();
  }

  int _readInt(TextEditingController controller, int fallback) {
    final value = int.tryParse(controller.text.trim());
    if (value == null || value < 0) return fallback;
    return value;
  }

  String _timestamp() => DateTime.now().toIso8601String();

  void _addLog(String message) {
    final line = '[${_timestamp()}] $message';
    if (mounted) {
      setState(() {
        _log.add(line);
        if (_log.length > 4000) _log.removeRange(0, _log.length - 4000);
      });
    } else {
      _log.add(line);
    }
    debugPrint('Ventio Stress Lab: $line');
  }

  void _setStatus(String value, {double? progress}) {
    if (!mounted) return;
    setState(() {
      _status = value;
      if (progress != null) _progress = progress.clamp(0, 1);
    });
  }

  String _roleLabel() {
    final identity = store.appIdentity;
    if (identity.isHost) return 'HOST';
    if (identity.isClient && identity.activeSyncTransportNormalized == 'cloud') return 'CLIENT_CLOUD';
    if (identity.isClient && identity.activeSyncTransportNormalized == 'lan') return 'CLIENT_LAN';
    return 'LOCAL_${identity.deviceRole.name.toUpperCase()}';
  }

  String _snapshotLine(String label) {
    final identity = store.appIdentity;
    final rejectedQueue = store.syncQueue.where((item) => item.status.toLowerCase() == 'rejected').length;
    final failedQueue = store.syncQueue.where((item) => item.status.toLowerCase() == 'failed').length;
    return '$label role=${_roleLabel()} device=${identity.deviceId} store=${identity.storeId} branch=${identity.branchId} '
        'transport=${identity.activeSyncTransportNormalized} epoch=${identity.storeEpoch} seq=${store.currentSyncSequence} '
        'products=${store.products.length} customers=${store.customers.length} suppliers=${store.suppliers.length} '
        'sales=${store.sales.length} purchases=${store.purchases.length} expenses=${store.expenses.length} stockMovements=${store.stockMovements.length} '
        'pendingQueue=${store.pendingSyncQueue.length} pendingChanges=${store.pendingSyncChanges.length} '
        'allQueue=${store.syncQueue.length} allChanges=${store.syncChanges.length} rejectedQueue=$rejectedQueue failedQueue=$failedQueue';
  }


  int _logicalDatabaseBytes() {
    final entries = LocalDatabaseService.allEntries();
    var total = 0;
    for (final entry in entries.entries) {
      total += utf8.encode(entry.key).length + utf8.encode(entry.value).length;
    }
    return total;
  }

  String _dbMetricsLine(String label) {
    final entries = LocalDatabaseService.allEntries();
    final logicalBytes = _logicalDatabaseBytes();
    final backup = store.exportBackupJson();
    return '$label dbKeys=${entries.length} logicalDbBytes=$logicalBytes logicalDbMB=${(logicalBytes / 1024 / 1024).toStringAsFixed(2)} '
        'backupBytes=${backup.length} backupMB=${(backup.length / 1024 / 1024).toStringAsFixed(2)}';
  }

  void _logDatabaseMetrics(String label) {
    try {
      _addLog(_dbMetricsLine(label));
    } catch (error) {
      _addLog('$label DB_METRICS_FAILED $error');
    }
  }

  void _applyPreset({required int products, required int customers, required int suppliers, required int sales, required int progressEvery}) {
    if (_running) return;
    setState(() {
      _productsController.text = products.toString();
      _customersController.text = customers.toString();
      _suppliersController.text = suppliers.toString();
      _salesController.text = sales.toString();
      _progressEveryController.text = progressEvery.toString();
      _status = 'Preset applied.';
    });
  }

  Future<T> _measure<T>(String label, Future<T> Function() action) async {
    final sw = Stopwatch()..start();
    try {
      final result = await action();
      sw.stop();
      _addLog('$label OK in ${sw.elapsedMilliseconds} ms');
      return result;
    } catch (error, stackTrace) {
      sw.stop();
      _addLog('$label FAILED in ${sw.elapsedMilliseconds} ms: $error');
      _addLog(stackTrace.toString().split('\n').take(8).join(' | '));
      rethrow;
    }
  }

  Future<void> _runFullSimulation() async {
    if (_running) return;
    setState(() {
      _running = true;
      _progress = 0;
      _status = 'Starting...';
      _currentBatchId = 'stress_${DateTime.now().millisecondsSinceEpoch}_${_roleLabel().toLowerCase()}';
    });

    try {
      _addLog('VENTIO_REAL_APP_STRESS_START batch=$_currentBatchId buildMode=${kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug')}');
      _addLog(_snapshotLine('BEFORE'));
      _logDatabaseMetrics('BEFORE_DB');
      await _seedCatalog();
      await _createSales();
      await _runActiveSync();
      await _exportBackupProbe();
      _logDatabaseMetrics('AFTER_DB');
      _addLog(_snapshotLine('AFTER'));
      _addHealthSummary('REAL_APP_STRESS_SUMMARY');
      _addLog('VENTIO_REAL_APP_STRESS_DONE batch=$_currentBatchId');
      _setStatus('Done', progress: 1);
    } catch (error) {
      _addLog('VENTIO_REAL_APP_STRESS_FAILED batch=$_currentBatchId error=$error');
      _setStatus('Failed: $error');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _seedCatalog() async {
    final productCount = _readInt(_productsController, 1000);
    final customerCount = _readInt(_customersController, 500);
    final supplierCount = _readInt(_suppliersController, 100);
    final progressEvery = max(1, _readInt(_progressEveryController, 25));

    _setStatus('Seeding suppliers...', progress: 0.02);
    await _measure('Seed suppliers count=$supplierCount', () async {
      for (var i = 1; i <= supplierCount; i++) {
        final id = '${_currentBatchId}_supplier_$i';
        await store.addOrUpdateSupplier(Supplier(
          id: id,
          name: '[STRESS] Supplier $i $_currentBatchId',
          phone: '+961700${i.toString().padLeft(5, '0')}',
          address: 'Stress address $i',
          notes: 'Generated by Ventio Stress Lab',
        ));
        if (i == 1 || i % progressEvery == 0 || i == supplierCount) {
          _addLog('Suppliers progress $i/$supplierCount ${_snapshotLine('SNAPSHOT')}');
          _setStatus('Seeding suppliers $i/$supplierCount', progress: 0.02 + 0.10 * (i / max(1, supplierCount)));
          await Future<void>.delayed(Duration.zero);
        }
      }
    });

    _setStatus('Seeding customers...', progress: 0.14);
    await _measure('Seed customers count=$customerCount', () async {
      for (var i = 1; i <= customerCount; i++) {
        final id = '${_currentBatchId}_customer_$i';
        await store.addOrUpdateCustomer(Customer(
          id: id,
          name: '[STRESS] Customer $i $_currentBatchId',
          phone: '+961710${i.toString().padLeft(5, '0')}',
          address: 'Stress customer address $i',
        ));
        if (i == 1 || i % progressEvery == 0 || i == customerCount) {
          _addLog('Customers progress $i/$customerCount ${_snapshotLine('SNAPSHOT')}');
          _setStatus('Seeding customers $i/$customerCount', progress: 0.14 + 0.16 * (i / max(1, customerCount)));
          await Future<void>.delayed(Duration.zero);
        }
      }
    });

    _setStatus('Seeding products...', progress: 0.32);
    await _measure('Seed products count=$productCount', () async {
      for (var i = 1; i <= productCount; i++) {
        final price = 5.0 + (i % 200);
        final cost = max(1.0, price * 0.65);
        final id = '${_currentBatchId}_product_$i';
        await store.addOrUpdateProduct(Product(
          id: id,
          name: '[STRESS] Product ${i.toString().padLeft(5, '0')} $_currentBatchId',
          nameEn: 'Stress Product ${i.toString().padLeft(5, '0')}',
          nameAr: 'منتج اختبار ${i.toString().padLeft(5, '0')}',
          code: 'ST-${_currentBatchId.hashCode.abs()}-${i.toString().padLeft(5, '0')}',
          barcode: 'ST${_currentBatchId.hashCode.abs()}${i.toString().padLeft(6, '0')}',
          price: price,
          cost: cost,
          stock: 100000,
          category: 'Stress Lab',
          brand: 'Stress',
          supplier: supplierCount == 0 ? '' : '[STRESS] Supplier ${1 + (i % supplierCount)} $_currentBatchId',
          unit: 'pcs',
          lowStockThreshold: 10,
          trackStock: true,
          isActive: true,
        ));
        if (i == 1 || i % progressEvery == 0 || i == productCount) {
          _addLog('Products progress $i/$productCount ${_snapshotLine('SNAPSHOT')}');
          _setStatus('Seeding products $i/$productCount', progress: 0.32 + 0.24 * (i / max(1, productCount)));
          await Future<void>.delayed(Duration.zero);
        }
      }
    });
  }

  Future<void> _createSales() async {
    final saleCount = _readInt(_salesController, 500);
    final progressEvery = max(1, _readInt(_progressEveryController, 25));
    final stressProducts = store.products.where((item) => item.name.contains('[STRESS]') && item.stock > 10 && !item.isDeleted).toList();
    final stressCustomers = store.customers.where((item) => item.name.contains('[STRESS]') && !item.isDeleted).toList();
    if (stressProducts.isEmpty) {
      throw StateError('No stress products available. Seed products first.');
    }

    var totalSaleMs = 0;
    var maxSaleMs = 0;
    var slowSales = 0;
    final salesSw = Stopwatch()..start();

    _setStatus('Creating sales...', progress: 0.58);
    await _measure('Create real sales count=$saleCount', () async {
      for (var i = 1; i <= saleCount; i++) {
        final sw = Stopwatch()..start();
        final itemCount = 1 + _random.nextInt(min(5, stressProducts.length));
        final selected = <Product>[];
        while (selected.length < itemCount) {
          final product = stressProducts[_random.nextInt(stressProducts.length)];
          if (!selected.any((item) => item.id == product.id)) selected.add(product);
        }
        final items = selected.map((product) {
          final qty = 1 + _random.nextInt(3);
          return SaleItem(
            productId: product.id,
            productName: product.name,
            unitPrice: product.price,
            quantity: qty.toDouble(),
            unitCost: product.usdCost,
            unitName: product.unit,
            baseQuantity: qty.toDouble(),
            conversionToBase: 1,
          );
        }).toList();
        final customer = stressCustomers.isEmpty ? AppStore.walkInCustomerName : stressCustomers[_random.nextInt(stressCustomers.length)].name;
        await store.createSale(customerName: customer, items: items, paymentMethod: i.isEven ? 'Cash' : 'Card');
        sw.stop();
        totalSaleMs += sw.elapsedMilliseconds;
        maxSaleMs = max(maxSaleMs, sw.elapsedMilliseconds);
        if (sw.elapsedMilliseconds >= 1000) slowSales += 1;

        if (i == 1 || i % progressEvery == 0 || i == saleCount) {
          final avg = totalSaleMs / i;
          _addLog('Sales progress $i/$saleCount batchElapsed=${salesSw.elapsed} avgSaleMs=${avg.toStringAsFixed(1)} maxSaleMs=$maxSaleMs slowSales=$slowSales ${_snapshotLine('SNAPSHOT')}');
          _setStatus('Creating sales $i/$saleCount avg=${avg.toStringAsFixed(1)}ms max=${maxSaleMs}ms', progress: 0.58 + 0.24 * (i / max(1, saleCount)));
          await Future<void>.delayed(Duration.zero);
        }
      }
    });
  }

  Future<void> _runActiveSync() async {
    final identity = store.appIdentity;
    _setStatus('Running active sync...', progress: 0.84);
    _addLog(_snapshotLine('BEFORE_SYNC'));
    await _measure('Active sync role=${_roleLabel()} transport=${identity.activeSyncTransportNormalized}', () async {
      // Important diagnostic fix:
      // A Host must never run the LAN client push/pull/rebuild flow. Its LAN role
      // is to keep serving local clients. When Cloud is enabled, the Host's
      // active sync responsibility is to publish its authoritative changes to
      // Cloud so Cloud clients can pull the complete store state.
      if (identity.isHost) {
        if (identity.isCloudEnabled || CloudSyncSettings.load().isConfigured) {
          _addLog('Host active sync route: Cloud host push/pull. LAN host will not run client pull.');
          final result = await UnifiedSyncFactory.cloudEngine(store, enabled: true).syncNow(onProgress: (value, label) {
            _setStatus('Host Cloud Sync: $label', progress: 0.84 + 0.10 * value);
            _addLog('Sync progress ${(value * 100).toStringAsFixed(0)}% $label');
          });
          _addLog('Sync result ok=${result.ok} message=${result.message} cursor=${result.cursor.value} source=${result.cursor.source}');
          return;
        }

        _addLog('Host active sync route: LAN host only. No LAN client pull will run on Host.');
        final result = await UnifiedSyncFactory.lanEngine(store).registerCurrentHost(transportName: 'lan');
        _addLog('Sync result ok=${result.ok} message=${result.message} cursor=${result.cursor.value} source=${result.cursor.source}');
        return;
      }

      final transport = identity.activeSyncTransportNormalized;
      final engine = transport == 'cloud'
          ? UnifiedSyncFactory.cloudEngine(store)
          : transport == 'lan'
              ? UnifiedSyncFactory.lanEngine(store)
              : identity.isCloudEnabled
                  ? UnifiedSyncFactory.cloudEngine(store)
                  : UnifiedSyncFactory.lanEngine(store);
      final result = await engine.syncNow(onProgress: (value, label) {
        _setStatus('Sync: $label', progress: 0.84 + 0.10 * value);
        _addLog('Sync progress ${(value * 100).toStringAsFixed(0)}% $label');
      });
      _addLog('Sync result ok=${result.ok} message=${result.message} cursor=${result.cursor.value} source=${result.cursor.source}');
    });
    _addLog(_snapshotLine('AFTER_SYNC'));
  }

  Future<void> _compactSyncedSyncHistory() async {
    if (_running) return;
    setState(() => _running = true);
    try {
      _setStatus('Compacting synced sync history...', progress: 0.05);
      _addLog(_snapshotLine('BEFORE_COMPACT_SYNC_HISTORY'));
      final result = await store.compactSyncedSyncHistoryForDiagnostics();
      _addLog("Compact synced sync history result removedChanges=${result['removedChanges']} removedQueue=${result['removedQueue']} remainingChanges=${result['remainingChanges']} remainingQueue=${result['remainingQueue']} pendingChanges=${result['pendingChanges']} pendingQueue=${result['pendingQueue']} safeFloorSequence=${result['safeFloorSequence']} earliestSequence=${result['earliestSequence']} latestSequence=${result['latestSequence']}");
      _addLog(_snapshotLine('AFTER_COMPACT_SYNC_HISTORY'));
      _setStatus('Compaction completed.', progress: 1);
    } catch (error, stack) {
      _addLog('COMPACT_SYNC_HISTORY_FAILED $error');
      debugPrint('$stack');
      _setStatus('Compaction failed: $error', progress: 1);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _exportBackupProbe() async {
    _setStatus('Exporting backup probe...', progress: 0.96);
    await _measure('Export backup probe', () async {
      final raw = store.exportBackupJson();
      _addLog('Backup probe sizeBytes=${raw.length} sizeMB=${(raw.length / 1024 / 1024).toStringAsFixed(2)}');
      _logDatabaseMetrics('BACKUP_PROBE_DB');
    });
  }


  Future<void> _runDailyOperationsTest() async {
    if (_running) return;
    setState(() {
      _running = true;
      _progress = 0;
      _status = 'Starting daily operations test...';
      _currentBatchId = 'daily_${DateTime.now().millisecondsSinceEpoch}_${_roleLabel().toLowerCase()}';
    });

    try {
      _addLog('VENTIO_DAILY_OPERATIONS_START batch=$_currentBatchId buildMode=${kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug')}');
      _addLog(_snapshotLine('DAILY_BEFORE'));
      _logDatabaseMetrics('DAILY_BEFORE_DB');

      final hasStressProducts = store.products.any((item) => item.name.contains('[STRESS]') && !item.isDeleted);
      if (!hasStressProducts) {
        _addLog('Daily operations found no stress catalog. Seeding baseline catalog first.');
        await _seedCatalog();
      }

      await _runDailyOperationsMix();
      await _runActiveSync();
      await _exportBackupProbe();
      _logDatabaseMetrics('DAILY_AFTER_DB');
      _addLog(_snapshotLine('DAILY_AFTER'));
      _addHealthSummary('DAILY_OPERATIONS_SUMMARY');
      _addLog('VENTIO_DAILY_OPERATIONS_DONE batch=$_currentBatchId');
      _setStatus('Daily operations done', progress: 1);
    } catch (error, stack) {
      _addLog('VENTIO_DAILY_OPERATIONS_FAILED batch=$_currentBatchId error=$error');
      _addLog(stack.toString().split('\n').take(8).join(' | '));
      _setStatus('Daily operations failed: $error', progress: 1);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _runDailyOperationsMix() async {
    final baseSales = max(20, _readInt(_salesController, 500));
    final progressEvery = max(1, _readInt(_progressEveryController, 25));
    final stressProducts = store.products.where((item) => item.name.contains('[STRESS]') && item.stock > 10 && !item.isDeleted).toList();
    final stressCustomers = store.customers.where((item) => item.name.contains('[STRESS]') && !item.isDeleted).toList();
    final stressSuppliers = store.suppliers.where((item) => item.name.contains('[STRESS]') && !item.isDeleted).toList();
    if (stressProducts.isEmpty) throw StateError('No stress products available for daily operations.');

    final salesToCreate = max(1, (baseSales * 0.60).round());
    final productUpdates = min(stressProducts.length, max(1, (baseSales * 0.10).round()));
    final purchasesToCreate = max(1, (baseSales * 0.10).round());
    final expensesToCreate = max(1, (baseSales * 0.05).round());
    final salesToCancel = max(1, (baseSales * 0.05).round());
    final softDeletes = min(stressProducts.length, max(1, (baseSales * 0.03).round()));

    await _measure('Daily product updates count=$productUpdates', () async {
      for (var i = 0; i < productUpdates; i++) {
        final product = stressProducts[i % stressProducts.length];
        await store.addOrUpdateProduct(product.copyWith(
          name: '${product.name} upd${DateTime.now().millisecondsSinceEpoch % 100000}',
          price: product.price + 0.25 + (i % 7),
          cost: max(0.1, product.cost + 0.05),
          clearDeletedAt: true,
        ));
        if ((i + 1) % progressEvery == 0 || i + 1 == productUpdates) {
          _addLog('Daily product updates ${i + 1}/$productUpdates ${_snapshotLine('SNAPSHOT')}');
          _setStatus('Daily product updates ${i + 1}/$productUpdates', progress: 0.06 + 0.12 * ((i + 1) / max(1, productUpdates)));
          await Future<void>.delayed(Duration.zero);
        }
      }
    });

    await _measure('Daily mixed sales count=$salesToCreate', () async {
      for (var i = 1; i <= salesToCreate; i++) {
        final itemCount = 1 + _random.nextInt(min(5, stressProducts.length));
        final selected = <Product>[];
        while (selected.length < itemCount) {
          final product = stressProducts[_random.nextInt(stressProducts.length)];
          if (!selected.any((item) => item.id == product.id)) selected.add(product);
        }
        final items = selected.map((product) {
          final qty = 1 + _random.nextInt(3);
          return SaleItem(
            productId: product.id,
            productName: product.name,
            unitPrice: product.price,
            quantity: qty.toDouble(),
            unitCost: product.usdCost,
            unitName: product.unit,
            baseQuantity: qty.toDouble(),
            conversionToBase: 1,
          );
        }).toList();
        final customer = stressCustomers.isEmpty ? AppStore.walkInCustomerName : stressCustomers[_random.nextInt(stressCustomers.length)].name;
        await store.createSale(customerName: customer, items: items, paymentMethod: i.isEven ? 'Cash' : 'Card');
        if (i == 1 || i % progressEvery == 0 || i == salesToCreate) {
          _addLog('Daily sales $i/$salesToCreate ${_snapshotLine('SNAPSHOT')}');
          _setStatus('Daily sales $i/$salesToCreate', progress: 0.20 + 0.30 * (i / max(1, salesToCreate)));
          await Future<void>.delayed(Duration.zero);
        }
      }
    });

    await _measure('Daily purchases count=$purchasesToCreate', () async {
      for (var i = 1; i <= purchasesToCreate; i++) {
        final supplier = stressSuppliers.isEmpty ? null : stressSuppliers[_random.nextInt(stressSuppliers.length)];
        final product = stressProducts[_random.nextInt(stressProducts.length)];
        await store.createPurchase(
          supplierId: supplier?.id ?? 'stress_supplier',
          supplierName: supplier?.name ?? '[STRESS] Supplier',
          receiveNow: i.isEven,
          note: 'Daily operations generated purchase $_currentBatchId #$i',
          items: [
            PurchaseItem(
              productId: product.id,
              productName: product.name,
              quantity: (5 + _random.nextInt(10)).toDouble(),
              unitCost: max(0.1, product.usdCost),
              purchaseUnitName: product.unit,
              conversionToBase: 1,
            ),
          ],
        );
        if (i == 1 || i % progressEvery == 0 || i == purchasesToCreate) {
          _addLog('Daily purchases $i/$purchasesToCreate ${_snapshotLine('SNAPSHOT')}');
          _setStatus('Daily purchases $i/$purchasesToCreate', progress: 0.52 + 0.12 * (i / max(1, purchasesToCreate)));
          await Future<void>.delayed(Duration.zero);
        }
      }
    });

    await _measure('Daily expenses count=$expensesToCreate', () async {
      for (var i = 1; i <= expensesToCreate; i++) {
        final now = DateTime.now();
        await store.addOrUpdateExpense(Expense(
          id: '${_currentBatchId}_expense_$i',
          title: '[STRESS] Daily expense $i',
          category: i.isEven ? 'Utilities' : 'Operations',
          amount: 3 + (i % 50).toDouble(),
          date: now,
          notes: 'Generated by Daily Operations Stress Lab',
        ));
        if (i == 1 || i % progressEvery == 0 || i == expensesToCreate) {
          _addLog('Daily expenses $i/$expensesToCreate ${_snapshotLine('SNAPSHOT')}');
          _setStatus('Daily expenses $i/$expensesToCreate', progress: 0.66 + 0.06 * (i / max(1, expensesToCreate)));
          await Future<void>.delayed(Duration.zero);
        }
      }
    });

    await _measure('Daily cancellations count=$salesToCancel', () async {
      final cancellableSales = store.sales.where((sale) => !sale.isCancelled && sale.items.isNotEmpty).take(salesToCancel).toList();
      for (var i = 0; i < cancellableSales.length; i++) {
        await store.cancelSale(cancellableSales[i].id, restoreStock: true);
        _addLog('Daily cancel sale ${i + 1}/${cancellableSales.length} ${_snapshotLine('SNAPSHOT')}');
        _setStatus('Daily cancellations ${i + 1}/${cancellableSales.length}', progress: 0.74 + 0.06 * ((i + 1) / max(1, cancellableSales.length)));
        await Future<void>.delayed(Duration.zero);
      }
    });

    await _measure('Daily safe soft deletes target=$softDeletes', () async {
      final deletableProducts = stressProducts.where((product) => !store.isProductReferenced(product.id)).toList();
      var deleted = 0;
      var skipped = 0;
      for (final product in deletableProducts.take(softDeletes)) {
        await store.deleteProduct(product.id);
        deleted++;
        if (deleted % progressEvery == 0 || deleted == softDeletes || deleted == deletableProducts.length) {
          _addLog('Daily safe soft deletes deleted=$deleted skippedReferenced=$skipped target=$softDeletes ${_snapshotLine('SNAPSHOT')}');
          _setStatus('Daily safe soft deletes $deleted/$softDeletes', progress: 0.82 + 0.06 * (deleted / max(1, softDeletes)));
          await Future<void>.delayed(Duration.zero);
        }
      }
      skipped = stressProducts.length - deletableProducts.length;
      if (deleted == 0 || deleted < softDeletes) {
        _addLog('Daily safe soft deletes completed deleted=$deleted skippedReferenced=$skipped target=$softDeletes note=Referenced products are protected from deletion.');
      }
    });
  }

  Future<void> _waitForAutoSyncCheck() async {
    if (_running) return;
    setState(() {
      _running = true;
      _progress = 0;
      _status = 'Waiting for Auto Sync...';
    });
    try {
      _addLog('AUTO_SYNC_WAIT_START seconds=60');
      _addLog(_snapshotLine('AUTO_SYNC_BEFORE_WAIT'));
      _logDatabaseMetrics('AUTO_SYNC_BEFORE_WAIT_DB');
      for (var second = 1; second <= 60; second++) {
        await Future<void>.delayed(const Duration(seconds: 1));
        if (second % 15 == 0 || second == 60) {
          _addLog('AUTO_SYNC_WAIT_PROGRESS second=$second ${_snapshotLine('SNAPSHOT')}');
        }
        _setStatus('Waiting for Auto Sync $second/60 sec', progress: second / 60);
      }
      _addLog(_snapshotLine('AUTO_SYNC_AFTER_WAIT'));
      _logDatabaseMetrics('AUTO_SYNC_AFTER_WAIT_DB');
      _addHealthSummary('AUTO_SYNC_WAIT_SUMMARY');
      _addLog('AUTO_SYNC_WAIT_DONE');
      _setStatus('Auto Sync wait done', progress: 1);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _runLateClientGuardCheck() async {
    if (_running) return;
    setState(() {
      _running = true;
      _progress = 0;
      _status = 'Checking late-client guard...';
    });
    try {
      final sequenced = store.syncChanges.where((change) => change.sequence > 0).map((change) => change.sequence).toList()..sort();
      final earliest = sequenced.isEmpty ? 0 : sequenced.first;
      final latest = sequenced.isEmpty ? store.currentSyncSequence : sequenced.last;
      final simulatedClientSeq = earliest > 1 ? earliest - 1 : 0;
      _addLog('LATE_CLIENT_GUARD_CHECK role=${_roleLabel()} simulatedClientSeq=$simulatedClientSeq earliestSequence=$earliest latestSequence=$latest currentSeq=${store.currentSyncSequence}');
      if (earliest > 0 && simulatedClientSeq < earliest) {
        _addLog('LATE_CLIENT_GUARD_EXPECTED_RESULT needsSnapshot=true reason=client_seq_older_than_earliest_available');
      } else {
        _addLog('LATE_CLIENT_GUARD_INCONCLUSIVE reason=no_compacted_sequence_window_yet');
      }
      _addHealthSummary('LATE_CLIENT_GUARD_SUMMARY');
      _setStatus('Late-client guard check done', progress: 1);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  void _addHealthSummary(String label) {
    final rejectedQueue = store.syncQueue.where((item) => item.status.toLowerCase() == 'rejected').length;
    final failedQueue = store.syncQueue.where((item) => item.status.toLowerCase() == 'failed').length;
    final pendingQueue = store.pendingSyncQueue.length;
    final pendingChanges = store.pendingSyncChanges.length;
    final changes = store.syncChanges.length;
    final queue = store.syncQueue.length;
    final syncHealth = pendingQueue == 0 && pendingChanges == 0 && failedQueue == 0 && rejectedQueue == 0 ? 'PASS' : 'FAIL';
    final dbBloat = changes <= 250 && queue == 0 ? 'PASS' : 'FAIL';
    final dataHealth = store.products.isNotEmpty && store.sales.isNotEmpty ? 'PASS' : 'WARN';
    _addLog('$label SYNC_HEALTH=$syncHealth DB_BLOAT=$dbBloat DATA_HEALTH=$dataHealth '
        'products=${store.products.length} customers=${store.customers.length} suppliers=${store.suppliers.length} sales=${store.sales.length} '
        'purchases=${store.purchases.length} expenses=${store.expenses.length} stockMovements=${store.stockMovements.length} '
        'allChanges=$changes allQueue=$queue pendingQueue=$pendingQueue pendingChanges=$pendingChanges rejectedQueue=$rejectedQueue failedQueue=$failedQueue');
  }


  int _stableHash(Iterable<String> values) {
    var hash = 0x811c9dc5;
    final sorted = values.map((value) => value.trim()).where((value) => value.isNotEmpty).toList()..sort();
    for (final value in sorted) {
      for (final codeUnit in value.codeUnits) {
        hash ^= codeUnit;
        hash = (hash * 0x01000193) & 0xffffffff;
      }
      hash ^= 0x1f;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash;
  }

  String _hashHex(Iterable<String> values) => _stableHash(values).toRadixString(16).padLeft(8, '0').toUpperCase();

  String _sampleIds(Iterable<String> ids, {int limit = 8}) {
    final sorted = ids.where((id) => id.trim().isNotEmpty).toList()..sort();
    if (sorted.isEmpty) return '-';
    return sorted.take(limit).join(',');
  }

  void _logEntityDigest(String label, Iterable<String> ids, {Iterable<String> activeIds = const [], Iterable<String> deletedIds = const []}) {
    final all = ids.toList();
    final active = activeIds.toList();
    final deleted = deletedIds.toList();
    _addLog('$label count=${all.length} hash=${_hashHex(all)} activeCount=${active.isEmpty ? all.length : active.length} '
        'activeHash=${_hashHex(active.isEmpty ? all : active)} deletedCount=${deleted.length} deletedHash=${_hashHex(deleted)} sample=${_sampleIds(all)}');
  }

  Future<void> _compareDeviceState() async {
    if (_running) return;
    setState(() {
      _running = true;
      _status = 'Comparing local device state...';
      _progress = 0;
    });
    try {
      _addLog('COMPARE_DEVICE_STATE_START role=${_roleLabel()}');
      _addLog(_snapshotLine('COMPARE_SNAPSHOT'));
      _logEntityDigest('COMPARE_PRODUCTS', store.allProductsForDiagnostics.map((item) => item.id), activeIds: store.products.map((item) => item.id), deletedIds: store.allProductsForDiagnostics.where((item) => item.isDeleted).map((item) => item.id));
      _logEntityDigest('COMPARE_CUSTOMERS', store.customers.map((item) => item.id), activeIds: store.customers.where((item) => !item.isDeleted).map((item) => item.id));
      _logEntityDigest('COMPARE_SUPPLIERS', store.suppliers.map((item) => item.id), activeIds: store.suppliers.where((item) => !item.isDeleted).map((item) => item.id));
      _logEntityDigest('COMPARE_SALES', store.sales.map((item) => item.id), activeIds: store.sales.where((item) => !item.isDeleted).map((item) => item.id));
      _logEntityDigest('COMPARE_PURCHASES', store.purchases.map((item) => item.id), activeIds: store.purchases.where((item) => !item.isDeleted).map((item) => item.id));
      _logEntityDigest('COMPARE_EXPENSES', store.expenses.map((item) => item.id), activeIds: store.expenses.where((item) => !item.isDeleted).map((item) => item.id));
      _logEntityDigest('COMPARE_STOCK_MOVEMENTS', store.stockMovements.map((item) => item.id));
      _logEntityDigest('COMPARE_CATEGORIES', store.categories.map((item) => item.id));
      _logEntityDigest('COMPARE_BRANDS', store.brands.map((item) => item.id));
      _logEntityDigest('COMPARE_UNITS', store.units.map((item) => item.id));
      _addLog('COMPARE_DEVICE_STATE_DONE note=Run this on each device and compare count/hash lines. Different hashes mean different IDs.');
      _setStatus('Device state comparison logged', progress: 1);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _runSequenceAudit() async {
    if (_running) return;
    setState(() {
      _running = true;
      _status = 'Running sequence audit...';
      _progress = 0;
    });
    try {
      final sequenced = store.syncChanges.where((change) => change.sequence > 0).map((change) => change.sequence).toList()..sort();
      final earliest = sequenced.isEmpty ? 0 : sequenced.first;
      final latest = sequenced.isEmpty ? 0 : sequenced.last;
      final unique = sequenced.toSet();
      final duplicateCount = sequenced.length - unique.length;
      final missing = <int>[];
      if (earliest > 0 && latest >= earliest) {
        for (var seq = earliest; seq <= latest && missing.length < 50; seq++) {
          if (!unique.contains(seq)) missing.add(seq);
        }
      }
      final byDevice = <String, int>{};
      for (final change in store.syncChanges) {
        final key = change.deviceId.isEmpty ? 'unknown' : change.deviceId;
        byDevice[key] = (byDevice[key] ?? 0) + 1;
      }
      final byEntity = <String, int>{};
      for (final change in store.syncChanges) {
        final key = change.entityType.isEmpty ? 'unknown' : change.entityType;
        byEntity[key] = (byEntity[key] ?? 0) + 1;
      }
      _addLog('SEQUENCE_AUDIT role=${_roleLabel()} currentSeq=${store.currentSyncSequence} sequencedChanges=${sequenced.length} earliestSequence=$earliest latestSequence=$latest duplicateSequences=$duplicateCount missingSequenceSample=${missing.isEmpty ? '-' : missing.join(',')}');
      _addLog('SEQUENCE_AUDIT_BY_DEVICE ${byDevice.entries.map((entry) => '${entry.key}:${entry.value}').join(' ')}');
      _addLog('SEQUENCE_AUDIT_BY_ENTITY ${byEntity.entries.map((entry) => '${entry.key}:${entry.value}').join(' ')}');
      _setStatus('Sequence audit logged', progress: 1);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _runPendingAudit() async {
    if (_running) return;
    setState(() {
      _running = true;
      _status = 'Running pending audit...';
      _progress = 0;
    });
    try {
      final byStatus = <String, int>{};
      for (final item in store.syncQueue) {
        byStatus[item.status] = (byStatus[item.status] ?? 0) + 1;
      }
      final pending = store.syncQueue.where((item) => item.isPending || item.isInProgress || item.isFailed || item.isRejected).take(30).toList();
      _addLog('PENDING_AUDIT queueTotal=${store.syncQueue.length} changesTotal=${store.syncChanges.length} pendingQueue=${store.pendingSyncQueue.length} pendingChanges=${store.pendingSyncChanges.length} queueByStatus=${byStatus.entries.map((entry) => '${entry.key}:${entry.value}').join(' ')}');
      if (pending.isEmpty) {
        _addLog('PENDING_AUDIT_SAMPLE none');
      } else {
        for (final item in pending) {
          final matches = store.syncChanges.where((change) => change.id == item.changeId).toList();
          final change = matches.isEmpty ? null : matches.first;
          _addLog('PENDING_AUDIT_ITEM queueId=${item.id} changeId=${item.changeId} status=${item.status} target=${item.target} attempts=${item.attempts} updatedAt=${item.updatedAt.toIso8601String()} changeEntity=${change?.entityType ?? '-'} changeEntityId=${change?.entityId ?? '-'} changeSeq=${change?.sequence ?? '-'} changeSynced=${change?.isSynced ?? '-'} error=${item.lastError.replaceAll('\n', ' ')}');
        }
      }
      _setStatus('Pending audit logged', progress: 1);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _runDuplicateDetection() async {
    if (_running) return;
    setState(() {
      _running = true;
      _status = 'Running duplicate detection...';
      _progress = 0;
    });
    try {
      List<String> duplicates(Iterable<String> values) {
        final counts = <String, int>{};
        for (final value in values.where((value) => value.trim().isNotEmpty)) {
          counts[value] = (counts[value] ?? 0) + 1;
        }
        return counts.entries.where((entry) => entry.value > 1).map((entry) => '${entry.key}:${entry.value}').take(30).toList();
      }
      final duplicateChangeIds = duplicates(store.syncChanges.map((change) => change.id));
      final duplicateEventKeys = duplicates(store.syncChanges.map((change) => '${change.entityType}:${change.entityId}:${change.operation}:${change.sequence}'));
      final duplicateEntityIds = duplicates(store.syncChanges.map((change) => '${change.entityType}:${change.entityId}:${change.operation}'));
      final duplicateQueueChangeIds = duplicates(store.syncQueue.map((item) => item.changeId));
      _addLog('DUPLICATE_DETECTION duplicateChangeIds=${duplicateChangeIds.isEmpty ? 0 : duplicateChangeIds.length} sample=${duplicateChangeIds.isEmpty ? '-' : duplicateChangeIds.join(',')}');
      _addLog('DUPLICATE_DETECTION duplicateEventKeys=${duplicateEventKeys.isEmpty ? 0 : duplicateEventKeys.length} sample=${duplicateEventKeys.isEmpty ? '-' : duplicateEventKeys.join(',')}');
      _addLog('DUPLICATE_DETECTION duplicateEntityOperationKeys=${duplicateEntityIds.isEmpty ? 0 : duplicateEntityIds.length} sample=${duplicateEntityIds.isEmpty ? '-' : duplicateEntityIds.join(',')}');
      _addLog('DUPLICATE_DETECTION duplicateQueueChangeIds=${duplicateQueueChangeIds.isEmpty ? 0 : duplicateQueueChangeIds.length} sample=${duplicateQueueChangeIds.isEmpty ? '-' : duplicateQueueChangeIds.join(',')}');
      _setStatus('Duplicate detection logged', progress: 1);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _runSyncHistoryInspector() async {
    if (_running) return;
    setState(() {
      _running = true;
      _status = 'Inspecting sync history...';
      _progress = 0;
    });
    try {
      final authoritative = store.syncChanges.where((change) => change.sequence > 0).length;
      final localDraft = store.syncChanges.where((change) => change.sequence <= 0).length;
      final syncedDraft = store.syncChanges.where((change) => change.sequence <= 0 && change.isSynced).length;
      final unsyncedDraft = store.syncChanges.where((change) => change.sequence <= 0 && !change.isSynced).length;
      final syncedAuthoritative = store.syncChanges.where((change) => change.sequence > 0 && change.isSynced).length;
      final unsyncedAuthoritative = store.syncChanges.where((change) => change.sequence > 0 && !change.isSynced).length;
      final zeroSeqSample = store.syncChanges.where((change) => change.sequence <= 0).take(20).map((change) => '${change.id}/${change.entityType}/${change.entityId}/${change.operation}/synced=${change.isSynced}').join(' | ');
      _addLog('SYNC_HISTORY_INSPECTOR total=${store.syncChanges.length} authoritative=$authoritative localDraft=$localDraft syncedDraft=$syncedDraft unsyncedDraft=$unsyncedDraft syncedAuthoritative=$syncedAuthoritative unsyncedAuthoritative=$unsyncedAuthoritative queue=${store.syncQueue.length}');
      _addLog('SYNC_HISTORY_ZERO_SEQUENCE_SAMPLE ${zeroSeqSample.isEmpty ? '-' : zeroSeqSample}');
      _setStatus('Sync history inspection logged', progress: 1);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _runDatabaseSizeBreakdown() async {
    if (_running) return;
    setState(() {
      _running = true;
      _status = 'Calculating DB size breakdown...';
      _progress = 0;
    });
    try {
      final entries = LocalDatabaseService.allEntries();
      _addLog('DB_SIZE_BREAKDOWN_START keys=${entries.length}');
      final sorted = entries.entries.toList()
        ..sort((a, b) => (utf8.encode(b.key).length + utf8.encode(b.value).length).compareTo(utf8.encode(a.key).length + utf8.encode(a.value).length));
      var total = 0;
      for (final entry in sorted) {
        final bytes = utf8.encode(entry.key).length + utf8.encode(entry.value).length;
        total += bytes;
        _addLog('DB_SIZE_KEY key=${entry.key} bytes=$bytes mb=${(bytes / 1024 / 1024).toStringAsFixed(3)}');
      }
      _addLog('DB_SIZE_BREAKDOWN_TOTAL bytes=$total mb=${(total / 1024 / 1024).toStringAsFixed(3)}');
      _setStatus('DB size breakdown logged', progress: 1);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _runIntegrityCheck() async {
    if (_running) return;
    setState(() {
      _running = true;
      _status = 'Running integrity check...';
      _progress = 0;
    });
    try {
      final productIds = store.allProductsForDiagnostics.map((item) => item.id).toSet();
      final saleIds = store.sales.map((item) => item.id).toSet();
      final purchaseIds = store.purchases.map((item) => item.id).toSet();
      final saleItemMissingProducts = <String>[];
      for (final sale in store.sales) {
        for (final item in sale.items) {
          if (!productIds.contains(item.productId)) saleItemMissingProducts.add('${sale.id}:${item.productId}');
          if (saleItemMissingProducts.length >= 30) break;
        }
        if (saleItemMissingProducts.length >= 30) break;
      }
      final purchaseItemMissingProducts = <String>[];
      for (final purchase in store.purchases) {
        for (final item in purchase.items) {
          if (!productIds.contains(item.productId)) purchaseItemMissingProducts.add('${purchase.id}:${item.productId}');
          if (purchaseItemMissingProducts.length >= 30) break;
        }
        if (purchaseItemMissingProducts.length >= 30) break;
      }
      final stockMissingProducts = store.stockMovements.where((movement) => movement.productId.isNotEmpty && !productIds.contains(movement.productId)).take(30).map((movement) => '${movement.id}:${movement.productId}').toList();
      final stockMissingReferences = store.stockMovements.where((movement) {
        final reference = movement.referenceId;
        if (reference.isEmpty) return false;
        final type = movement.type.toLowerCase();
        if (type.contains('sale')) return !saleIds.contains(reference);
        if (type.contains('purchase')) return !purchaseIds.contains(reference);
        return false;
      }).take(30).map((movement) => '${movement.id}:${movement.type}:${movement.referenceId}').toList();
      final pass = saleItemMissingProducts.isEmpty && purchaseItemMissingProducts.isEmpty && stockMissingProducts.isEmpty && stockMissingReferences.isEmpty;
      _addLog('INTEGRITY_CHECK result=${pass ? 'PASS' : 'WARN'} saleItemMissingProducts=${saleItemMissingProducts.length} purchaseItemMissingProducts=${purchaseItemMissingProducts.length} stockMissingProducts=${stockMissingProducts.length} stockMissingReferences=${stockMissingReferences.length}');
      if (saleItemMissingProducts.isNotEmpty) _addLog('INTEGRITY_SALE_ITEM_MISSING_PRODUCTS sample=${saleItemMissingProducts.join(',')}');
      if (purchaseItemMissingProducts.isNotEmpty) _addLog('INTEGRITY_PURCHASE_ITEM_MISSING_PRODUCTS sample=${purchaseItemMissingProducts.join(',')}');
      if (stockMissingProducts.isNotEmpty) _addLog('INTEGRITY_STOCK_MISSING_PRODUCTS sample=${stockMissingProducts.join(',')}');
      if (stockMissingReferences.isNotEmpty) _addLog('INTEGRITY_STOCK_MISSING_REFERENCES sample=${stockMissingReferences.join(',')}');
      _setStatus('Integrity check logged', progress: 1);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _runAllDiagnostics() async {
    if (_running) return;
    await _compareDeviceState();
    await _runSequenceAudit();
    await _runLateClientGuardCheck();
    await _runPendingAudit();
    await _runDuplicateDetection();
    await _runSyncHistoryInspector();
    await _runDatabaseSizeBreakdown();
    await _runIntegrityCheck();
    await _generateTestSummary();
  }

  Future<void> _generateTestSummary() async {
    _addLog(_snapshotLine('MANUAL_SUMMARY_SNAPSHOT'));
    _logDatabaseMetrics('MANUAL_SUMMARY_DB');
    _addHealthSummary('MANUAL_TEST_SUMMARY');
  }

  Future<void> _copyLog() async {
    final text = _log.join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copied ${_log.length} log lines')));
  }

  Future<void> _clearLog() async {
    setState(() => _log.clear());
  }

  Widget _numberField(String label, TextEditingController controller) {
    return SizedBox(
      width: 170,
      child: TextField(
        controller: controller,
        enabled: !_running,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      ),
    );
  }

  Future<void> _runCompleteLab() async {
    if (_running) return;
    await _runFullSimulation();
    await _waitForAutoSyncCheck();
    await _runAllDiagnostics();
  }

  @override
  Widget build(BuildContext context) {
    final identity = store.appIdentity;
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ventio Stress Lab', style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    Text('Temporary real-app simulation. Uses the real AppStore services, stock logic, sync queue, and active sync transport. Log stays in memory until Clear Log is pressed.'),
                    const SizedBox(height: 8),
                    Text('Role: ${_roleLabel()} • Device: ${identity.deviceId} • Transport: ${identity.activeSyncTransportNormalized} • Epoch: ${identity.storeEpoch}'),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _numberField('Products', _productsController),
                        _numberField('Customers', _customersController),
                        _numberField('Suppliers', _suppliersController),
                        _numberField('Sales', _salesController),
                        _numberField('Progress every', _progressEveryController),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ActionChip(label: const Text('Small'), onPressed: _running ? null : () => _applyPreset(products: 100, customers: 50, suppliers: 10, sales: 50, progressEvery: 10)),
                        ActionChip(label: const Text('Medium'), onPressed: _running ? null : () => _applyPreset(products: 1000, customers: 500, suppliers: 100, sales: 500, progressEvery: 25)),
                        ActionChip(label: const Text('Heavy'), onPressed: _running ? null : () => _applyPreset(products: 3000, customers: 1500, suppliers: 300, sales: 1500, progressEvery: 50)),
                        ActionChip(label: const Text('Sync Bloat'), onPressed: _running ? null : () => _applyPreset(products: 1500, customers: 750, suppliers: 150, sales: 750, progressEvery: 25)),
                        ActionChip(label: const Text('Daily Ops'), onPressed: _running ? null : () => _applyPreset(products: 500, customers: 250, suppliers: 50, sales: 300, progressEvery: 20)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(value: _running ? _progress : null),
                    const SizedBox(height: 8),
                    Text(_status),
                    const SizedBox(height: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FilledButton.icon(
                          onPressed: _running ? null : _runCompleteLab,
                          icon: const Icon(Icons.health_and_safety_outlined),
                          label: const Text('Run Complete Lab'),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _log.isEmpty ? null : _copyLog,
                              icon: const Icon(Icons.copy),
                              label: const Text('Copy Log'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _running ? null : _clearLog,
                              icon: const Icon(Icons.clear_all),
                              label: const Text('Clear Log'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: const Text('Advanced Diagnostics'),
                          children: [
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: _running ? null : _runFullSimulation,
                                    icon: const Icon(Icons.science),
                                    label: const Text('Real App Stress'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: _running ? null : _runDailyOperationsTest,
                                    icon: const Icon(Icons.storefront),
                                    label: const Text('Daily Operations'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: _running ? null : _waitForAutoSyncCheck,
                                    icon: const Icon(Icons.timer),
                                    label: const Text('Wait Auto Sync'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: _running ? null : _runAllDiagnostics,
                                    icon: const Icon(Icons.manage_search),
                                    label: const Text('Run All Diagnostics'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: _running ? null : _compareDeviceState,
                                    icon: const Icon(Icons.compare_arrows),
                                    label: const Text('Compare State'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: _running ? null : _runSequenceAudit,
                                    icon: const Icon(Icons.format_list_numbered),
                                    label: const Text('Sequence Audit'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: _running ? null : _runPendingAudit,
                                    icon: const Icon(Icons.pending_actions),
                                    label: const Text('Pending Audit'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: _running ? null : _runDatabaseSizeBreakdown,
                                    icon: const Icon(Icons.storage),
                                    label: const Text('DB Size'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: _running ? null : _runIntegrityCheck,
                                    icon: const Icon(Icons.verified_outlined),
                                    label: const Text('Integrity'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: _running ? null : _runActiveSync,
                                    icon: const Icon(Icons.sync),
                                    label: const Text('Sync Now Only'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: _running ? null : _compactSyncedSyncHistory,
                                    icon: const Icon(Icons.cleaning_services_outlined),
                                    label: const Text('Clean Sync Logs'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _log.isEmpty
                    ? const Center(child: Text('No log yet.'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _log.length,
                        itemBuilder: (context, index) => SelectableText(
                          _log[index],
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
