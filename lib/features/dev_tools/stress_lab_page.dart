// ignore_for_file: unused_element, unused_field, unused_import
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';
import 'package:flutter/services.dart';

import '../../core/services/cloud_sync_service.dart';
import '../../core/services/local_database_service.dart';
import '../../core/services/lan_sync_service.dart';
import '../../core/services/accounting_service.dart';
import '../../core/sync_unified/sync_unified.dart';
import '../../data/app_store.dart';
import '../../models/account_transaction.dart';
import '../../models/catalog_item.dart';
import '../../models/customer.dart';
import '../../models/expense.dart';
import '../../models/product.dart';
import '../../models/purchase.dart';
import '../../models/warehouse.dart';
import '../../models/sale_quotation.dart';
import '../../models/delivery_note.dart';
import '../../models/purchase_item.dart';
import '../../models/sale_item.dart';
import '../../models/sale.dart';
import '../../models/supplier.dart';
import '../../models/supplier_product_price.dart';
import '../../models/manufacturing.dart';
import '../maintenance/maintenance_models.dart';
import '../maintenance/maintenance_service.dart';


class _StressAuditStep {
  const _StressAuditStep({
    required this.section,
    required this.name,
    required this.status,
    required this.details,
    required this.elapsedMs,
  });

  final String section;
  final String name;
  final String status;
  final String details;
  final int elapsedMs;

  bool get isPass => status == 'PASS';
  bool get isWarn => status == 'WARN';
  bool get isFail => status == 'FAIL';
}


class _StressAssertionResult {
  const _StressAssertionResult({
    required this.id,
    required this.area,
    required this.expected,
    required this.actual,
    required this.passed,
    this.blocking = true,
  });

  final String id;
  final String area;
  final String expected;
  final String actual;
  final bool passed;
  final bool blocking;

  String get status => passed ? 'PASS' : (blocking ? 'FAIL' : 'WARN');
  String get details => 'ASSERTION $id expected=[$expected] actual=[$actual] blocking=$blocking';
}


class _StressPerfStats {
  _StressPerfStats(this.section, this.name);

  final String section;
  final String name;
  static const int bucketSize = 100;
  int count = 0;
  int failed = 0;
  int totalMs = 0;
  int minMs = 1 << 30;
  int maxMs = 0;
  final List<int> _bucketTotals = <int>[];
  final List<int> _bucketCounts = <int>[];

  void add(int elapsedMs) {
    count += 1;
    totalMs += elapsedMs;
    if (elapsedMs < minMs) minMs = elapsedMs;
    if (elapsedMs > maxMs) maxMs = elapsedMs;
    final bucket = max<int>(0, (count - 1) ~/ bucketSize);
    while (_bucketTotals.length <= bucket) {
      _bucketTotals.add(0);
      _bucketCounts.add(0);
    }
    _bucketTotals[bucket] += elapsedMs;
    _bucketCounts[bucket] += 1;
  }

  void addFail() {
    failed += 1;
  }

  double get avgMs => count == 0 ? 0 : totalMs / count;
  double get opsPerSecond => totalMs <= 0 ? 0 : count * 1000 / totalMs;

  double get firstBucketAvg => _bucketCounts.isEmpty || _bucketCounts.first == 0 ? avgMs : _bucketTotals.first / _bucketCounts.first;
  double get lastBucketAvg => _bucketCounts.isEmpty || _bucketCounts.last == 0 ? avgMs : _bucketTotals.last / _bucketCounts.last;
  double get slowdownRatio => firstBucketAvg <= 0 ? 1 : lastBucketAvg / firstBucketAvg;
  bool get hasSlowdownWarning => count >= bucketSize * 3 && slowdownRatio >= 1.8;

  String get curve {
    if (_bucketCounts.isEmpty) return 'curve=none';
    final parts = <String>[];
    for (var i = 0; i < _bucketCounts.length; i++) {
      final start = i * bucketSize;
      final end = start + _bucketCounts[i] - 1;
      final avg = _bucketCounts[i] == 0 ? 0 : _bucketTotals[i] / _bucketCounts[i];
      parts.add('$start-$end:${avg.toStringAsFixed(1)}ms');
    }
    return 'curve=${parts.join('|')} slowdown=${slowdownRatio.toStringAsFixed(2)}x';
  }

  String get summary => 'count=$count failed=$failed total=${totalMs}ms avg=${avgMs.toStringAsFixed(2)}ms min=${minMs == (1 << 30) ? 0 : minMs}ms max=${maxMs}ms ops/s=${opsPerSecond.toStringAsFixed(1)} $curve';
}

class _StressTraceStat {
  _StressTraceStat(this.phase);

  final String phase;
  int count = 0;
  int totalMs = 0;
  int maxMs = 0;
  final List<String> samples = <String>[];

  void add(int elapsedMs, Map<String, Object?> metadata) {
    count += 1;
    totalMs += elapsedMs;
    if (elapsedMs > maxMs) maxMs = elapsedMs;
    if (samples.length >= 3) return;
    final meta = metadata.entries
        .where((entry) => entry.value != null && entry.value.toString().isNotEmpty)
        .map((entry) => '${entry.key}=${entry.value}')
        .join(',');
    samples.add(meta);
  }

  double get avgMs => count == 0 ? 0 : totalMs / count;
  String get summary => '$phase avg=${avgMs.toStringAsFixed(1)}ms total=${totalMs}ms count=$count max=${maxMs}ms${samples.isEmpty ? '' : ' sample=${samples.join(' | ')}'}';
}

class StressLabPage extends StatefulWidget {
  const StressLabPage({super.key, required this.store});

  final AppStore store;

  @override
  State<StressLabPage> createState() => _StressLabPageState();
}

class _StressLabPageState extends State<StressLabPage> {
  String _t(String key) => AppLocalizations.of(context).text(key);
  String _tf(String key, Map<String, Object?> values) => AppLocalizations.of(context).format(key, values);
  final _productsController = TextEditingController(text: '1000');
  final _customersController = TextEditingController(text: '500');
  final _suppliersController = TextEditingController(text: '100');
  final _salesController = TextEditingController(text: '500');
  final _progressEveryController = TextEditingController(text: '25');
  static final List<String> _persistentLog = <String>[];
  static final List<Map<String, int>> _healthHistory = <Map<String, int>>[];
  final _log = _persistentLog;
  final _random = Random(52);
  final Map<String, _StressTraceStat> _traceStats = <String, _StressTraceStat>{};

  bool _running = false;
  double _progress = 0;
  String _status = 'Ready';
  String _currentBatchId = '';
  final List<_StressAuditStep> _report = <_StressAuditStep>[];
  final List<_StressAssertionResult> _assertions = <_StressAssertionResult>[];

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

  void _resetTraceCapture() {
    _traceStats.clear();
  }

  void _captureTrace(String section, String phase, int elapsedMs, Map<String, Object?> metadata) {
    final key = '$section::$phase';
    final stat = _traceStats.putIfAbsent(key, () => _StressTraceStat(phase));
    stat.add(elapsedMs, metadata);
  }

  String _traceSummaryForSection(String section) {
    final stats = _traceStats.values.toList();
    if (stats.isEmpty) return 'trace=none';
    stats.sort((a, b) => b.totalMs.compareTo(a.totalMs));
    final top = stats.take(3).map((stat) => stat.summary).join(' || ');
    return 'traceTop=$top';
  }

  void _setStatus(String value, {double? progress}) {
    if (!mounted) return;
    setState(() {
      _status = value;
      if (progress != null) _progress = progress.clamp(0, 1);
    });
  }


  String _effectiveSyncTransport() {
    final identity = store.appIdentity;
    final lan = LanSyncSettings.load();
    final cloud = CloudSyncSettings.load();
    final cloudActive = cloud.isConfigured && (identity.isCloudEnabled || identity.activeSyncTransportNormalized == 'cloud');
    final lanHostActive = identity.isHost && lan.setupComplete && lan.isHost;
    final lanClientActive = identity.isClient && lan.setupComplete && lan.isClient && identity.activeSyncTransportNormalized == 'lan';
    if (cloudActive) return 'cloud';
    if (lanHostActive || lanClientActive) return 'lan';
    return 'local';
  }

  String _roleLabel() {
    final identity = store.appIdentity;
    final transport = _effectiveSyncTransport();
    if (identity.isHost) return transport == 'cloud' ? 'HOST_CLOUD' : transport == 'lan' ? 'HOST_LAN' : 'HOST_LOCAL';
    if (identity.isClient && transport == 'cloud') return 'CLIENT_CLOUD';
    if (identity.isClient && transport == 'lan') return 'CLIENT_LAN';
    return 'LOCAL_${identity.deviceRole.name.toUpperCase()}';
  }

