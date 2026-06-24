import 'package:drift/drift.dart';

import '../../models/account_transaction.dart';
import '../../models/aging_report.dart';
import '../../models/purchase.dart';
import '../../models/sale.dart';
import '../storage/sqlite/sqlite_migration_manager.dart';
import '../storage/sqlite/ventio_drift_database.dart';

/// Priority #1: Aging Reports.
///
/// Builds customer receivable and supplier payable aging using FIFO allocation:
/// invoices/purchases are aged by their document date, while later receipts/payments
/// reduce the oldest open documents first. Buckets are current, 0-30, 31-60,
/// 61-90, and 90+ days as of the selected date.
class AccountingAgingService {
  AccountingAgingService._();

  static Future<AgingReportResult> customerAgingReport({DateTime? asOfDate}) async {
    final db = _dbOrNull;
    if (db == null) {
      return AgingReportResult(asOfDate: _dateOnly(asOfDate ?? DateTime.now()), rows: const <AgingReportRow>[], openDocuments: const <AgingOpenDocument>[]);
    }
    final rows = await db.customSelect(
      '''
      SELECT je.reference_id, je.reference_no, je.entry_date, jl.party_id, jl.party_name,
             SUM(jl.debit - jl.credit) AS amount
      FROM journal_lines jl
      INNER JOIN journal_entries je ON je.id = jl.entry_id
      INNER JOIN accounting_settings s ON s.key = 'default_customers_account_id' AND s.account_id = jl.account_id
      WHERE je.status = 'posted' AND jl.party_type = 'customer'
      GROUP BY je.reference_id, je.reference_no, je.entry_date, jl.party_id, jl.party_name
      HAVING ABS(amount) > 0.0001
      ORDER BY datetime(je.entry_date), je.reference_no
      ''',
    ).get();
    return _buildFromLedgerRows(rows, asOfDate ?? DateTime.now(), receivableMode: true);
  }

  static Future<AgingReportResult> supplierAgingReport({DateTime? asOfDate}) async {
    final db = _dbOrNull;
    if (db == null) {
      return AgingReportResult(asOfDate: _dateOnly(asOfDate ?? DateTime.now()), rows: const <AgingReportRow>[], openDocuments: const <AgingOpenDocument>[]);
    }
    final rows = await db.customSelect(
      '''
      SELECT je.reference_id, je.reference_no, je.entry_date, jl.party_id, jl.party_name,
             SUM(jl.credit - jl.debit) AS amount
      FROM journal_lines jl
      INNER JOIN journal_entries je ON je.id = jl.entry_id
      INNER JOIN accounting_settings s ON s.key = 'default_suppliers_account_id' AND s.account_id = jl.account_id
      WHERE je.status = 'posted' AND jl.party_type = 'supplier'
      GROUP BY je.reference_id, je.reference_no, je.entry_date, jl.party_id, jl.party_name
      HAVING ABS(amount) > 0.0001
      ORDER BY datetime(je.entry_date), je.reference_no
      ''',
    ).get();
    return _buildFromLedgerRows(rows, asOfDate ?? DateTime.now(), receivableMode: false);
  }

  static AgingReportResult customerAgingFromStore({
    required List<Sale> sales,
    required List<AccountTransaction> accountTransactions,
    DateTime? asOfDate,
  }) {
    final asOf = _dateOnly(asOfDate ?? DateTime.now());
    final documents = <_AgingDocument>[];
    final paymentsByParty = <String, double>{};

    for (final sale in sales) {
      if (sale.isDeleted || sale.isCancelled || sale.total <= 0 || sale.date.isAfter(asOf)) continue;
      final partyId = _partyKey(sale.customerId, sale.customerName);
      final invoiceTotal = _clean(sale.invoiceTotal);
      final saleTotal = _clean(sale.total);
      final paidInInvoiceCurrency = _clean(sale.paidAmount.clamp(0, invoiceTotal).toDouble());
      final paid = invoiceTotal <= 0 ? 0.0 : _clean(saleTotal * (paidInInvoiceCurrency / invoiceTotal));
      final open = _roundMoney(saleTotal - paid);
      if (open > 0) {
        documents.add(_AgingDocument(
          id: sale.id,
          number: sale.invoiceNo,
          partyId: partyId,
          partyName: sale.customerName.trim().isEmpty ? 'Walk-in customer' : sale.customerName.trim(),
          date: _dateOnly(sale.date),
          originalAmount: saleTotal,
          openAmount: open,
        ));
      }
    }

    for (final txn in accountTransactions) {
      if (txn.isDeleted || !txn.isCustomer || txn.date.isAfter(asOf)) continue;
      final amount = _roundMoney(txn.credit - txn.debit);
      if (amount > 0) {
        final partyId = _partyKey(txn.accountId, txn.accountName);
        paymentsByParty[partyId] = _roundMoney((paymentsByParty[partyId] ?? 0) + amount);
      }
    }

    return _buildReport(documents, paymentsByParty, asOf);
  }

