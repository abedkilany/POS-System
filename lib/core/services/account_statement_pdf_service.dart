import 'dart:typed_data';
import 'dart:ui' show Locale;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../models/account_transaction.dart';
import '../../models/expense.dart';
import '../../models/store_profile.dart';
import '../utils/currency_utils.dart';
import 'professional_pdf_theme.dart';

/// Builds printable, date-bounded account and expense statements.
///
/// Account statements intentionally consume the same AccountTransaction rows
/// used by the on-screen ledger. This keeps the printed statement consistent
/// with the balance shown in the application.
class AccountStatementPdfService {
  static Future<Uint8List> buildAccountStatementPdf({
    required String accountType,
    required String accountName,
    required List<AccountTransaction> transactions,
    required DateTime from,
    required DateTime to,
    required StoreProfile profile,
    Locale locale = const Locale('en'),
  }) async {
    final labels = _StatementLabels(locale.languageCode);
    final rows = _accountRows(
      transactions: transactions,
      from: from,
      to: to,
      labels: labels,
    );
    return _buildPdf(
      title: accountType.toLowerCase() == 'customer'
          ? labels.customerStatement
          : labels.supplierStatement,
      englishTitle: 'ACCOUNT STATEMENT',
      partyName: accountName,
      from: from,
      to: to,
      rows: rows,
      profile: profile,
      locale: locale,
      labels: labels,
      openingBalance: _openingBalance(transactions, from),
      showBalance: true,
    );
  }