  String _snapshotLine(String label) {
    final identity = store.appIdentity;
    final rejectedQueue = store.syncQueue.where((item) => item.status.toLowerCase() == 'rejected').length;
    final failedQueue = store.syncQueue.where((item) => item.status.toLowerCase() == 'failed').length;
    return '$label role=${_roleLabel()} device=${identity.deviceId} store=${identity.storeId} branch=${identity.branchId} '
        'transport=${_effectiveSyncTransport()} identityTransport=${identity.activeSyncTransportNormalized} epoch=${identity.storeEpoch} seq=${store.currentSyncSequence} '
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
            conversionToBase: 1.0,
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
    final effectiveTransport = _effectiveSyncTransport();
    await _measure('Active sync role=${_roleLabel()} transport=$effectiveTransport', () async {
      // Important diagnostic fix:
      // A Host must never run the LAN client push/pull/rebuild flow. Its LAN role
      // is to keep serving local clients. When Cloud is enabled, the Host's
      // active sync responsibility is to publish its authoritative changes to
      // Cloud so Cloud clients can pull the complete store state.
      if (identity.isHost) {
        if (effectiveTransport == 'cloud') {
          _addLog('Host active sync route: Cloud host push/pull. LAN host will not run client pull.');
          final result = await UnifiedSyncFactory.cloudEngine(store, enabled: true).syncNow(onProgress: (value, label) {
            _setStatus('Host Cloud Sync: $label', progress: 0.84 + 0.10 * value);
            _addLog('Sync progress ${(value * 100).toStringAsFixed(0)}% $label');
          });
          _addLog('Sync result ok=${result.ok} message=${result.message} cursor=${result.cursor.value} source=${result.cursor.source}');
          return;
        }

        if (effectiveTransport == 'lan') {
          _addLog('Host active sync route: LAN host only. No LAN client pull will run on Host.');
          final result = await UnifiedSyncFactory.lanEngine(store).registerCurrentHost(transportName: 'lan');
          _addLog('Sync result ok=${result.ok} message=${result.message} cursor=${result.cursor.value} source=${result.cursor.source}');
          return;
        }

        _addLog('Host active sync route: local/offline. LAN is disabled and Cloud is not configured; no sync transport will run.');
        return;
      }

      final transport = effectiveTransport;
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
            conversionToBase: 1.0,
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
              conversionToBase: 1.0,
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
    final logicalBytes = _logicalDatabaseBytes();
    final backupBytes = store.exportBackupJson().length;

    final transport = _effectiveSyncTransport();
    final pendingIsExpectedForCloud = transport == 'cloud' && failedQueue == 0 && rejectedQueue == 0;
    final syncHealth = (pendingQueue == 0 && pendingChanges == 0 && failedQueue == 0 && rejectedQueue == 0) || pendingIsExpectedForCloud ? 'PASS' : 'FAIL';

    // DB_BLOAT used to treat every retained SyncChange above 250 as database
    // bloat. That rule was valid for the old legacy JSON storage/JSON storage path, where the
    // full sync history was serialized back into one large value. After the
    // SQLite migration, synced authoritative history is stored row-by-row and
    // does not indicate JSON/DB bloat by itself.
    //
    // What still indicates real bloat in the stress lab:
    // 1) legacy LocalDatabaseService keys growing close to the full backup size
    //    (means large typed entities are being mirrored as JSON again), or
    // 2) stale queue rows that remain although there is no pending/failed work.
    final legacyJsonBloat = logicalBytes > 1024 * 1024 && logicalBytes > (backupBytes / 2);
    final staleQueueBloat = queue > 0 && pendingQueue == 0 && failedQueue == 0 && rejectedQueue == 0;
    final dbBloat = !legacyJsonBloat && !staleQueueBloat ? 'PASS' : 'FAIL';
    final dbBloatReason = legacyJsonBloat
        ? 'legacy_json_cache'
        : staleQueueBloat
            ? 'stale_queue_rows'
            : 'none';

    final dataHealth = store.products.isNotEmpty && store.sales.isNotEmpty ? 'PASS' : 'WARN';
    _addLog('$label SYNC_HEALTH=$syncHealth DB_BLOAT=$dbBloat DATA_HEALTH=$dataHealth '
        'products=${store.products.length} customers=${store.customers.length} suppliers=${store.suppliers.length} sales=${store.sales.length} '
        'purchases=${store.purchases.length} expenses=${store.expenses.length} stockMovements=${store.stockMovements.length} '
        'allChanges=$changes allQueue=$queue pendingQueue=$pendingQueue pendingChanges=$pendingChanges rejectedQueue=$rejectedQueue failedQueue=$failedQueue '
        'logicalDbBytes=$logicalBytes backupBytes=$backupBytes dbBloatReason=$dbBloatReason syncMode=$transport pendingExpectedForCloud=$pendingIsExpectedForCloud');
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

  String _catalogDigestKey(CatalogItem item) {
    String normalize(String value) => value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final code = normalize(item.code);
    final nameEn = normalize(item.nameEn);
    final nameAr = normalize(item.nameAr);
    final deleted = item.isDeleted ? 'deleted' : 'active';
    // Catalog IDs for categories/brands/units may be generated locally on each
    // device. Diagnostics must compare the business identity, not the local ID,
    // otherwise healthy sync can report false hash mismatches.
    return '$code|$nameEn|$nameAr|$deleted';
  }

  void _logCatalogDigest(String label, Iterable<CatalogItem> items) {
    final allItems = items.toList();
    final all = allItems.map(_catalogDigestKey).toList();
    final active = allItems.where((item) => !item.isDeleted).map(_catalogDigestKey).toList();
    final deleted = allItems.where((item) => item.isDeleted).map(_catalogDigestKey).toList();
    final sample = allItems.map((item) {
      final code = item.code.trim().isEmpty ? '-' : item.code.trim();
      final en = item.nameEn.trim().isEmpty ? '-' : item.nameEn.trim();
      final ar = item.nameAr.trim().isEmpty ? '-' : item.nameAr.trim();
      return '$code:$en:$ar';
    }).toList();
    _addLog('$label count=${all.length} hash=${_hashHex(all)} activeCount=${active.length} '
        'activeHash=${_hashHex(active)} deletedCount=${deleted.length} deletedHash=${_hashHex(deleted)} sample=${_sampleIds(sample)} note=business-key-hash');
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
      _logCatalogDigest('COMPARE_CATEGORIES', store.categories);
      _logCatalogDigest('COMPARE_BRANDS', store.brands);
      _logCatalogDigest('COMPARE_UNITS', store.units);
      _addLog('COMPARE_DEVICE_STATE_DONE note=Run this on each device and compare count/hash lines. Catalog hashes use business fields, not local IDs.');
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


  Future<T?> _auditStep<T>(
    String section,
    String name,
    Future<T> Function() action, {
    String Function(T value)? successDetails,
  }) async {
    final sw = Stopwatch()..start();
    try {
      final result = await action();
      sw.stop();
      final details = successDetails?.call(result) ?? 'تم التنفيذ بنجاح.';
      _report.add(_StressAuditStep(section: section, name: name, status: 'PASS', details: details, elapsedMs: sw.elapsedMilliseconds));
      _addLog('AUDIT_STEP PASS [$section] $name ${sw.elapsedMilliseconds}ms $details');
      return result;
    } catch (error, stack) {
      sw.stop();
      final details = error.toString();
      _report.add(_StressAuditStep(section: section, name: name, status: 'FAIL', details: details, elapsedMs: sw.elapsedMilliseconds));
      _addLog('AUDIT_STEP FAIL [$section] $name ${sw.elapsedMilliseconds}ms $details');
      _addLog(stack.toString().split('\n').take(6).join(' | '));
      return null;
    }
  }

  void _auditCheck(String section, String name, bool condition, String passDetails, String failDetails, {bool warning = false}) {
    final status = condition ? 'PASS' : (warning ? 'WARN' : 'FAIL');
    final details = condition ? passDetails : failDetails;
    _report.add(_StressAuditStep(section: section, name: name, status: status, details: details, elapsedMs: 0));
    _addLog('AUDIT_CHECK $status [$section] $name $details');
  }

  String _money(double value) => value.toStringAsFixed(2);

  List<SaleItem> _saleItemsFromProducts(List<Product> products, {double quantity = 1, double priceFactor = 1}) => products.map((product) => SaleItem(
        productId: product.id,
        productName: product.name,
        unitPrice: product.price * priceFactor,
        quantity: quantity,
        unitCost: product.usdCost > 0 ? product.usdCost : product.cost,
        unitName: product.unit,
        baseQuantity: quantity,
        conversionToBase: 1.0,
      )).toList();


  static const int _pressureMultiplier = 1000;

  Future<void> _ensureAuditCashDrawerOpen() async {
    if (!AccountingService.isAvailable) return;
    final hasOpenDrawer = await AccountingService.hasOpenCashDrawerForDevice(
      deviceId: store.appIdentity.deviceId,
      branchId: store.appIdentity.branchId,
    );
    if (hasOpenDrawer) return;
    await AccountingService.openCashDrawer(
      drawerNo: 'Stress Lab $_currentBatchId',
      openingBalance: 10000,
      openedBy: 'Stress Lab',
      openedByUserId: store.appIdentity.deviceId,
      storeId: store.appIdentity.storeId,
      branchId: store.appIdentity.branchId,
      deviceId: store.appIdentity.deviceId,
    );
  }

  Future<void> _pressureStep(
    String section,
    String name,
    int count,
    Future<void> Function(int index) action, {
    double startProgress = 0.0,
    double endProgress = 1.0,
  }) async {
    final stats = _StressPerfStats(section, name);
    _resetTraceCapture();
    final swTotal = Stopwatch()..start();
    final progressEvery = max<int>(1, count ~/ 20);
    String? firstError;
    for (var i = 0; i < count; i++) {
      final sw = Stopwatch()..start();
      try {
        await action(i);
        sw.stop();
        stats.add(sw.elapsedMilliseconds);
      } catch (error, stack) {
        sw.stop();
        stats.addFail();
        firstError ??= error.toString();
        _addLog('PRESSURE_ITEM_FAIL [$section] $name index=$i error=$error');
        _addLog(stack.toString().split('\n').take(3).join(' | '));
      }
      if (i % progressEvery == 0) {
        final ratio = count <= 1 ? 1.0 : i / (count - 1);
        _setStatus('$section / $name: ${i + 1}/$count', progress: startProgress + (endProgress - startProgress) * ratio);
        await Future<void>.delayed(Duration.zero);
      }
    }
    swTotal.stop();
    final status = stats.failed == 0 ? (stats.hasSlowdownWarning ? 'WARN' : 'PASS') : 'FAIL';
    final traceSummary = _traceSummaryForSection(section);
    final details = '${stats.summary} totalWall=${swTotal.elapsedMilliseconds}ms${firstError == null ? '' : ' firstError=$firstError'}${stats.hasSlowdownWarning ? ' slowdownWarning=true' : ''} ${traceSummary == 'trace=none' ? '' : traceSummary}';
    _report.add(_StressAuditStep(section: section, name: name, status: status, details: details, elapsedMs: swTotal.elapsedMilliseconds));
    _addLog('PERF_STEP $status [$section] $name $details');
  }

  Future<void> _runPressureAudit({
    required List<Product> baseProducts,
    required Customer? baseCustomer,
    required Supplier? baseSupplier,
  }) async {
    final count = _pressureMultiplier;
    AppStore.setTraceSink(_captureTrace);
    try {
      await _auditStep('الوردية النقدية', 'تجهيز وردية نقدية للاختبار الضاغط', () async {
        await _ensureAuditCashDrawerOpen();
        return AccountingService.isAvailable ? 'تم التأكد من وجود وردية نقدية أو فتح وردية اختبارية.' : 'SQLite Accounting غير متاح؛ تم تجاوز فتح الوردية.';
      }, successDetails: (value) => value);

    final pressureCustomers = <Customer>[];
    await _pressureStep('ضغط العملاء', 'إنشاء $count عميل', count, (i) async {
      final customer = Customer(
        id: '${_currentBatchId}_pc_$i',
        name: '[PRESSURE] Customer $i $_currentBatchId',
        phone: '+96171${i.toString().padLeft(6, '0')}',
        address: 'Pressure customer address $i',
      );
      await store.addOrUpdateCustomer(customer);
      if (i < 20) pressureCustomers.add(customer);
    }, startProgress: 0.79, endProgress: 0.815);

    final pressureSuppliers = <Supplier>[];
    await _pressureStep('ضغط الموردين', 'إنشاء $count مورد', count, (i) async {
      final supplier = Supplier(
        id: '${_currentBatchId}_ps_$i',
        name: '[PRESSURE] Supplier $i $_currentBatchId',
        phone: '+96170${i.toString().padLeft(6, '0')}',
        address: 'Pressure supplier address $i',
        notes: 'Generated by Stress Lab pressure test',
      );
      await store.addOrUpdateSupplier(supplier);
      if (i < 20) pressureSuppliers.add(supplier);
    }, startProgress: 0.815, endProgress: 0.84);

    final pressureProducts = <Product>[];
    await _pressureStep('ضغط المنتجات', 'إنشاء $count منتج', count, (i) async {
      final product = Product(
        id: '${_currentBatchId}_pp_$i',
        name: '[PRESSURE] Product $i $_currentBatchId',
        nameEn: 'Pressure Product $i',
        nameAr: 'منتج ضغط $i',
        code: 'PRS-${DateTime.now().microsecondsSinceEpoch}-$i',
        barcode: 'PRS${DateTime.now().microsecondsSinceEpoch}$i',
        price: (10 + (i % 50)).toDouble(),
        cost: (4 + (i % 20)).toDouble(),
        usdCost: (4 + (i % 20)).toDouble(),
        stock: 1000,
        category: 'Stress Pressure',
        brand: 'Stress Pressure',
        supplier: baseSupplier?.name ?? '',
        unit: 'pcs',
        lowStockThreshold: 5,
        trackStock: true,
        isActive: true,
      );
      await store.addOrUpdateProduct(product);
      if (i < 50) pressureProducts.add(product);
    }, startProgress: 0.84, endProgress: 0.865);

    final salePool = pressureProducts.isNotEmpty ? pressureProducts : baseProducts;
    final customerPool = pressureCustomers.isNotEmpty ? pressureCustomers : (baseCustomer == null ? <Customer>[] : <Customer>[baseCustomer]);
    final supplierPool = pressureSuppliers.isNotEmpty ? pressureSuppliers : (baseSupplier == null ? <Supplier>[] : <Supplier>[baseSupplier]);

    if (salePool.isNotEmpty) {
      await _pressureStep('ضغط المخزون', 'تنفيذ $count تعديل مخزون', count, (i) async {
        final product = salePool[i % salePool.length];
        await store.adjustStock(
          productId: product.id,
          quantityDelta: (i % 2 == 0 ? 1.0 : -0.5),
          reason: 'Stress Lab pressure adjustment',
          adjustmentCategory: 'pressure_adjustment',
          notes: '$_currentBatchId pressure $i',
        );
      }, startProgress: 0.865, endProgress: 0.89);
    }

    if (salePool.isNotEmpty && supplierPool.isNotEmpty) {
      await _pressureStep('ضغط المشتريات', 'إنشاء واستلام $count فاتورة شراء', count, (i) async {
        final product = salePool[i % salePool.length];
        final supplier = supplierPool[i % supplierPool.length];
        await store.createPurchase(
          supplierId: supplier.id,
          supplierName: supplier.name,
          receiveNow: true,
          paymentStatus: 'paid',
          paymentMethod: 'Card',
          note: 'Stress Lab pressure purchase $i',
          items: [PurchaseItem(productId: product.id, productName: product.name, quantity: 1.0 + (i % 3), unitCost: product.cost, purchaseUnitName: product.unit, conversionToBase: 1.0)],
        );
      }, startProgress: 0.89, endProgress: 0.915);
    }

    if (salePool.isNotEmpty && customerPool.isNotEmpty) {
      await _pressureStep('ضغط المبيعات', 'إنشاء $count فاتورة بيع', count, (i) async {
        final product = salePool[i % salePool.length];
        final customer = customerPool[i % customerPool.length];
        await store.createSale(
          customerName: customer.name,
          customerId: customer.id,
          items: _saleItemsFromProducts([product], quantity: 1.0, priceFactor: 1.05),
          discount: i % 10 == 0 ? 0.25 : 0.0,
          paymentMethod: 'Card',
          paymentStatus: 'paid',
        );
      }, startProgress: 0.915, endProgress: 0.94);
    }

      await _pressureStep('ضغط المصاريف', 'إنشاء وترحيل $count مصروف', count, (i) async {
        final expense = Expense(
          id: '${_currentBatchId}_pe_$i',
          title: '[PRESSURE] Expense $i $_currentBatchId',
          category: i % 2 == 0 ? 'Operations' : 'Maintenance',
          amount: 1.0 + (i % 25),
          date: DateTime.now(),
          notes: 'Stress Lab pressure expense $i',
        );
        await store.addOrUpdateExpense(expense);
        await store.postExpense(expense.id);
      }, startProgress: 0.94, endProgress: 0.965);
    } finally {
      AppStore.setTraceSink(null);
    }
  }

  Future<void> _runOneButtonSystemAudit() async {
    if (_running) return;
    setState(() {
      _running = true;
      _progress = 0;
      _status = 'تشغيل اختبار شامل...';
      _report.clear();
      _assertions.clear();
      _log.clear();
      _currentBatchId = 'audit_${DateTime.now().millisecondsSinceEpoch}_${_roleLabel().toLowerCase()}';
    });

    final beforeProducts = store.products.length;
    final beforeCustomers = store.customers.length;
    final beforeSuppliers = store.suppliers.length;
    final beforeSales = store.sales.length;
    final beforePurchases = store.purchases.length;
    final beforeExpenses = store.expenses.length;
    final beforeMovements = store.stockMovements.length;
    final beforeTransactions = store.accountTransactions.length;
    final startedAt = DateTime.now();

    try {
      _addLog('VENTIO_ONE_BUTTON_AUDIT_START batch=$_currentBatchId role=${_roleLabel()}');
      _addLog(_snapshotLine('AUDIT_BEFORE'));
      _logDatabaseMetrics('AUDIT_BEFORE_DB');

      _setStatus('إنشاء الكتالوج...', progress: 0.05);
      final category = await _auditStep('الكتالوج', 'إنشاء تصنيف', () async {
        final item = CatalogItem(id: '${_currentBatchId}_cat', nameEn: 'Stress Audit Category $_currentBatchId', nameAr: 'تصنيف اختبار شامل $_currentBatchId', code: 'AUD-CAT-${DateTime.now().millisecondsSinceEpoch}');
        await store.addOrUpdateCategory(item);
        return item;
      }, successDetails: (item) => 'تم إنشاء التصنيف ${item.code}.');
      final brand = await _auditStep('الكتالوج', 'إنشاء براند', () async {
        final item = CatalogItem(id: '${_currentBatchId}_brand', nameEn: 'Stress Audit Brand $_currentBatchId', nameAr: 'براند اختبار شامل $_currentBatchId', code: 'AUD-BRD-${DateTime.now().millisecondsSinceEpoch}');
        await store.addOrUpdateBrand(item);
        return item;
      }, successDetails: (item) => 'تم إنشاء البراند ${item.code}.');
      final unit = await _auditStep('الكتالوج', 'إنشاء وحدة', () async {
        final item = CatalogItem(id: '${_currentBatchId}_unit', nameEn: 'Piece Audit $_currentBatchId', nameAr: 'قطعة اختبار $_currentBatchId', code: 'AUD-PCS-${DateTime.now().millisecondsSinceEpoch}');
        await store.addOrUpdateUnit(item);
        return item;
      }, successDetails: (item) => 'تم إنشاء الوحدة ${item.code}.');

      _setStatus('إنشاء الأطراف والمنتجات...', progress: 0.14);
      final supplier = await _auditStep('الموردون', 'إنشاء مورد', () async {
        final item = Supplier(id: '${_currentBatchId}_supplier', name: '[AUDIT] Supplier $_currentBatchId', phone: '+96170000000', address: 'Audit supplier address', notes: 'Generated by one-button Stress Lab audit');
        await store.addOrUpdateSupplier(item);
        return item;
      }, successDetails: (item) => 'المورد: ${item.name}.');
      final customer = await _auditStep('العملاء', 'إنشاء عميل', () async {
        final item = Customer(id: '${_currentBatchId}_customer', name: '[AUDIT] Customer $_currentBatchId', phone: '+96171000000', address: 'Audit customer address');
        await store.addOrUpdateCustomer(item);
        return item;
      }, successDetails: (item) => 'العميل: ${item.name}.');

      final products = <Product>[];
      await _auditStep('المنتجات', 'إنشاء منتجات متنوعة', () async {
        for (var i = 1; i <= 4; i++) {
          final product = Product(
            id: '${_currentBatchId}_product_$i',
            name: '[AUDIT] Product $i $_currentBatchId',
            nameEn: 'Audit Product $i',
            nameAr: 'منتج اختبار $i',
            code: 'AUD-${DateTime.now().millisecondsSinceEpoch}-$i',
            barcode: 'AUD${DateTime.now().millisecondsSinceEpoch}$i',
            price: (20 + i * 5).toDouble(),
            cost: (8 + i * 2).toDouble(),
            usdCost: (8 + i * 2).toDouble(),
            stock: (80 + i * 10).toDouble(),
            category: category?.nameEn ?? 'Audit',
            brand: brand?.nameEn ?? 'Audit',
            supplier: supplier?.name ?? '',
            unit: unit?.nameEn ?? 'pcs',
            lowStockThreshold: 5,
            trackStock: true,
            isActive: true,
          );
          await store.addOrUpdateProduct(product);
          products.add(product);
        }
        return products.length;
      }, successDetails: (count) => 'تم إنشاء $count منتجات قابلة للبيع والجرد.');

      if (products.isNotEmpty && supplier != null) {
        await _auditStep('الموردون', 'ربط سعر مورد بمنتج', () async {
          await store.addOrUpdateSupplierProductPrice(SupplierProductPrice(
            id: '${_currentBatchId}_spp',
            productId: products.first.id,
            supplierId: supplier.id,
            cost: max<double>(1, products.first.cost - 1),
            currency: 'USD',
            isPreferred: true,
            supplierSku: 'AUD-SKU-1',
            minOrderQty: 2,
            leadTimeDays: 3,
            notes: 'Generated by one-button Stress Lab audit',
          ));
          return store.supplierProductPricesForProduct(products.first.id).length;
        }, successDetails: (count) => 'أسعار الموردين لهذا المنتج: $count.');
      }

      _setStatus('اختبار المخزون...', progress: 0.28);
      final warehouse = await _auditStep('المخزون', 'إنشاء مستودع', () async => store.createWarehouse(name: '[AUDIT] Warehouse $_currentBatchId', code: 'AUD-WH-${DateTime.now().millisecondsSinceEpoch}', location: 'Stress Lab'), successDetails: (wh) => 'تم إنشاء المستودع ${wh.name}.');
      if (products.isNotEmpty) {
        await _auditStep('المخزون', 'تعديل مخزون يدوي', () async {
          final before = store.products.firstWhere((p) => p.id == products.first.id).stock;
          await store.adjustStock(productId: products.first.id, quantityDelta: 7, reason: 'Stress Lab audit adjustment', adjustmentCategory: 'audit_adjustment', notes: _currentBatchId);
          final after = store.products.firstWhere((p) => p.id == products.first.id).stock;
          return after - before;
        }, successDetails: (delta) => 'فرق المخزون المسجل: ${_money(delta)}.');
        if (warehouse != null) {
          await _auditStep('المخزون', 'تحويل مخزون بين المستودعات', () async {
            await store.transferStock(productId: products.first.id, fromWarehouseId: store.defaultWarehouse.id, toWarehouseId: warehouse.id, quantity: 3.0, notes: 'Stress Lab audit transfer');
            return store.stockForWarehouse(products.first.id, warehouse.id);
          }, successDetails: (qty) => 'رصيد المستودع الجديد للمنتج: ${_money(qty)}.');
        }
      }

      await _auditStep('الوردية النقدية', 'تجهيز وردية نقدية قبل العمليات النقدية', () async {
        await _ensureAuditCashDrawerOpen();
        return AccountingService.isAvailable ? 'تم فتح/تأكيد وردية نقدية قبل الشراء والمصاريف.' : 'SQLite Accounting غير متاح؛ تم تجاوز فتح الوردية.';
      }, successDetails: (value) => value);

      _setStatus('اختبار المشتريات والجرد...', progress: 0.40);
      if (products.length >= 2 && supplier != null) {
        final purchase = await _auditStep('المشتريات', 'إنشاء واستلام فاتورة شراء', () async => store.createPurchase(
              supplierId: supplier.id,
              supplierName: supplier.name,
              receiveNow: true,
              paymentStatus: 'partial',
              paidAmount: 10.0,
              note: 'Stress Lab audit purchase',
              items: [PurchaseItem(productId: products[1].id, productName: products[1].name, quantity: 6.0, unitCost: products[1].cost, purchaseUnitName: products[1].unit, conversionToBase: 1.0)],
            ), successDetails: (po) => 'فاتورة شراء ${po.purchaseNo} بقيمة ${_money(po.subtotal)}.');
        _auditCheck('المشتريات', 'تدقيق أثر الشراء على المخزون', purchase != null && store.stockMovements.any((m) => m.referenceId == purchase.id && m.type == 'purchase_receive'), 'تم تسجيل حركة استلام مخزون للشراء.', 'لم يتم العثور على حركة استلام مخزون مرتبطة بالشراء.');
      }
      if (products.isNotEmpty) {
        await _auditStep('الجرد', 'فتح واعتماد جلسة جرد', () async {
          final session = await store.createInventoryCountSession(notes: 'Stress Lab audit count');
          final line = session.lines.firstWhere((line) => line.productId == products.first.id);
          await store.countInventoryLine(sessionId: session.id, productId: products.first.id, countedQty: line.snapshotStock + 1, note: 'Audit counted +1');
          await store.approveInventoryCount(session.id);
          return session.countNo;
        }, successDetails: (countNo) => 'تم اعتماد جلسة الجرد $countNo.');
      }

      _setStatus('اختبار التصنيع...', progress: 0.52);
      if (products.length >= 3) {
        final bom = await _auditStep('التصنيع', 'إنشاء وصفة تصنيع BOM', () async => store.createBillOfMaterials(
              name: '[AUDIT] BOM $_currentBatchId',
              outputProductId: products[2].id,
              outputQuantity: 1.0,
              components: [BillOfMaterialsLine(productId: products.first.id, productName: products.first.name, quantity: 1.0, unitCost: products.first.cost)],
              notes: 'Stress Lab audit BOM',
            ), successDetails: (value) => 'تم إنشاء BOM ${value.name}.');
        if (bom != null) {
          await _auditStep('التصنيع', 'تنفيذ أمر تصنيع', () async => store.completeManufacturingOrder(bomId: bom.id, quantity: 2.0, notes: 'Stress Lab audit manufacturing'), successDetails: (order) => 'تم تنفيذ أمر تصنيع ${order.orderNo}.');
        }
      }

      _setStatus('اختبار المبيعات والوثائق...', progress: 0.64);
      Sale? normalSale;
      if (products.length >= 2 && customer != null) {
        normalSale = await _auditStep('المبيعات', 'إنشاء فاتورة بيع مدفوعة بالبطاقة', () async => store.createSale(customerName: customer.name, customerId: customer.id, items: _saleItemsFromProducts(products.take(2).toList(), quantity: 2.0), discount: 1.0, paymentMethod: 'Card', paymentStatus: 'paid'), successDetails: (sale) => 'فاتورة ${sale.invoiceNo} بقيمة ${_money(sale.total)} وربح ${_money(sale.grossProfit)}.');
        if (normalSale != null) {
          await _auditStep('سندات التسليم', 'إنشاء وتسليم سند تسليم', () async {
            final note = await store.createDeliveryNoteFromSale(normalSale!.id, note: 'Stress Lab audit delivery');
            await store.markDeliveryNoteDelivered(note.id);
            return note.deliveryNo;
          }, successDetails: (deliveryNo) => 'تم إنشاء وتسليم السند $deliveryNo.');
        }
      }
      if (products.isNotEmpty && customer != null) {
        await _auditStep('عروض الأسعار', 'إنشاء عرض سعر وتحويله إلى بيع', () async {
          final quotation = await store.createSaleQuotation(customerName: customer.name, customerId: customer.id, items: _saleItemsFromProducts([products.last], quantity: 1.0), discount: 0.5, note: 'Stress Lab audit quotation');
          final sale = await store.convertSaleQuotationToSale(quotation.id, paymentMethod: 'Card', paymentStatus: 'paid');
          return '${quotation.quotationNo} -> ${sale.invoiceNo}';
        }, successDetails: (value) => 'تم التحويل: $value.');
      }
      if (products.length >= 2 && customer != null) {
        await _auditStep('المبيعات', 'إنشاء وإرجاع فاتورة بيع', () async {
          final sale = await store.createSale(customerName: customer.name, customerId: customer.id, items: _saleItemsFromProducts([products[1]], quantity: 1.0), paymentMethod: 'Card', paymentStatus: 'paid');
          await store.returnSale(sale.id, restoreStock: true);
          return sale.invoiceNo;
        }, successDetails: (invoice) => 'تم إنشاء ثم إرجاع الفاتورة $invoice.');
        await _auditStep('المبيعات', 'إنشاء وإلغاء فاتورة بيع', () async {
          final sale = await store.createSale(customerName: customer.name, customerId: customer.id, items: _saleItemsFromProducts([products[1]], quantity: 1.0), paymentMethod: 'Card', paymentStatus: 'paid');
          await store.cancelSale(sale.id, restoreStock: true);
          return sale.invoiceNo;
        }, successDetails: (invoice) => 'تم إنشاء ثم إلغاء الفاتورة $invoice.');
      }

      _setStatus('اختبار المصاريف والمحاسبة...', progress: 0.78);
      final expense = await _auditStep('المصاريف', 'إنشاء وترحيل مصروف', () async {
        final item = Expense(id: '${_currentBatchId}_expense', title: '[AUDIT] Expense $_currentBatchId', category: 'Operations', amount: 12.75, date: DateTime.now(), notes: 'Stress Lab audit expense');
        await store.addOrUpdateExpense(item);
        await store.postExpense(item.id);
        return item.id;
      }, successDetails: (id) => 'تم إنشاء وترحيل المصروف $id.');
      if (expense != null) {
        await _auditStep('المصاريف', 'إلغاء مصروف مرحّل', () async {
          await store.cancelExpense(expense, reason: 'Stress Lab audit cancel');
          return expense;
        }, successDetails: (id) => 'تم إلغاء المصروف $id.');
      }

      _setStatus('تشغيل اختبار الضغط 1000x...', progress: 0.79);
      await _runPressureAudit(baseProducts: products, baseCustomer: customer, baseSupplier: supplier);

      _setStatus('اختبار النسخ الاحتياطي والمزامنة...', progress: 0.97);
      await _auditStep('النسخ الاحتياطي', 'توليد Backup JSON', () async {
        final raw = store.exportBackupJson();
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        return '${raw.length} bytes, keys=${decoded.keys.length}';
      }, successDetails: (value) => 'نجح توليد النسخة الاحتياطية: $value.');
      await _auditStep('المزامنة', 'فحص حالة Queue بدون إجبار شبكة', () async {
        final rejectedQueue = store.syncQueue.where((item) => item.status.toLowerCase() == 'rejected').length;
        final failedQueue = store.syncQueue.where((item) => item.status.toLowerCase() == 'failed').length;
        return 'pendingQueue=${store.pendingSyncQueue.length}, pendingChanges=${store.pendingSyncChanges.length}, failed=$failedQueue, rejected=$rejectedQueue, transport=${_effectiveSyncTransport()}';
      }, successDetails: (value) => value);

      _setStatus('تدقيق النتائج...', progress: 0.99);
      final newSales = store.sales.length - beforeSales;
      final newPurchases = store.purchases.length - beforePurchases;
      final newExpenses = store.expenses.length - beforeExpenses;
      final newMovements = store.stockMovements.length - beforeMovements;
      final newTransactions = store.accountTransactions.length - beforeTransactions;
      _auditCheck('ملخص البيانات', 'نمو البيانات بعد الاختبار', store.products.length > beforeProducts && store.customers.length > beforeCustomers && store.suppliers.length > beforeSuppliers, 'تم إنشاء بيانات أساسية جديدة: منتجات ${store.products.length - beforeProducts}, عملاء ${store.customers.length - beforeCustomers}, موردون ${store.suppliers.length - beforeSuppliers}.', 'لم تنمُ البيانات الأساسية كما هو متوقع.');
      _auditCheck('ملخص البيانات', 'حركات تشغيلية جديدة', newSales > 0 && newPurchases > 0 && newExpenses > 0 && newMovements > 0, 'تم إنشاء عمليات: مبيعات $newSales، مشتريات $newPurchases، مصاريف $newExpenses، حركات مخزون $newMovements.', 'هناك نقص في العمليات المنشأة: مبيعات $newSales، مشتريات $newPurchases، مصاريف $newExpenses، حركات مخزون $newMovements.');
      final hasInvalidStock = products.any((product) {
        final current = store.products.where((item) => item.id == product.id).toList();
        return current.isNotEmpty && !current.first.stock.isFinite;
      });
      _auditCheck('المخزون', 'سلامة أرقام المخزون', !hasInvalidStock, 'كل أرصدة منتجات الاختبار أرقام صالحة.', 'تم العثور على رصيد مخزون غير صالح في أحد منتجات الاختبار.');
      final failedQueue = store.syncQueue.where((item) => item.status.toLowerCase() == 'failed' || item.status.toLowerCase() == 'rejected').length;
      _auditCheck('المزامنة', 'عدم وجود Queue فاشلة/مرفوضة', failedQueue == 0, 'لا توجد عناصر sync failed/rejected.', 'يوجد $failedQueue عناصر sync failed/rejected.', warning: true);
      _auditCheck('المحاسبة', 'ترحيل محاسبي محلي', newTransactions > 0 || AccountingService.isAvailable, newTransactions > 0 ? 'تم إنشاء $newTransactions حركات حساب محلية.' : 'SQLite Accounting متاح؛ بعض القيود قد تكون في دفتر اليومية وليس accountTransactions.', 'لم يتم رصد حركات حساب جديدة ودفتر SQLite غير متاح.', warning: true);
      final activeSalesTotal = store.sales.where((sale) => sale.customerName.contains(_currentBatchId)).where((sale) => !sale.isCancelled && !sale.isDeleted).fold<double>(0, (sum, sale) => sum + sale.total);
      final expectedMinimumRevenue = normalSale == null ? 0.0 : max<double>(0.0, normalSale.total);
      _auditCheck('المحاسبة', 'منطق نتيجة المبيعات', activeSalesTotal + 0.001 >= expectedMinimumRevenue, 'إجمالي المبيعات النشطة لاختبار الدفعة ${_money(activeSalesTotal)}، وهو متوافق مبدئياً مع الفواتير غير الملغاة.', 'إجمالي المبيعات النشطة ${_money(activeSalesTotal)} أقل من المتوقع ${_money(expectedMinimumRevenue)}.');
      await _runDeepAccountingChecks();
      _runInventoryConsistencyChecks();
      _runPerformanceHealthChecks();
      await _runMaintenanceHealthCheckIntegration();
      await _runReleaseAssertions();
      _runInvestigationMode();
      await _auditStep('سلامة البيانات', 'Integrity Check داخلي', () async {
        await _runIntegrityCheckBodyForOneButton();
        return 'اكتمل فحص العلاقات الأساسية.';
      }, successDetails: (value) => value);

      _logDatabaseMetrics('AUDIT_AFTER_DB');
      _addLog(_snapshotLine('AUDIT_AFTER'));
      _addHealthSummary('ONE_BUTTON_AUDIT_SUMMARY');
      _addFinalAuditReport(startedAt);
      _setStatus('انتهى الاختبار الشامل', progress: 1);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _runIntegrityCheckBodyForOneButton() async {
    final productIds = store.allProductsForDiagnostics.map((item) => item.id).toSet();
    final saleIds = store.sales.map((item) => item.id).toSet();
    final purchaseIds = store.purchases.map((item) => item.id).toSet();
    final saleMissing = <String>[];
    for (final sale in store.sales) {
      for (final item in sale.items) {
        if (!productIds.contains(item.productId)) saleMissing.add('${sale.id}:${item.productId}');
      }
    }
    final purchaseMissing = <String>[];
    for (final purchase in store.purchases) {
      for (final item in purchase.items) {
        if (!productIds.contains(item.productId)) purchaseMissing.add('${purchase.id}:${item.productId}');
      }
    }
    final stockMissingReferences = store.stockMovements.where((movement) {
      final reference = movement.referenceId;
      if (reference.isEmpty) return false;
      final type = movement.type.toLowerCase();
      if (type.contains('sale')) return !saleIds.contains(reference);
      if (type.contains('purchase')) return !purchaseIds.contains(reference);
      return false;
    }).take(5).toList();
    if (saleMissing.isNotEmpty || purchaseMissing.isNotEmpty || stockMissingReferences.isNotEmpty) {
      throw StateError('Integrity issues: saleMissing=${saleMissing.length}, purchaseMissing=${purchaseMissing.length}, stockMissingRefs=${stockMissingReferences.length}');
    }
  }


  Future<void> _runMaintenanceHealthCheckIntegration() async {
    final summary = await _auditStep('صيانة التطبيق', 'تشغيل Maintenance Health Check', () async {
      final summary = await MaintenanceService(store).runHealthCheck(deep: true);
      return summary;
    }, successDetails: (summary) {
      final actionable = summary.issues
          .where((issue) => issue.severity != MaintenanceSeverity.ok)
          .length;
      return 'score=${summary.healthScore}/100 status=${summary.healthStatusLabel} issues=${summary.issues.length} actionable=$actionable db=${summary.databaseEngine} size=${summary.databaseSizeBytes} bytes.';
    });
    if (summary == null) {
      _auditCheck(
        'صيانة التطبيق',
        'دمج نتائج Maintenance',
        false,
        'تم دمج نتائج Maintenance بنجاح.',
        'تعذر تشغيل Maintenance Health Check ودمجه مع تقرير Stress Lab.',
      );
      return;
    }
    final okCount = summary.issues
        .where((issue) => issue.severity == MaintenanceSeverity.ok)
        .length;
    final infoCount = summary.issues
        .where((issue) => issue.severity == MaintenanceSeverity.info)
        .length;
    final warningCount = summary.issues
        .where((issue) => issue.severity == MaintenanceSeverity.warning)
        .length;
    final criticalCount = summary.issues
        .where((issue) => issue.severity == MaintenanceSeverity.critical)
        .length;
    _auditCheck(
      'صيانة التطبيق',
      'ملخص فحص الصيانة',
      criticalCount == 0 && warningCount == 0,
      'Maintenance clean: ok=$okCount info=$infoCount warning=0 critical=0 score=${summary.healthScore}/100.',
      'Maintenance findings: ok=$okCount info=$infoCount warning=$warningCount critical=$criticalCount score=${summary.healthScore}/100.',
      warning: true,
    );

    for (final issue in summary.issues.where((issue) => issue.severity != MaintenanceSeverity.ok)) {
      final status = issue.severity == MaintenanceSeverity.critical
          ? 'FAIL'
          : 'WARN';
      final details = _maintenanceIssueDetails(issue);
      _report.add(_StressAuditStep(
        section: 'صيانة التطبيق',
        name: issue.title,
        status: status,
        details: details,
        elapsedMs: 0,
      ));
      _addLog('MAINTENANCE_CHECK $status [${issue.id}] ${issue.title}: $details');
    }

    _addOverpaidSalesEvidence();
  }

  String _maintenanceIssueDetails(MaintenanceIssue issue) {
    if (issue.id == 'overpaid_sales') {
      final overpaid = store.sales
          .where((sale) => !sale.isDeleted && sale.paidAmount > sale.invoiceTotal + 0.01)
          .toList(growable: false);
      final totalExtra = overpaid.fold<double>(
        0,
        (sum, sale) => sum + max<double>(0, sale.paidAmount - sale.invoiceTotal),
      );
      final sample = overpaid
          .take(8)
          .map((sale) => '${sale.invoiceNo}: total=${_money(sale.invoiceTotal)} paid=${_money(sale.paidAmount)} extra=${_money(max<double>(0, sale.paidAmount - sale.invoiceTotal))}')
          .join(' | ');
      return '${issue.message} totalExtra=${_money(totalExtra)}${sample.isEmpty ? '' : ' sample=$sample'}';
    }
    if (issue.details.isEmpty) return issue.message;
    return '${issue.message} details=${jsonEncode(issue.details)}';
  }

  void _addOverpaidSalesEvidence() {
    final overpaid = store.sales
        .where((sale) => !sale.isDeleted && !sale.isCancelled && sale.paidAmount > sale.invoiceTotal + 0.01)
        .toList(growable: false);
    if (overpaid.isEmpty) {
      _auditCheck(
        'أدلة الصيانة',
        'فواتير مدفوعة بزيادة',
        true,
        'لا توجد فواتير مدفوعة بأكثر من إجماليها.',
        'يوجد فواتير مدفوعة بزيادة.',
      );
      return;
    }
    final totalExtra = overpaid.fold<double>(
      0,
      (sum, sale) => sum + max<double>(0, sale.paidAmount - sale.invoiceTotal),
    );
    final sample = overpaid
        .take(10)
        .map((sale) => '${sale.invoiceNo}: total=${_money(sale.invoiceTotal)} paid=${_money(sale.paidAmount)} extra=${_money(max<double>(0, sale.paidAmount - sale.invoiceTotal))}')
        .join(' | ');
    _auditCheck(
      'أدلة الصيانة',
      'فواتير مدفوعة بزيادة',
      false,
      'لا توجد فواتير مدفوعة بأكثر من إجماليها.',
      'count=${overpaid.length} totalExtra=${_money(totalExtra)} sample=$sample',
      warning: true,
    );
  }


  Future<void> _runDeepAccountingChecks() async {
    final batchSales = store.sales.where((sale) => sale.customerName.contains(_currentBatchId)).toList(growable: false);
    final batchPurchases = store.purchases.where((purchase) => purchase.supplierName.contains(_currentBatchId) || purchase.note.contains(_currentBatchId)).toList(growable: false);
    final batchExpenses = store.expenses.where((expense) => expense.id.contains(_currentBatchId) || expense.title.contains(_currentBatchId) || expense.notes.contains(_currentBatchId)).toList(growable: false);
    final transactions = store.accountTransactions.where((tx) => !tx.isDeleted).toList(growable: false);
    final accountingAvailable = AccountingService.isAvailable;
    final invalidTransactions = transactions.where((tx) => !tx.debit.isFinite || !tx.credit.isFinite || tx.debit < 0 || tx.credit < 0 || (tx.debit == 0 && tx.credit == 0)).length;
    final batchRefs = <String>{
      ...batchSales.map((sale) => sale.id),
      ...batchSales.map((sale) => sale.invoiceNo),
      ...batchPurchases.map((purchase) => purchase.id),
      ...batchPurchases.map((purchase) => purchase.purchaseNo),
      ...batchExpenses.map((expense) => expense.id),
    };
    final batchTransactions = transactions.where((tx) => batchRefs.contains(tx.referenceId) || batchRefs.contains(tx.referenceNo) || tx.note.contains(_currentBatchId)).toList(growable: false);
    final batchDebit = batchTransactions.fold<double>(0, (sum, tx) => sum + tx.debit);
    final batchCredit = batchTransactions.fold<double>(0, (sum, tx) => sum + tx.credit);
    final activeBatchSales = batchSales.where((sale) => !sale.isCancelled && !sale.isDeleted).toList(growable: false);
    final activeBatchPurchases = batchPurchases.where((purchase) => !purchase.isCancelled && !purchase.isDeleted).toList(growable: false);
    final activeBatchExpenses = batchExpenses.where((expense) => expense.cancelledAt == null && expense.deletedAt == null).toList(growable: false);
    final trialBalanceRows = accountingAvailable ? await AccountingService.trialBalanceReport() : const <dynamic>[];
    final trialDebit = trialBalanceRows.fold<double>(0, (sum, row) => sum + row.debit);
    final trialCredit = trialBalanceRows.fold<double>(0, (sum, row) => sum + row.credit);
    final trialDiff = (trialDebit - trialCredit).abs();
    final activeSalesJournalCount = accountingAvailable ? await AccountingService.countPostedJournalEntriesForReferences(
      referenceType: 'sale',
      referenceIds: activeBatchSales.map((sale) => sale.id),
    ) : 0;
    final activePurchasesJournalCount = accountingAvailable ? await AccountingService.countPostedJournalEntriesForReferences(
      referenceType: 'purchase',
      referenceIds: activeBatchPurchases.map((purchase) => purchase.id),
    ) : 0;
    final activeExpensesJournalCount = accountingAvailable ? await AccountingService.countPostedJournalEntriesForReferences(
      referenceType: 'expense',
      referenceIds: activeBatchExpenses.map((expense) => expense.id),
    ) : 0;

    _auditCheck('المحاسبة المتقدمة', 'صلاحية مبالغ القيود', invalidTransactions == 0, 'كل القيود المحاسبية تحمل مبالغ صالحة وغير سالبة.', 'يوجد $invalidTransactions قيد محاسبي بمبلغ غير صالح.');
    _auditCheck('المحاسبة المتقدمة', 'تغطية فواتير البيع بقيود يومية', accountingAvailable ? activeSalesJournalCount == activeBatchSales.length : false, accountingAvailable ? 'كل فواتير البيع النشطة في دفعة الاختبار لها قيد يومية منشور.' : 'SQLite accounting غير متاح؛ لا يمكن التحقق من قيود اليومية لفواتير البيع.', accountingAvailable ? 'القيود اليومية لفواتير البيع النشطة: $activeSalesJournalCount من ${activeBatchSales.length}.' : 'SQLite accounting unavailable; journal coverage not verified.', warning: !accountingAvailable);
    _auditCheck('المحاسبة المتقدمة', 'تغطية فواتير الشراء بقيود يومية', accountingAvailable ? activePurchasesJournalCount == activeBatchPurchases.length : false, accountingAvailable ? 'كل فواتير الشراء النشطة في دفعة الاختبار لها قيد يومية منشور.' : 'SQLite accounting غير متاح؛ لا يمكن التحقق من قيود اليومية لفواتير الشراء.', accountingAvailable ? 'القيود اليومية لفواتير الشراء النشطة: $activePurchasesJournalCount من ${activeBatchPurchases.length}.' : 'SQLite accounting unavailable; journal coverage not verified.', warning: !accountingAvailable);
    _auditCheck('المحاسبة المتقدمة', 'تغطية المصاريف بقيود يومية', accountingAvailable ? activeExpensesJournalCount == activeBatchExpenses.length : false, accountingAvailable ? 'كل المصاريف النشطة في دفعة الاختبار لها قيد يومية منشور.' : 'SQLite accounting غير متاح؛ لا يمكن التحقق من قيود اليومية للمصاريف.', accountingAvailable ? 'القيود اليومية للمصاريف النشطة: $activeExpensesJournalCount من ${activeBatchExpenses.length}.' : 'SQLite accounting unavailable; journal coverage not verified.', warning: !accountingAvailable);
    _auditCheck('المحاسبة المتقدمة', 'توازن دفتر اليومية', accountingAvailable ? trialDiff <= 0.01 : false, accountingAvailable ? 'دفتر اليومية متوازن: debit=${_money(trialDebit)} credit=${_money(trialCredit)}.' : 'SQLite accounting غير متاح؛ لا يمكن التحقق من توازن دفتر اليومية.', accountingAvailable ? 'دفتر اليومية غير متوازن: debit=${_money(trialDebit)} credit=${_money(trialCredit)} diff=${_money(trialDiff)}.' : 'SQLite accounting unavailable; balance not verified.', warning: !accountingAvailable);
    _addLog('SUBLEDGER_SNAPSHOT batchDebit=${_money(batchDebit)} batchCredit=${_money(batchCredit)} batchDiff=${_money((batchDebit - batchCredit).abs())} note=Open customer/supplier balances may remain after partial settlement and are reported separately from trial balance.');
  }


  List<Expense> _activeBatchExpenses() => store.expenses
      .where((expense) => expense.id.contains(_currentBatchId) || expense.title.contains(_currentBatchId) || expense.notes.contains(_currentBatchId))
      .where((expense) => expense.isPosted && !expense.isDeleted && !expense.isCancelled)
      .toList(growable: false);

  List<Sale> _batchSales() => store.sales
      .where((sale) => sale.customerName.contains(_currentBatchId) || sale.invoiceNo.contains(_currentBatchId) || sale.id.contains(_currentBatchId))
      .toList(growable: false);

  List<Purchase> _batchPurchases() => store.purchases
      .where((purchase) => purchase.supplierName.contains(_currentBatchId) || purchase.note.contains(_currentBatchId) || purchase.id.contains(_currentBatchId))
      .toList(growable: false);

  bool _transactionMatchesAny(AccountTransaction tx, Iterable<String> refs) {
    for (final ref in refs) {
      if (ref.trim().isEmpty) continue;
      if (tx.referenceId == ref || tx.referenceNo == ref || tx.note.contains(ref)) return true;
    }
    return false;
  }


  void _recordAssertion(_StressAssertionResult result) {
    _assertions.add(result);
    final section = result.blocking ? 'Release Assertions' : 'Release Assertions - Advisory';
    final status = result.status;
    _report.add(_StressAuditStep(
      section: section,
      name: result.id,
      status: status,
      details: result.details,
      elapsedMs: 0,
    ));
    _addLog('RELEASE_ASSERTION $status ${result.id} area=${result.area} expected="${result.expected}" actual="${result.actual}" blocking=${result.blocking}');
  }

  bool _hasAccountingReference(Iterable<AccountTransaction> transactions, Iterable<String> refs) {
    return transactions.any((tx) => _transactionMatchesAny(tx, refs));
  }

  bool _hasStockReference(Iterable<String> refs) {
    return store.stockMovements.any((movement) {
      for (final ref in refs) {
        if (ref.trim().isEmpty) continue;
        if (movement.referenceId == ref || movement.referenceNo == ref || movement.notes.contains(ref) || movement.reason.contains(ref)) {
          return true;
        }
      }
      return false;
    });
  }

  Future<void> _runReleaseAssertions() async {
    _addLog('========== VENTIO RELEASE ASSERTIONS ==========' );
    final batchProducts = store.allProductsForDiagnostics.where((product) => product.name.contains(_currentBatchId) || product.code.contains(_currentBatchId)).toList(growable: false);
    final batchCustomers = store.customers.where((customer) => customer.name.contains(_currentBatchId)).toList(growable: false);
    final batchSuppliers = store.suppliers.where((supplier) => supplier.name.contains(_currentBatchId)).toList(growable: false);
    final batchSales = _batchSales();
    final batchPurchases = _batchPurchases();
    final activeSales = batchSales.where((sale) => !sale.isCancelled && !sale.isDeleted).toList(growable: false);
    final activePurchases = batchPurchases.where((purchase) => !purchase.isCancelled && !purchase.isDeleted).toList(growable: false);
    final activeExpenses = _activeBatchExpenses();
    final accountingAvailable = AccountingService.isAvailable;
    final trialBalanceRows = accountingAvailable ? await AccountingService.trialBalanceReport() : const <dynamic>[];
    final trialDebit = trialBalanceRows.fold<double>(0, (sum, row) => sum + row.debit);
    final trialCredit = trialBalanceRows.fold<double>(0, (sum, row) => sum + row.credit);
    final diff = (trialDebit - trialCredit).abs();
    final activeSalesJournalCount = accountingAvailable ? await AccountingService.countPostedJournalEntriesForReferences(
      referenceType: 'sale',
      referenceIds: activeSales.map((sale) => sale.id),
    ) : 0;
    final activePurchasesJournalCount = accountingAvailable ? await AccountingService.countPostedJournalEntriesForReferences(
      referenceType: 'purchase',
      referenceIds: activePurchases.map((purchase) => purchase.id),
    ) : 0;
    final activeExpensesJournalCount = accountingAvailable ? await AccountingService.countPostedJournalEntriesForReferences(
      referenceType: 'expense',
      referenceIds: activeExpenses.map((expense) => expense.id),
    ) : 0;
    final activeSalesMissingStock = activeSales.where((sale) => !_hasStockReference(<String>{sale.id, sale.invoiceNo})).length;
    final activePurchasesMissingStock = activePurchases.where((purchase) => !_hasStockReference(<String>{purchase.id, purchase.purchaseNo})).length;
    final invalidStock = batchProducts.where((product) => !product.stock.isFinite).length;
    final negativeStock = batchProducts.where((product) => product.stock < -0.001).length;
    final overpaidCancelled = batchSales.where((sale) => !sale.isDeleted && sale.paidAmount > sale.invoiceTotal + 0.01 && (sale.isCancelled || sale.status.toLowerCase().contains('return'))).length;
    final perfWarns = _report.where((row) => row.section.startsWith('ضغط ') && row.isWarn).length;
    final perfFails = _report.where((row) => row.section.startsWith('ضغط ') && row.isFail).length;
    final failedOrRejectedQueue = store.syncQueue.where((item) {
      final status = item.status.toLowerCase();
      return status == 'failed' || status == 'rejected';
    }).length;

    void expect(String id, String area, bool condition, String expected, String actual, {bool blocking = true}) {
      _recordAssertion(_StressAssertionResult(
        id: id,
        area: area,
        expected: expected,
        actual: actual,
        passed: condition,
        blocking: blocking,
      ));
    }

    expect('CATALOG-001', 'Catalog', store.categories.any((item) => item.displayName('en').startsWith('AUD-CAT-') || item.code.startsWith('AUD-CAT-')) && store.brands.any((item) => item.displayName('en').startsWith('AUD-BRD-') || item.code.startsWith('AUD-BRD-')) && store.units.any((item) => item.displayName('en').startsWith('AUD-PCS-') || item.code.startsWith('AUD-PCS-')), 'Stress category, brand, and unit exist.', 'categories=${store.categories.length} brands=${store.brands.length} units=${store.units.length}');
    expect('MASTER-DATA-001', 'Master Data', batchProducts.length >= 1004 && batchCustomers.length >= 1001 && batchSuppliers.length >= 1001, 'At least 1004 products, 1001 customers, and 1001 suppliers for this batch.', 'products=${batchProducts.length} customers=${batchCustomers.length} suppliers=${batchSuppliers.length}');
    expect('SALES-ACCOUNTING-001', 'Accounting', accountingAvailable ? activeSalesJournalCount == activeSales.length : false, 'Every active batch sale has a posted journal entry.', accountingAvailable ? 'activeSales=${activeSales.length} journalEntries=$activeSalesJournalCount' : 'SQLite accounting unavailable; journal coverage not verified.', blocking: accountingAvailable);
    expect('PURCHASE-ACCOUNTING-001', 'Accounting', accountingAvailable ? activePurchasesJournalCount == activePurchases.length : false, 'Every active batch purchase has a posted journal entry.', accountingAvailable ? 'activePurchases=${activePurchases.length} journalEntries=$activePurchasesJournalCount' : 'SQLite accounting unavailable; journal coverage not verified.', blocking: accountingAvailable);
    expect('EXPENSE-ACCOUNTING-001', 'Accounting', accountingAvailable ? activeExpensesJournalCount == activeExpenses.length : false, 'Every active posted expense has a posted journal entry.', accountingAvailable ? 'activeExpenses=${activeExpenses.length} journalEntries=$activeExpensesJournalCount' : 'SQLite accounting unavailable; journal coverage not verified.', blocking: accountingAvailable);
    expect('LEDGER-BALANCE-001', 'Accounting', accountingAvailable ? diff <= 0.01 : false, 'Posted journal entries are balanced in trial balance.', accountingAvailable ? 'debit=${_money(trialDebit)} credit=${_money(trialCredit)} diff=${_money(diff)} postedJournalRows=${trialBalanceRows.length}' : 'SQLite accounting unavailable; balance not verified.', blocking: accountingAvailable);
    expect('SALE-STOCK-001', 'Inventory', activeSalesMissingStock == 0, 'Every active sale has a stock movement reference.', 'activeSales=${activeSales.length} missingStockMovement=$activeSalesMissingStock');
    expect('PURCHASE-STOCK-001', 'Inventory', activePurchasesMissingStock == 0, 'Every active purchase has a receipt stock movement reference.', 'activePurchases=${activePurchases.length} missingStockMovement=$activePurchasesMissingStock');
    expect('STOCK-VALIDITY-001', 'Inventory', invalidStock == 0 && negativeStock == 0, 'Stress products have valid non-negative stock.', 'invalidStock=$invalidStock negativeStock=$negativeStock products=${batchProducts.length}');
    expect('CANCEL-RETURN-PAYMENT-001', 'Sales Cancellation', overpaidCancelled == 0, 'Cancelled/returned sales must not remain overpaid unless customer credit is explicitly represented.', 'cancelledOrReturnedOverpaid=$overpaidCancelled', blocking: false);
    expect('PERFORMANCE-001', 'Performance', perfFails == 0 && perfWarns == 0, 'No pressure test failed or crossed slowdown thresholds.', 'perfWarnings=$perfWarns perfFailures=$perfFails', blocking: false);
    expect('SYNC-001', 'Sync', failedOrRejectedQueue == 0, 'No failed or rejected sync queue items after stress run.', 'failedOrRejectedQueue=$failedOrRejectedQueue pendingQueue=${store.pendingSyncQueue.length} transport=${_effectiveSyncTransport()}');
    expect('BACKUP-001', 'Backup', store.exportBackupJson().isNotEmpty, 'Backup JSON can be generated after stress run.', 'backupBytes=${store.exportBackupJson().length}');

    final passed = _assertions.where((item) => item.passed).length;
    final blockingFailed = _assertions.where((item) => !item.passed && item.blocking).length;
    final advisoryFailed = _assertions.where((item) => !item.passed && !item.blocking).length;
    final certification = blockingFailed == 0 && advisoryFailed == 0
        ? 'READY FOR PRODUCTION'
        : blockingFailed == 0
            ? 'READY WITH WARNINGS'
            : 'NOT READY FOR PRODUCTION';
    _addLog('RELEASE_CERTIFICATION assertionsPassed=$passed/${_assertions.length} blockingFailed=$blockingFailed advisoryWarnings=$advisoryFailed certification=$certification');
    _auditCheck(
      'Release Certification',
      'Production Gate',
      blockingFailed == 0,
      'Assertions Passed: $passed/${_assertions.length}; advisoryWarnings=$advisoryFailed; Certification=$certification.',
      'Assertions Passed: $passed/${_assertions.length}; blockingFailed=$blockingFailed; advisoryWarnings=$advisoryFailed; Certification=$certification.',
    );
    final blockingIds = _assertions.where((item) => !item.passed && item.blocking).map((item) => item.id).join(', ');
    final advisoryIds = _assertions.where((item) => !item.passed && !item.blocking).map((item) => item.id).join(', ');
    if (blockingIds.isNotEmpty || advisoryIds.isNotEmpty) {
      _addLog('BLOCKING_ASSERTIONS ${blockingIds.isEmpty ? 'none' : blockingIds} | ADVISORY_ASSERTIONS ${advisoryIds.isEmpty ? 'none' : advisoryIds}');
    }
    _addLog('==============================================' );
  }

  void _runInvestigationMode() {
    _addLog('========== VENTIO INVESTIGATION MODE ==========' );
    final failRows = _report.where((item) => item.isFail).toList(growable: false);
    final warnRows = _report.where((item) => item.isWarn).toList(growable: false);
    _addLog('Investigation triggers: fails=${failRows.length} warnings=${warnRows.length} batch=$_currentBatchId');

    final expenseEvidence = _investigateExpenseJournals();
    final balanceEvidence = _investigateTrialBalance();
    final overpaidEvidence = _investigateOverpaidSales();
    final performanceEvidence = _investigatePerformanceSlowdown();
    final syncEvidence = _investigateSyncMode();
    final suggestionDetails = _buildAutoSuggestions(expenseEvidence, balanceEvidence, overpaidEvidence, performanceEvidence, syncEvidence);

    _auditCheck(
      'تحليل السبب الجذري',
      'تشخيص المصاريف المحاسبي',
      !expenseEvidence.contains('missing='),
      expenseEvidence,
      expenseEvidence,
      warning: true,
    );
    _auditCheck(
      'تحليل السبب الجذري',
      'تشخيص فرق المدين والدائن',
      !balanceEvidence.contains('diff='),
      balanceEvidence,
      balanceEvidence,
      warning: true,
    );
    _auditCheck(
      'تحليل السبب الجذري',
      'تشخيص الفواتير المدفوعة بزيادة',
      !overpaidEvidence.contains('count='),
      overpaidEvidence,
      overpaidEvidence,
      warning: true,
    );
    _auditCheck(
      'تحليل السبب الجذري',
      'تشخيص تباطؤ الأداء',
      !performanceEvidence.contains('slowSections='),
      performanceEvidence,
      performanceEvidence,
      warning: true,
    );
    _auditCheck(
      'تحليل السبب الجذري',
      'تشخيص حالة المزامنة',
      !syncEvidence.contains('needsSync=true'),
      syncEvidence,
      syncEvidence,
      warning: true,
    );
    _auditCheck(
      'اقتراحات الإصلاح',
      'خطوات مقترحة حسب الأدلة',
      true,
      suggestionDetails,
      suggestionDetails,
    );
    _addLog('ROOT_CAUSE_SUGGESTIONS $suggestionDetails');
    _addLog('===============================================' );
  }

  String _investigateExpenseJournals() {
    final expenses = _activeBatchExpenses();
    final transactions = store.accountTransactions.where((tx) => !tx.isDeleted).toList(growable: false);
    final missing = <Expense>[];
    final linked = <Expense>[];
    for (final expense in expenses) {
      final refs = <String>{expense.id, expense.title};
      final hasTx = transactions.any((tx) => _transactionMatchesAny(tx, refs));
      if (hasTx) {
        linked.add(expense);
      } else {
        missing.add(expense);
      }
    }
    final sample = missing.take(8).map((expense) => '${expense.id}:${expense.title}:amount=${_money(expense.amount)}:status=${expense.status}').join(' | ');
    final details = missing.isEmpty
        ? 'Expense journals OK: active=${expenses.length} linked=${linked.length}. كل مصروف نشط في الدفعة له أثر ضمن accountTransactions.'
        : 'missing=${missing.length}/${expenses.length} linked=${linked.length} sample=$sample possibleCause=Expense journal may be stored only in SQLite journal_entries, or postExpense did not create a legacy accountTransaction reference.';
    _addLog('INVESTIGATION_EXPENSE_JOURNALS $details');
    return details;
  }

  String _investigateTrialBalance() {
    final sales = _batchSales();
    final purchases = _batchPurchases();
    final expenses = _activeBatchExpenses();
    final refs = <String>{
      ...sales.map((sale) => sale.id),
      ...sales.map((sale) => sale.invoiceNo),
      ...purchases.map((purchase) => purchase.id),
      ...purchases.map((purchase) => purchase.purchaseNo),
      ...expenses.map((expense) => expense.id),
      ...expenses.map((expense) => expense.title),
    };
    final transactions = store.accountTransactions.where((tx) => !tx.isDeleted && _transactionMatchesAny(tx, refs)).toList(growable: false);
    final debit = transactions.fold<double>(0, (sum, tx) => sum + tx.debit);
    final credit = transactions.fold<double>(0, (sum, tx) => sum + tx.credit);
    final diff = (debit - credit).abs();
    final byType = <String, double>{};
    for (final tx in transactions) {
      final key = tx.accountType.trim().isEmpty ? 'unknown' : tx.accountType.trim();
      byType[key] = (byType[key] ?? 0) + tx.debit - tx.credit;
    }
    final contributors = byType.entries.toList()
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
    final top = contributors.take(6).map((entry) => '${entry.key}=${_money(entry.value)}').join(' | ');
    final details = diff <= 0.01 || transactions.isEmpty
        ? 'Trial balance investigation OK: tx=${transactions.length} debit=${_money(debit)} credit=${_money(credit)} diff=${_money(diff)}.'
        : 'diff=${_money(diff)} debit=${_money(debit)} credit=${_money(credit)} tx=${transactions.length} topAccountTypes=$top possibleCause=missing expense references, reversal/payment handling for cancelled/returned invoices, or legacy accountTransactions not matching SQLite journals.';
    _addLog('INVESTIGATION_TRIAL_BALANCE $details');
    return details;
  }

  String _investigateOverpaidSales() {
    final overpaid = store.sales
        .where((sale) => !sale.isDeleted && !sale.isCancelled && sale.paidAmount > sale.invoiceTotal + 0.01)
        .toList(growable: false);
    if (overpaid.isEmpty) {
      const details = 'Overpaid sales OK: no invoices have paid amount greater than invoice total.';
      _addLog('INVESTIGATION_OVERPAID_SALES $details');
      return details;
    }
    final cancelledOrReturned = overpaid.where((sale) => sale.isCancelled || sale.status.toLowerCase().contains('return')).length;
    final zeroTotal = overpaid.where((sale) => sale.invoiceTotal.abs() <= 0.01 && sale.paidAmount > 0.01).length;
    final totalExtra = overpaid.fold<double>(0, (sum, sale) => sum + max<double>(0, sale.paidAmount - sale.invoiceTotal));
    final sample = overpaid.take(10).map((sale) => '${sale.invoiceNo}:status=${sale.status}:cancelled=${sale.isCancelled}:total=${_money(sale.invoiceTotal)}:paid=${_money(sale.paidAmount)}:extra=${_money(max<double>(0, sale.paidAmount - sale.invoiceTotal))}').join(' | ');
    final details = 'count=${overpaid.length} totalExtra=${_money(totalExtra)} zeroTotalPaid=$zeroTotal cancelledOrReturned=$cancelledOrReturned sample=$sample possibleCause=cancel/return flow may zero invoice total without reversing or clearing paid amount, or Maintenance check should ignore cancelled/returned invoices.';
    _addLog('INVESTIGATION_OVERPAID_SALES $details');
    return details;
  }

  String _investigatePerformanceSlowdown() {
    final slowRows = _report
        .where((item) => item.section.startsWith('ضغط ') && item.isWarn)
        .toList(growable: false);
    if (slowRows.isEmpty) {
      const details = 'Performance investigation OK: no pressure section crossed the slowdown threshold.';
      _addLog('INVESTIGATION_PERFORMANCE $details');
      return details;
    }
    String parseValue(String text, String key) {
      final match = RegExp('$key=([^ ]+)').firstMatch(text);
      return match?.group(1) ?? 'n/a';
    }
    final evidence = slowRows.map((row) {
      final avg = parseValue(row.details, 'avg');
      final ops = parseValue(row.details, 'ops/s');
      final slowdown = parseValue(row.details, 'slowdown');
      final curveMatch = RegExp('curve=([^ ]+)').firstMatch(row.details);
      final curve = curveMatch?.group(1) ?? 'n/a';
      final buckets = curve.split('|');
      final first = buckets.isEmpty ? 'n/a' : buckets.first;
      final last = buckets.isEmpty ? 'n/a' : buckets.last;
      return '${row.section}:${row.name}:avg=$avg opsPerSecond=$ops slowdown=$slowdown firstBucket=$first lastBucket=$last severity=Medium';
    }).join(' || ');
    final details = 'slowSections=${slowRows.length} evidence=$evidence possibleCause=growing lookup/validation cost, sync-change creation cost, or unindexed purchase/product queries under pressure.';
    _addLog('INVESTIGATION_PERFORMANCE $details');
    return details;
  }

  String _investigateSyncMode() {
    final transport = _effectiveSyncTransport();
    final pendingQueue = store.pendingSyncQueue.length;
    final pendingChanges = store.pendingSyncChanges.length;
    final failedQueue = store.syncQueue.where((item) => item.status.toLowerCase() == 'failed').length;
    final rejectedQueue = store.syncQueue.where((item) => item.status.toLowerCase() == 'rejected').length;
    final isCloud = transport == 'cloud';
    final details = isCloud
        ? 'mode=cloud pendingQueue=$pendingQueue pendingChanges=$pendingChanges failed=$failedQueue rejected=$rejectedQueue needsSync=${pendingQueue > 0 || pendingChanges > 0} interpretation=Pending changes are expected immediately after generating stress data until cloud sync completes; failed/rejected must remain zero.'
        : 'mode=$transport pendingQueue=$pendingQueue pendingChanges=$pendingChanges failed=$failedQueue rejected=$rejectedQueue needsSync=false interpretation=Local/LAN mode should not accumulate failed or rejected queue items.';
    _addLog('INVESTIGATION_SYNC_MODE $details');
    return details;
  }

  String _buildAutoSuggestions(String expenseEvidence, String balanceEvidence, String overpaidEvidence, String performanceEvidence, String syncEvidence) {
    final suggestions = <String>[];
    if (expenseEvidence.contains('missing=')) {
      suggestions.add('[1] راجع store.postExpense / AccountingService.recordExpense وتأكد من referenceType=expense و referenceId=expense.id.');
      suggestions.add('[2] إذا كانت القيود محفوظة في SQLite فقط، عدّل Stress Lab ليفحص journal_entries بدل accountTransactions للمصاريف.');
    }
    if (balanceEvidence.contains('diff=')) {
      suggestions.add('[3] شغّل مطابقة بين legacy accountTransactions و SQLite journal_entries لنفس batch.');
      suggestions.add('[4] افحص عكس القيود عند إلغاء/إرجاع البيع والشراء.');
    }
    if (overpaidEvidence.contains('count=')) {
      suggestions.add('[HIGH] افحص منطق إلغاء/إرجاع الفاتورة: لا تترك paidAmount أكبر من invoiceTotal إلا إذا كان هناك رصيد عميل مقابل.');
      suggestions.add('[MEDIUM] عدّل Maintenance overpaid_sales ليتجاهل الفواتير الملغاة/المرتجعة أو يطلب قيد عكسي واضح.');
    }
    if (performanceEvidence.contains('slowSections=')) {
      suggestions.add('[MEDIUM] راجع أقسام الأداء المتباطئة المذكورة في Performance Investigation، وابدأ بالاستعلامات/الفهارس الخاصة بالمشتريات والمنتجات.');
    }
    if (syncEvidence.contains('mode=cloud') && syncEvidence.contains('needsSync=true')) {
      suggestions.add('[LOW] في وضع Cloud، شغّل/انتظر المزامنة بعد الاختبار ثم أعد الفحص؛ pending queue وحدها ليست فشلًا ما دام failed/rejected = 0.');
    }
    if (_report.any((row) => row.section == 'المشتريات' && row.isFail) || _report.any((row) => row.section == 'المصاريف' && row.isFail)) {
      suggestions.insert(0, '[CRITICAL] تأكد أن Stress Lab يفتح الوردية النقدية قبل أي شراء أو مصروف نقدي، وليس بعدهما.');
    }
    if (suggestions.isEmpty) suggestions.add('[OK] لا توجد أسباب جذرية واضحة؛ استمر بمراقبة الأداء والنسخ الاحتياطي والمزامنة.' );
    return 'NEXT_ACTIONS ${suggestions.join(' | ')}';
  }

  void _runInventoryConsistencyChecks() {
    final productIds = store.allProductsForDiagnostics.map((product) => product.id).toSet();
    final badStockValues = store.allProductsForDiagnostics.where((product) => !product.stock.isFinite).length;
    final negativeStressStocks = store.allProductsForDiagnostics.where((product) => product.name.contains(_currentBatchId) && product.stock < -0.001).length;
    final orphanStockProducts = store.stockMovements.where((movement) => movement.productId.isNotEmpty && !productIds.contains(movement.productId)).length;
    final saleIds = store.sales.map((sale) => sale.id).toSet();
    final purchaseIds = store.purchases.map((purchase) => purchase.id).toSet();
    final orphanReferences = store.stockMovements.where((movement) {
      final type = movement.type.toLowerCase();
      if (movement.referenceId.isEmpty) return false;
      if (type.contains('sale')) return !saleIds.contains(movement.referenceId);
      if (type.contains('purchase')) return !purchaseIds.contains(movement.referenceId);
      return false;
    }).length;
    _auditCheck('المخزون المتقدم', 'صلاحية أرصدة المنتجات', badStockValues == 0, 'كل أرصدة المنتجات أرقام صالحة.', 'يوجد $badStockValues منتجات برصيد غير صالح.');
    _auditCheck('المخزون المتقدم', 'عدم وجود مخزون اختبار سالب', negativeStressStocks == 0, 'لا توجد منتجات اختبار برصيد سالب.', 'يوجد $negativeStressStocks منتجات اختبار برصيد سالب.');
    _auditCheck('المخزون المتقدم', 'عدم وجود حركات مخزون يتيمة', orphanStockProducts == 0 && orphanReferences == 0, 'لا توجد حركات مخزون يتيمة أو مراجع مفقودة.', 'حركات مخزون يتيمة: products=$orphanStockProducts references=$orphanReferences.');
  }

  void _runPerformanceHealthChecks() {
    final perfRows = _report.where((item) => item.section.startsWith('ضغط ')).toList(growable: false);
    final slowRows = perfRows.where((item) => item.isWarn).length;
    final failedRows = perfRows.where((item) => item.isFail).length;
    final hasSalesPerf = perfRows.any((item) => item.section == 'ضغط المبيعات');
    _auditCheck('الأداء', 'منحنى التباطؤ', slowRows == 0 && failedRows == 0, 'لا يوجد تباطؤ حاد في منحنيات الأداء المسجلة كل 100 عملية.', 'يوجد $slowRows منحنيات أداء متباطئة و $failedRows اختبارات ضغط فاشلة.', warning: true);
    _auditCheck('الأداء', 'تغطية قياس المبيعات', hasSalesPerf, 'تم قياس أداء المبيعات تحت ضغط 1000 عملية.', 'لم يتم العثور على قياس ضغط للمبيعات.', warning: true);
  }

  int _scoreForSection(String section, int weight) {
    final rows = _report.where((item) => item.section == section || item.section.startsWith('$section ')).toList(growable: false);
    if (rows.isEmpty) return weight;
    final fails = rows.where((item) => item.isFail).length;
    final warns = rows.where((item) => item.isWarn).length;
    final penalty = fails * 25 + warns * 10;
    return max<int>(0, weight - penalty);
  }

  Map<String, int> _calculateHealthScores() {
    final performance = _scoreForSection('ضغط', 20) + _scoreForSection('الأداء', 10);
    final accounting = _scoreForSection('المحاسبة', 15) + _scoreForSection('المحاسبة المتقدمة', 15);
    final inventory = _scoreForSection('المخزون', 8) + _scoreForSection('المخزون المتقدم', 7);
    final integrity = _scoreForSection('سلامة البيانات', 10);
    final maintenance = _scoreForSection('صيانة التطبيق', 5) + _scoreForSection('أدلة الصيانة', 5);
    final backup = _scoreForSection('النسخ الاحتياطي', 5);
    final sync = _scoreForSection('المزامنة', 5);
    final total = performance + accounting + inventory + integrity + maintenance + backup + sync;
    return <String, int>{
      'total': total,
      'performance': performance,
      'accounting': accounting,
      'inventory': inventory,
      'integrity': integrity,
      'maintenance': maintenance,
      'backup': backup,
      'sync': sync,
    };
  }

  void _addHealthScoreReport() {
    final scores = _calculateHealthScores();
    final total = scores['total'] ?? 0;
    final verdict = total >= 95 ? 'VENTIO READY FOR PRODUCTION' : total >= 80 ? 'VENTIO READY WITH WARNINGS' : 'VENTIO NOT READY';
    _addLog('========== VENTIO HEALTH SCORE ==========' );
    _addLog("System Health=$total/100 | Performance=${scores['performance']}/30 | Accounting=${scores['accounting']}/30 | Inventory=${scores['inventory']}/15 | Integrity=${scores['integrity']}/10 | Maintenance=${scores['maintenance']}/10 | Backup=${scores['backup']}/5 | Sync=${scores['sync']}/5");
    _addLog('Verdict: $verdict');
    if (_healthHistory.isNotEmpty) {
      final previous = _healthHistory.last;
      String delta(String key) {
        final currentValue = scores[key] ?? 0;
        final previousValue = previous[key] ?? 0;
        final diff = currentValue - previousValue;
        return '$key:previous=$previousValue current=$currentValue delta=${diff >= 0 ? '+' : ''}$diff';
      }
      _addLog("HEALTH_SCORE_COMPARISON ${delta('total')} | ${delta('performance')} | ${delta('accounting')} | ${delta('inventory')} | ${delta('maintenance')}");
    } else {
      _addLog('HEALTH_SCORE_COMPARISON previous=none current=$total/100');
    }
    _healthHistory.add(Map<String, int>.from(scores));
    if (_healthHistory.length > 10) _healthHistory.removeRange(0, _healthHistory.length - 10);
    _addLog('=========================================' );
  }

  void _addFinalAuditReport(DateTime startedAt) {
    final pass = _report.where((item) => item.isPass).length;
    final warn = _report.where((item) => item.isWarn).length;
    final fail = _report.where((item) => item.isFail).length;
    final elapsed = DateTime.now().difference(startedAt).inSeconds;
    final overall = fail > 0 ? 'فشل' : warn > 0 ? 'نجح مع تحذيرات' : 'نجح';
    _addHealthScoreReport();
    _addLog('========== VENTIO STRESS LAB FINAL REPORT ==========');
    _addLog('النتيجة العامة: $overall | نجاح=$pass | تحذيرات=$warn | فشل=$fail | الزمن=${elapsed}s | batch=$_currentBatchId');
    final sections = _report.map((item) => item.section).toSet().toList()..sort();
    for (final section in sections) {
      final rows = _report.where((item) => item.section == section).toList();
      final p = rows.where((item) => item.isPass).length;
      final w = rows.where((item) => item.isWarn).length;
      final f = rows.where((item) => item.isFail).length;
      _addLog('[$section] نجاح=$p تحذيرات=$w فشل=$f');
      for (final row in rows) {
        _addLog(' - ${row.status} ${row.name} (${row.elapsedMs}ms): ${row.details}');
      }
    }
    _addLog('====================================================');
  }

  Future<void> _copyLog() async {
    final text = _log.join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_tf('copied_log_lines', {'count': _log.length}))));
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
    final pass = _report.where((item) => item.isPass).length;
    final warn = _report.where((item) => item.isWarn).length;
    final fail = _report.where((item) => item.isFail).length;
    final overall = _report.isEmpty
        ? 'لم يتم تشغيل الاختبار بعد'
        : fail > 0
            ? 'فشل'
            : warn > 0
                ? 'نجح مع تحذيرات'
                : 'نجح بالكامل';
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
                    const Text('اختبار شامل بزر واحد ينشئ حالات حقيقية من أقسام التطبيق، ثم يضرب عدد العمليات ×1000 ويقيس سرعة كل نوع إضافة وتباطؤ الأداء.'),
                    const SizedBox(height: 8),
                    Text(_tf('role_device_transport_epoch', {'role': _roleLabel(), 'device': identity.deviceId, 'transport': _effectiveSyncTransport(), 'epoch': identity.storeEpoch})),
                    const SizedBox(height: 16),
                    LinearProgressIndicator(value: _running ? _progress : null),
                    const SizedBox(height: 8),
                    Text(_status),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _running ? null : _runOneButtonSystemAudit,
                      icon: const Icon(Icons.health_and_safety_outlined),
                      label: const Text('تشغيل اختبار الضغط الشامل ×1000'),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _log.isEmpty ? null : _copyLog,
                          icon: const Icon(Icons.copy),
                          label: const Text('نسخ التقرير الكامل'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _running ? null : _clearLog,
                          icon: const Icon(Icons.clear_all),
                          label: const Text('مسح التقرير'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_report.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('النتيجة العامة: $overall', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      Text('نجاح: $pass   تحذيرات: $warn   فشل: $fail'),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Expanded(
              child: _report.isEmpty
                  ? DecoratedBox(
                      decoration: BoxDecoration(border: Border.all(color: Theme.of(context).dividerColor), borderRadius: BorderRadius.circular(8)),
                      child: const Center(child: Text('اضغط تشغيل الاختبار الشامل للحصول على تقرير.')),
                    )
                  : ListView.builder(
                      itemCount: _report.length,
                      itemBuilder: (context, index) {
                        final item = _report[index];
                        final icon = item.isPass
                            ? Icons.check_circle_outline
                            : item.isWarn
                                ? Icons.warning_amber_outlined
                                : Icons.error_outline;
                        return Card(
                          child: ListTile(
                            leading: Icon(icon),
                            title: Text('${item.section} — ${item.name}'),
                            subtitle: Text('${item.details}\nالمدة: ${item.elapsedMs} ms'),
                            isThreeLine: true,
                            trailing: Text(item.status),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

