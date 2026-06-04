import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/cloud_sync_service.dart';
import '../../core/sync_unified/sync_unified.dart';
import '../../data/app_store.dart';
import '../../models/app_identity.dart';
import '../../models/customer.dart';
import '../../models/product.dart';
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
  final _log = <String>[];
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
        'sales=${store.sales.length} stockMovements=${store.stockMovements.length} '
        'pendingQueue=${store.pendingSyncQueue.length} pendingChanges=${store.pendingSyncChanges.length} '
        'allQueue=${store.syncQueue.length} allChanges=${store.syncChanges.length} rejectedQueue=$rejectedQueue failedQueue=$failedQueue';
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
      _log.clear();
      _status = 'Starting...';
      _currentBatchId = 'stress_${DateTime.now().millisecondsSinceEpoch}_${_roleLabel().toLowerCase()}';
    });

    try {
      _addLog('VENTIO_REAL_APP_STRESS_START batch=$_currentBatchId buildMode=${kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug')}');
      _addLog(_snapshotLine('BEFORE'));
      await _seedCatalog();
      await _createSales();
      await _runActiveSync();
      await _exportBackupProbe();
      _addLog(_snapshotLine('AFTER'));
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
    });
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
                    Text('Temporary real-app simulation. Uses the real AppStore services, stock logic, sync queue, and active sync transport.'),
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
                    LinearProgressIndicator(value: _running ? _progress : null),
                    const SizedBox(height: 8),
                    Text(_status),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: _running ? null : _runFullSimulation,
                          icon: const Icon(Icons.science),
                          label: const Text('Run Real App Stress Simulation'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _running ? null : _runActiveSync,
                          icon: const Icon(Icons.sync),
                          label: const Text('Sync Now Only'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _running ? null : _compactSyncedSyncHistory,
                          icon: const Icon(Icons.cleaning_services_outlined),
                          label: const Text('Clean Synced Sync Logs'),
                        ),
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