  static AgingReportResult supplierAgingFromStore({
    required List<Purchase> purchases,
    required List<AccountTransaction> accountTransactions,
    DateTime? asOfDate,
  }) {
    final asOf = _dateOnly(asOfDate ?? DateTime.now());
    final documents = <_AgingDocument>[];
    final paymentsByParty = <String, double>{};

    for (final purchase in purchases) {
      if (purchase.isDeleted || purchase.isCancelled || purchase.subtotal <= 0 || purchase.date.isAfter(asOf)) continue;
      final partyId = _partyKey(purchase.supplierId, purchase.supplierName);
      final subtotal = _clean(purchase.subtotal);
      final open = _roundMoney(subtotal - _clean(purchase.paidAmount.clamp(0, subtotal).toDouble()));
      if (open > 0) {
        documents.add(_AgingDocument(
          id: purchase.id,
          number: purchase.purchaseNo,
          partyId: partyId,
          partyName: purchase.supplierName.trim().isEmpty ? 'Unknown supplier' : purchase.supplierName.trim(),
          date: _dateOnly(purchase.date),
          originalAmount: subtotal,
          openAmount: open,
        ));
      }
    }

    for (final txn in accountTransactions) {
      if (txn.isDeleted || !txn.isSupplier || txn.date.isAfter(asOf)) continue;
      final amount = _roundMoney(txn.debit - txn.credit);
      if (amount > 0) {
        final partyId = _partyKey(txn.accountId, txn.accountName);
        paymentsByParty[partyId] = _roundMoney((paymentsByParty[partyId] ?? 0) + amount);
      }
    }

    return _buildReport(documents, paymentsByParty, asOf);
  }

  static VentioDriftDatabase? get _dbOrNull => SqliteMigrationManager.database;

  static AgingReportResult _buildFromLedgerRows(List<QueryRow> rows, DateTime asOfDate, {required bool receivableMode}) {
    final asOf = _dateOnly(asOfDate);
    final documents = <_AgingDocument>[];
    final paymentsByParty = <String, double>{};

    for (final row in rows) {
      final data = row.data;
      final amount = _roundMoney(_num(data['amount']));
      final partyName = data['party_name']?.toString().trim() ?? '';
      final partyId = _partyKey(data['party_id']?.toString() ?? '', partyName);
      final date = _dateOnly(DateTime.tryParse(data['entry_date']?.toString() ?? '') ?? asOf);
      if (date.isAfter(asOf)) continue;
      if (amount > 0) {
        documents.add(_AgingDocument(
          id: data['reference_id']?.toString() ?? '',
          number: data['reference_no']?.toString() ?? '',
          partyId: partyId,
          partyName: partyName.isEmpty ? (receivableMode ? 'Walk-in customer' : 'Unknown supplier') : partyName,
          date: date,
          originalAmount: amount,
          openAmount: amount,
        ));
      } else if (amount < 0) {
        paymentsByParty[partyId] = _roundMoney((paymentsByParty[partyId] ?? 0) + amount.abs());
      }
    }
    return _buildReport(documents, paymentsByParty, asOf);
  }

