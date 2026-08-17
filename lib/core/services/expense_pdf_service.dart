import 'dart:ui' show Locale;

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../models/expense.dart';
import '../../models/store_profile.dart';
import '../utils/currency_utils.dart';

class ExpensePdfService {
  static Future<Uint8List> buildExpensePdf({
    required Expense expense,
    required StoreProfile profile,
    Locale locale = const Locale('en'),
  }) async {
    final baseFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/DejaVuSans.ttf'),
    );
    final boldFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf'),
    );
    final labels = _ExpensePdfLabels(locale.languageCode);
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
    );

    final originalAmount = formatCurrency(
      expense.originalAmount ?? expense.amount,
      currency: expense.originalCurrency,
    );
    final referenceAmount = formatUsdReferenceAmount(expense.amount, profile);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        textDirection:
            labels.isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        build: (_) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(profile.name,
                      style: pw.TextStyle(
                          fontSize: 22, fontWeight: pw.FontWeight.bold)),
                  if (profile.phone.isNotEmpty)
                    pw.Text('${labels.phone}: ${profile.phone}'),
                  if (profile.address.isNotEmpty)
                    pw.Text('${labels.address}: ${profile.address}'),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(labels.expense,
                      style: pw.TextStyle(
                          fontSize: 20, fontWeight: pw.FontWeight.bold)),
                  pw.Text('${labels.no}: ${expense.id}'),
                  pw.Text('${labels.date}: ${_formatDate(expense.date)}'),
                  pw.Text('${labels.status}: ${_statusLabel(labels, expense)}'),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            border: null,
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headers: [labels.field, labels.value],
            data: [
              [labels.title, expense.title],
              [labels.category, expense.category],
              [labels.amount, originalAmount],
              [labels.referenceAmount, referenceAmount],
              [labels.date, _formatDate(expense.date)],
              [labels.status, _statusLabel(labels, expense)],
              if (expense.notes.trim().isNotEmpty)
                [labels.notes, expense.notes.trim()],
              if (expense.cancelReason.trim().isNotEmpty)
                [labels.cancelReason, expense.cancelReason.trim()],
            ],
          ),
          pw.SizedBox(height: 24),
          pw.Text(profile.footerNote),
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
    final bytes = await buildExpensePdf(
      expense: expense,
      profile: profile,
      locale: locale,
    );
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: expense.title,
    );
  }

  static String _statusLabel(_ExpensePdfLabels labels, Expense expense) =>
      expense.isCancelled
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