  static Future<void> printAccountStatement({
    required String accountType,
    required String accountName,
    required List<AccountTransaction> transactions,
    required DateTime from,
    required DateTime to,
    required StoreProfile profile,
    Locale locale = const Locale('en'),
  }) async {
    final bytes = await buildAccountStatementPdf(
      accountType: accountType,
      accountName: accountName,
      transactions: transactions,
      from: from,
      to: to,
      profile: profile,
      locale: locale,
    );
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'account-statement-$accountName',
    );
  }

  static Future<Uint8List> buildExpenseStatementPdf({
    required List<Expense> expenses,
    required DateTime from,
    required DateTime to,
    required StoreProfile profile,
    String accountName = '',
    Locale locale = const Locale('en'),
  }) async {
    final labels = _StatementLabels(locale.languageCode);
    final rows = _expenseRows(expenses, from, to, labels);
    return _buildPdf(
      title: labels.expenseStatement,
      englishTitle: 'EXPENSE STATEMENT',
      partyName: accountName.trim().isEmpty ? profile.name : accountName,
      from: from,
      to: to,
      rows: rows,
      profile: profile,
      locale: locale,
      labels: labels,
      openingBalance: 0,
      showBalance: false,
    );
  }

  static Future<void> printExpenseStatement({
    required List<Expense> expenses,
    required DateTime from,
    required DateTime to,
    required StoreProfile profile,
    String accountName = '',
    Locale locale = const Locale('en'),
  }) async {
    final bytes = await buildExpenseStatementPdf(
      expenses: expenses,
      from: from,
      to: to,
      profile: profile,
      accountName: accountName,
      locale: locale,
    );
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'expense-statement',
    );
  }

  static List<_StatementRow> _accountRows({
    required List<AccountTransaction> transactions,
    required DateTime from,
    required DateTime to,
    required _StatementLabels labels,
  }) {
    final opening = _openingBalance(transactions, from);
    var running = opening;
    final filtered = transactions
        .where((item) =>
            !item.isDeleted &&
            !_isBefore(item.date, from) &&
            !_isAfter(item.date, to))
        .toList()
      ..sort((a, b) {
        final byDate = a.date.compareTo(b.date);
        return byDate != 0 ? byDate : a.id.compareTo(b.id);
      });

    return filtered.map((item) {
      running += item.signedAmount;
      return _StatementRow(
        date: item.date,
        type: _transactionLabel(item.type, labels),
        reference: item.referenceNo.trim().isEmpty
            ? item.referenceId
            : item.referenceNo,
        description: [item.note, item.paymentMethod]
            .where((part) => part.trim().isNotEmpty)
            .join(' • '),
        debit: item.debit,
        credit: item.credit,
        balance: running,
      );
    }).toList(growable: false);
  }

  static List<_StatementRow> _expenseRows(
    List<Expense> expenses,
    DateTime from,
    DateTime to,
    _StatementLabels labels,
  ) {
    final filtered = expenses
        .where((expense) =>
            !expense.isDeleted &&
            !expense.isDraft &&
            !_isBefore(expense.date, from) &&
            !_isAfter(expense.date, to))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    var running = 0.0;
    return filtered.map((expense) {
      final isCancelled = expense.isCancelled;
      final amount = expense.amount;
      final debit = isCancelled ? 0.0 : amount;
      final credit = isCancelled ? amount : 0.0;
      running += debit - credit;
      return _StatementRow(
        date: expense.date,
        type: isCancelled ? labels.expenseReversal : labels.expense,
        reference: expense.id,
        description: [expense.category, expense.title, expense.notes]
            .where((part) => part.trim().isNotEmpty)
            .join(' • '),
        debit: debit,
        credit: credit,
        balance: running,
      );
    }).toList(growable: false);
  }

  static double _openingBalance(
    List<AccountTransaction> transactions,
    DateTime from,
  ) =>
      transactions
          .where((item) => !item.isDeleted && _isBefore(item.date, from))
          .fold<double>(0, (sum, item) => sum + item.signedAmount);

  static bool _isBefore(DateTime value, DateTime boundary) =>
      value.isBefore(boundary);

  static bool _isAfter(DateTime value, DateTime boundary) =>
      value.isAfter(boundary);

  static Future<Uint8List> _buildPdf({
    required String title,
    required String englishTitle,
    required String partyName,
    required DateTime from,
    required DateTime to,
    required List<_StatementRow> rows,
    required StoreProfile profile,
    required Locale locale,
    required _StatementLabels labels,
    required double openingBalance,
    required bool showBalance,
  }) async {
    final isArabic = labels.isArabic;
    final theme = await ProfessionalPdfTheme.loadTheme();
    final pdf = pw.Document(theme: theme);
    final totalDebit = rows.fold<double>(0, (sum, row) => sum + row.debit);
    final totalCredit = rows.fold<double>(0, (sum, row) => sum + row.credit);
    final closingBalance = openingBalance + totalDebit - totalCredit;
    final headers = isArabic
        ? <String>[
            if (showBalance) labels.balance,
            labels.credit,
            labels.debit,
            labels.reference,
            labels.details,
            labels.type,
            labels.date,
          ]
        : <String>[
            labels.date,
            labels.type,
            labels.details,
            labels.reference,
            labels.debit,
            labels.credit,
            if (showBalance) labels.balance,
          ];
    final data = rows.map((row) {
      final values = <String>[
        _formatDate(row.date),
        row.type,
        row.description,
        row.reference,
        _money(row.debit, profile),
        _money(row.credit, profile),
        _money(row.balance, profile),
      ];
      return isArabic
          ? <String>[
              if (showBalance) values[6],
              values[5],
              values[4],
              values[3],
              values[2],
              values[1],
              values[0],
            ]
          : <String>[
              values[0],
              values[1],
              values[2],
              values[3],
              values[4],
              values[5],
              if (showBalance) values[6],
            ];
    }).toList(growable: false);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(24, 22, 24, 22),
        textDirection: isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        header: (context) => context.pageNumber == 1
            ? ProfessionalPdfTheme.header(
                profile: profile,
                title: title,
                englishTitle: englishTitle,
                isArabic: isArabic,
                meta: [
                  MapEntry(labels.account, partyName),
                  MapEntry(labels.from, _formatDate(from)),
                  MapEntry(labels.to, _formatDate(to)),
                ],
              )
            : ProfessionalPdfTheme.compactHeader(
                profile: profile,
                title: title,
              ),
        footer: (context) => ProfessionalPdfTheme.footer(
          context: context,
          profile: profile,
          isArabic: isArabic,
          languageCode: locale.languageCode,
        ),
        build: (_) => [
          ProfessionalPdfTheme.infoStrip(
            isArabic: isArabic,
            entries: [
              MapEntry(labels.account, partyName),
              MapEntry(
                  labels.period, '${_formatDate(from)} - ${_formatDate(to)}'),
              MapEntry(labels.movements, '${rows.length}'),
            ],
          ),
          pw.SizedBox(height: 14),
          ProfessionalPdfTheme.table(
            headers: headers,
            data: data,
            columnWidths: _columnWidths(showBalance, isArabic),
          ),
          pw.SizedBox(height: 14),
          ProfessionalPdfTheme.summaryBox(
            isArabic: isArabic,
            highlightIndex: showBalance ? 3 : 2,
            rows: [
              if (showBalance)
                MapEntry(
                    labels.openingBalance, _money(openingBalance, profile)),
              MapEntry(labels.totalDebit, _money(totalDebit, profile)),
              MapEntry(labels.totalCredit, _money(totalCredit, profile)),
              MapEntry(showBalance ? labels.closingBalance : labels.netExpenses,
                  _money(closingBalance, profile)),
            ],
          ),
          if (rows.isEmpty) ...[
            pw.SizedBox(height: 16),
            pw.Center(
              child: pw.Text(labels.noMovements,
                  textDirection:
                      isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr),
            ),
          ],
        ],
      ),
    );
    return pdf.save();
  }

  static Map<int, pw.TableColumnWidth> _columnWidths(
    bool showBalance,
    bool isArabic,
  ) {
    if (!showBalance) {
      return <int, pw.TableColumnWidth>{
        0: const pw.FlexColumnWidth(1.2),
        1: const pw.FlexColumnWidth(1.4),
        2: const pw.FlexColumnWidth(2.4),
        3: const pw.FlexColumnWidth(1.6),
        4: const pw.FlexColumnWidth(1.1),
        5: const pw.FlexColumnWidth(1.1),
      };
    }
    return <int, pw.TableColumnWidth>{
      0: const pw.FlexColumnWidth(1.2),
      1: const pw.FlexColumnWidth(1.1),
      2: const pw.FlexColumnWidth(1.1),
      3: const pw.FlexColumnWidth(1.6),
      4: const pw.FlexColumnWidth(2.0),
      5: const pw.FlexColumnWidth(1.35),
      6: const pw.FlexColumnWidth(1.2),
    };
  }

  static String _transactionLabel(String type, _StatementLabels labels) {
    switch (type) {
      case 'saleInvoice':
        return labels.saleInvoice;
      case 'purchaseInvoice':
        return labels.purchaseInvoice;
      case 'paymentReceived':
        return labels.paymentReceived;
      case 'paymentPaid':
        return labels.paymentPaid;
      case 'paymentReversal':
        return labels.paymentReversal;
      case 'saleReturn':
      case 'salesReturn':
        return labels.saleReturn;
      case 'purchaseReturn':
      case 'purchasesReturn':
        return labels.purchaseReturn;
      case 'cancel':
        return labels.cancellation;
      case 'adjustment':
        return labels.adjustment;
      case 'expense':
        return labels.expense;
      default:
        return type.trim().isEmpty ? labels.other : type;
    }
  }

  static String _money(double amount, StoreProfile profile) =>
      formatUsdReferenceAmount(amount.abs(), profile);

  static String _formatDate(DateTime value) {
    final local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
  }
}

