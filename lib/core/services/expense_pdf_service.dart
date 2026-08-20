import 'dart:typed_data';
import 'dart:ui' show Locale;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../models/expense.dart';
import '../../models/store_profile.dart';
import '../utils/currency_utils.dart';
import 'professional_pdf_theme.dart';

class ExpensePdfService {
  static Future<Uint8List> buildExpensePdf({
    required Expense expense,
    required StoreProfile profile,
    Locale locale = const Locale('en'),
  }) async {
    final labels = _ExpensePdfLabels(locale.languageCode);
    final isArabic = labels.isArabic;
    final theme = await ProfessionalPdfTheme.loadTheme();
    final pdf = pw.Document(theme: theme);

    final originalAmount = formatCurrency(
      expense.originalAmount ?? expense.amount,
      currency: expense.originalCurrency,
    );
    final referenceAmount = formatUsdReferenceAmount(expense.amount, profile);
    final status = _statusLabel(labels, expense);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(24, 22, 24, 22),
        textDirection: isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        header: (context) => context.pageNumber == 1
            ? ProfessionalPdfTheme.header(
                profile: profile,
                title: labels.expense,
                englishTitle: 'EXPENSE',
                isArabic: isArabic,
                meta: [
                  MapEntry(labels.no, expense.id),
                  MapEntry(labels.date, _formatDate(expense.date)),
                  MapEntry(labels.status, status),
                ],
              )
            : ProfessionalPdfTheme.compactHeader(profile: profile, title: labels.expense),
        footer: (context) => ProfessionalPdfTheme.footer(context: context, profile: profile, isArabic: isArabic),
        build: (_) => [
          ProfessionalPdfTheme.infoStrip(
            isArabic: isArabic,
            entries: [
              MapEntry(labels.title, expense.title),
              MapEntry(labels.category, expense.category),
              MapEntry(labels.status, status),
            ],
          ),
          pw.SizedBox(height: 14),
          ProfessionalPdfTheme.summaryBox(
            isArabic: isArabic,
            highlightIndex: 0,
            rows: [
              MapEntry(labels.amount, originalAmount),
              MapEntry(labels.referenceAmount, referenceAmount),
            ],
          ),
          if (expense.notes.trim().isNotEmpty) ...[
            pw.SizedBox(height: 16),
            ProfessionalPdfTheme.note(labels.notes, expense.notes.trim(), isArabic: isArabic),
          ],
          if (expense.cancelReason.trim().isNotEmpty) ...[
            pw.SizedBox(height: 10),
            ProfessionalPdfTheme.note(labels.cancelReason, expense.cancelReason.trim(), isArabic: isArabic),
          ],
        ],
      ),
    );
    return pdf.save();
  }

  static Future<void> printExpense({
    required Expense expense,
    required StoreProfile profile,
    Locale locale = const Locale('en'),
  }) async {
    final bytes = await buildExpensePdf(expense: expense, profile: profile, locale: locale);
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: expense.title);
  }

  static String _statusLabel(_ExpensePdfLabels labels, Expense expense) => expense.isCancelled
      ? labels.cancelled
      : expense.isPosted
          ? labels.posted
          : labels.draft;

  static String _formatDate(DateTime date) {
    final local = date.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
  }
}

class _ExpensePdfLabels {
  const _ExpensePdfLabels(this.languageCode);

  final String languageCode;

  bool get isArabic => languageCode == 'ar';
  bool get isFrench => languageCode == 'fr';

  String get expense => isArabic
      ? 'المصروف'
      : isFrench
          ? 'Dépense'
          : 'Expense';
  String get phone => isArabic
      ? 'الهاتف'
      : isFrench
          ? 'Téléphone'
          : 'Phone';
  String get address => isArabic
      ? 'العنوان'
      : isFrench
          ? 'Adresse'
          : 'Address';
  String get no => isArabic
      ? 'الرقم'
      : isFrench
          ? 'N°'
          : 'No';
  String get date => isArabic
      ? 'التاريخ'
      : isFrench
          ? 'Date'
          : 'Date';
  String get status => isArabic
      ? 'الحالة'
      : isFrench
          ? 'Statut'
          : 'Status';
  String get field => isArabic
      ? 'الحقل'
      : isFrench
          ? 'Champ'
          : 'Field';
  String get value => isArabic
      ? 'القيمة'
      : isFrench
          ? 'Valeur'
          : 'Value';
  String get title => isArabic
      ? 'العنوان'
      : isFrench
          ? 'Titre'
          : 'Title';
  String get category => isArabic
      ? 'الفئة'
      : isFrench
          ? 'Catégorie'
          : 'Category';
  String get amount => isArabic
      ? 'المبلغ'
      : isFrench
          ? 'Montant'
          : 'Amount';
  String get referenceAmount => isArabic
      ? 'القيمة المرجعية'
      : isFrench
          ? 'Montant de référence'
          : 'Reference Amount';
  String get notes => isArabic
      ? 'ملاحظات'
      : isFrench
          ? 'Notes'
          : 'Notes';
  String get cancelReason => isArabic
      ? 'سبب الإلغاء'
      : isFrench
          ? 'Motif d’annulation'
          : 'Cancel Reason';
  String get draft => isArabic
      ? 'مسودة'
      : isFrench
          ? 'Brouillon'
          : 'Draft';
  String get posted => isArabic
      ? 'معتمد'
      : isFrench
          ? 'Comptabilisé'
          : 'Posted';
  String get cancelled => isArabic
      ? 'ملغي'
      : isFrench
          ? 'Annulé'
          : 'Cancelled';
}