  static AgingReportResult _buildReport(List<_AgingDocument> documents, Map<String, double> paymentsByParty, DateTime asOf) {
    documents.sort((a, b) {
      final byParty = a.partyName.toLowerCase().compareTo(b.partyName.toLowerCase());
      if (byParty != 0) return byParty;
      final byDate = a.date.compareTo(b.date);
      if (byDate != 0) return byDate;
      return a.number.compareTo(b.number);
    });

    for (final partyId in paymentsByParty.keys) {
      var remainingPayment = _roundMoney(paymentsByParty[partyId] ?? 0);
      if (remainingPayment <= 0) continue;
      final partyDocs = documents.where((doc) => doc.partyId == partyId).toList()..sort((a, b) => a.date.compareTo(b.date));
      for (final doc in partyDocs) {
        if (remainingPayment <= 0) break;
        final applied = remainingPayment > doc.openAmount ? doc.openAmount : remainingPayment;
        doc.openAmount = _roundMoney(doc.openAmount - applied);
        remainingPayment = _roundMoney(remainingPayment - applied);
      }
    }

    final totals = <String, _AgingTotals>{};
    final openDocuments = <AgingOpenDocument>[];
    for (final doc in documents) {
      if (doc.openAmount <= 0.009) continue;
      final ageDays = asOf.difference(doc.date).inDays;
      final bucket = _bucketLabel(ageDays);
      final totalsRow = totals.putIfAbsent(doc.partyId, () => _AgingTotals(partyId: doc.partyId, partyName: doc.partyName));
      totalsRow.add(bucket, doc.openAmount);
      openDocuments.add(AgingOpenDocument(
        id: doc.id,
        number: doc.number,
        partyId: doc.partyId,
        partyName: doc.partyName,
        date: doc.date,
        originalAmount: doc.originalAmount,
        openAmount: doc.openAmount,
        bucketLabel: bucket,
        ageDays: ageDays < 0 ? 0 : ageDays,
      ));
    }

    final rows = totals.values.map((row) => row.toRow()).where((row) => row.total > 0.009).toList()
      ..sort((a, b) => b.total.compareTo(a.total));
    openDocuments.sort((a, b) => b.openAmount.compareTo(a.openAmount));
    return AgingReportResult(asOfDate: asOf, rows: rows, openDocuments: openDocuments);
  }

  static String _bucketLabel(int ageDays) {
    if (ageDays <= 0) return 'current';
    if (ageDays <= 30) return '0_30';
    if (ageDays <= 60) return '31_60';
    if (ageDays <= 90) return '61_90';
    return '90_plus';
  }

  static DateTime _dateOnly(DateTime value) => DateTime(value.year, value.month, value.day);
  static String _partyKey(String id, String name) => id.trim().isNotEmpty ? id.trim() : 'name:${name.trim().toLowerCase()}';
  static double _clean(double value) => value.isFinite && value > 0 ? value : 0;
  static double _num(Object? value) => value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '') ?? 0;
  static double _roundMoney(double value) => (value * 100).roundToDouble() / 100;
}

class _AgingDocument {
  _AgingDocument({required this.id, required this.number, required this.partyId, required this.partyName, required this.date, required this.originalAmount, required this.openAmount});

  final String id;
  final String number;
  final String partyId;
  final String partyName;
  final DateTime date;
  final double originalAmount;
  double openAmount;
}

class _AgingTotals {
  _AgingTotals({required this.partyId, required this.partyName});

  final String partyId;
  final String partyName;
  double current = 0;
  double days1To30 = 0;
  double days31To60 = 0;
  double days61To90 = 0;
  double over90 = 0;

  void add(String bucket, double amount) {
    switch (bucket) {
      case 'current':
        current += amount;
        break;
      case '0_30':
        days1To30 += amount;
        break;
      case '31_60':
        days31To60 += amount;
        break;
      case '61_90':
        days61To90 += amount;
        break;
      default:
        over90 += amount;
    }
  }

  AgingReportRow toRow() => AgingReportRow(
        partyId: partyId,
        partyName: partyName,
        current: AccountingAgingService._roundMoney(current),
        days1To30: AccountingAgingService._roundMoney(days1To30),
        days31To60: AccountingAgingService._roundMoney(days31To60),
        days61To90: AccountingAgingService._roundMoney(days61To90),
        over90: AccountingAgingService._roundMoney(over90),
        total: AccountingAgingService._roundMoney(current + days1To30 + days31To60 + days61To90 + over90),
      );
}