class _StatementRow {
  const _StatementRow({
    required this.date,
    required this.type,
    required this.reference,
    required this.description,
    required this.debit,
    required this.credit,
    required this.balance,
  });

  final DateTime date;
  final String type, reference, description;
  final double debit, credit, balance;
}

class _StatementLabels {
  const _StatementLabels(this.languageCode);

  final String languageCode;
  bool get isArabic => languageCode == 'ar';
  bool get isFrench => languageCode == 'fr';

  String get account => isArabic
      ? 'الحساب'
      : isFrench
          ? 'Compte'
          : 'Account';
  String get from => isArabic
      ? 'من تاريخ'
      : isFrench
          ? 'Du'
          : 'From';
  String get to => isArabic
      ? 'إلى تاريخ'
      : isFrench
          ? 'Au'
          : 'To';
  String get period => isArabic
      ? 'الفترة'
      : isFrench
          ? 'Période'
          : 'Period';
  String get movements => isArabic
      ? 'عدد الحركات'
      : isFrench
          ? 'Mouvements'
          : 'Movements';
  String get date => isArabic
      ? 'التاريخ'
      : isFrench
          ? 'Date'
          : 'Date';
  String get type => isArabic
      ? 'نوع الحركة'
      : isFrench
          ? 'Type'
          : 'Type';
  String get reference => isArabic
      ? 'المرجع'
      : isFrench
          ? 'Référence'
          : 'Reference';
  String get details => isArabic
      ? 'التفاصيل'
      : isFrench
          ? 'Détails'
          : 'Details';
  String get debit => isArabic
      ? 'مدين'
      : isFrench
          ? 'Débit'
          : 'Debit';
  String get credit => isArabic
      ? 'دائن'
      : isFrench
          ? 'Crédit'
          : 'Credit';
  String get balance => isArabic
      ? 'الرصيد'
      : isFrench
          ? 'Solde'
          : 'Balance';
  String get openingBalance => isArabic
      ? 'الرصيد الافتتاحي'
      : isFrench
          ? 'Solde initial'
          : 'Opening Balance';
  String get totalDebit => isArabic
      ? 'إجمالي المدين'
      : isFrench
          ? 'Total débit'
          : 'Total Debit';
  String get totalCredit => isArabic
      ? 'إجمالي الدائن'
      : isFrench
          ? 'Total crédit'
          : 'Total Credit';
  String get closingBalance => isArabic
      ? 'الرصيد الختامي'
      : isFrench
          ? 'Solde final'
          : 'Closing Balance';
  String get netExpenses => isArabic
      ? 'صافي المصاريف'
      : isFrench
          ? 'Dépenses nettes'
          : 'Net Expenses';
  String get noMovements => isArabic
      ? 'لا توجد حركات ضمن الفترة المحددة.'
      : isFrench
          ? 'Aucun mouvement pour cette période.'
          : 'No movements in the selected period.';
  String get customerStatement => isArabic
      ? 'كشف حساب زبون'
      : isFrench
          ? 'Relevé client'
          : 'Customer Statement';
  String get supplierStatement => isArabic
      ? 'كشف حساب مورد'
      : isFrench
          ? 'Relevé fournisseur'
          : 'Supplier Statement';
  String get expenseStatement => isArabic
      ? 'كشف المصاريف'
      : isFrench
          ? 'Relevé des dépenses'
          : 'Expense Statement';
  String get saleInvoice => isArabic
      ? 'فاتورة بيع'
      : isFrench
          ? 'Facture de vente'
          : 'Sale Invoice';
  String get purchaseInvoice => isArabic
      ? 'فاتورة شراء'
      : isFrench
          ? "Facture d'achat"
          : 'Purchase Invoice';
  String get paymentReceived => isArabic
      ? 'سند قبض'
      : isFrench
          ? 'Encaissement'
          : 'Payment Received';
  String get paymentPaid => isArabic
      ? 'سند دفع'
      : isFrench
          ? 'Paiement'
          : 'Payment Paid';
  String get paymentReversal => isArabic
      ? 'عكس سند دفع'
      : isFrench
          ? 'Annulation de paiement'
          : 'Payment Reversal';
  String get saleReturn => isArabic
      ? 'مرتجع مبيعات'
      : isFrench
          ? 'Retour de vente'
          : 'Sales Return';
  String get purchaseReturn => isArabic
      ? 'مرتجع مشتريات'
      : isFrench
          ? "Retour d'achat"
          : 'Purchase Return';
  String get cancellation => isArabic
      ? 'إلغاء / عكس'
      : isFrench
          ? 'Annulation'
          : 'Cancellation / Reversal';
  String get adjustment => isArabic
      ? 'تسوية'
      : isFrench
          ? 'Ajustement'
          : 'Adjustment';
  String get expense => isArabic
      ? 'مصروف'
      : isFrench
          ? 'Dépense'
          : 'Expense';
  String get expenseReversal => isArabic
      ? 'عكس مصروف ملغى'
      : isFrench
          ? 'Annulation de dépense'
          : 'Expense Reversal';
  String get other => isArabic
      ? 'حركة أخرى'
      : isFrench
          ? 'Autre mouvement'
          : 'Other Movement';
}
