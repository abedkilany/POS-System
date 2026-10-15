import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../models/credit_note.dart';
import '../../models/sale.dart';
import '../../models/store_profile.dart';
import '../../models/print_settings.dart';
import '../utils/currency_utils.dart';
import 'pdf_font_loader.dart';
import 'posted_document_snapshot_service.dart';
import 'print_service.dart';

part 'invoice_pdf_service_impl_01.dart';
part 'invoice_pdf_service_impl_02.dart';
part 'invoice_pdf_service_impl_03.dart';

const PdfColor _navy = PdfColor(0.035, 0.13, 0.25);

const PdfColor _gold = PdfColor(0.84, 0.61, 0.10);

const PdfColor _ink = PdfColor(0.08, 0.11, 0.17);

const PdfColor _muted = PdfColor(0.39, 0.43, 0.50);

const PdfColor _line = PdfColor(0.86, 0.88, 0.91);

const PdfColor _soft = PdfColor(0.972, 0.976, 0.982);

class InvoicePdfService {
  InvoicePdfService();
  static final _InvoicePdfServiceImplementation
      _invoicePdfServiceImplementation = _InvoicePdfServiceImplementation();
  static Future<Uint8List> buildInvoicePdf({
    required Sale sale,
    required StoreProfile profile,
    Locale locale = const Locale('en'),
    bool isReturn = false,
    PdfPageFormat pageFormat = PdfPageFormat.a4,
  }) =>
      _invoicePdfServiceImplementation.buildInvoicePdf(
          sale: sale,
          profile: profile,
          locale: locale,
          isReturn: isReturn,
          pageFormat: pageFormat);

  static Future<void> printInvoice({
    BuildContext? context,
    required Sale sale,
    required StoreProfile profile,
    Locale locale = const Locale('en'),
  }) =>
      _invoicePdfServiceImplementation.printInvoice(
          context: context, sale: sale, profile: profile, locale: locale);

  static Future<void> shareInvoice({
    required Sale sale,
    required StoreProfile profile,
    Locale locale = const Locale('en'),
  }) =>
      _invoicePdfServiceImplementation.shareInvoice(
          sale: sale, profile: profile, locale: locale);

  static Future<void> printSaleReturn({
    BuildContext? context,
    required CreditNote creditNote,
    required StoreProfile profile,
    Locale locale = const Locale('en'),
  }) =>
      _invoicePdfServiceImplementation.printSaleReturn(
          context: context,
          creditNote: creditNote,
          profile: profile,
          locale: locale);

  static Future<Uint8List> buildSaleReturnPdf({
    required CreditNote creditNote,
    required StoreProfile profile,
    Locale locale = const Locale('en'),
    PdfPageFormat pageFormat = PdfPageFormat.a4,
  }) =>
      _invoicePdfServiceImplementation.buildSaleReturnPdf(
          creditNote: creditNote,
          profile: profile,
          locale: locale,
          pageFormat: pageFormat);
}

class _InvoicePdfServiceImplementation {}

class _InvoicePdfLabels {
  const _InvoicePdfLabels(this.languageCode, {this.isReturn = false});

  final String languageCode;
  final bool isReturn;
  bool get isArabic => languageCode == 'ar';
  bool get isFrench => languageCode == 'fr';

  String get invoiceNo => isArabic
      ? 'رقم الفاتورة'
      : isFrench
          ? 'N° facture'
          : 'Invoice No.';
  String get salesInvoice => isReturn
      ? (isArabic
          ? 'مرتجع مبيعات'
          : isFrench
              ? 'Retour de vente'
              : 'Sales Return')
      : isArabic
          ? 'فاتورة مبيعات'
          : isFrench
              ? 'Facture de vente'
              : 'Sales Invoice';
  String get date => isArabic
      ? 'التاريخ'
      : isFrench
          ? 'Date'
          : 'Date';
  String get time => isArabic
      ? 'الوقت'
      : isFrench
          ? 'Heure'
          : 'Time';
  String get customer => isArabic
      ? 'العميل'
      : isFrench
          ? 'Client'
          : 'Customer';
  String get paymentMethod => isArabic
      ? 'طريقة الدفع'
      : isFrench
          ? 'Mode de paiement'
          : 'Payment Method';
  String get cash => isArabic
      ? 'نقداً'
      : isFrench
          ? 'Espèces'
          : 'Cash';
  String get card => isArabic
      ? 'بطاقة'
      : isFrench
          ? 'Carte'
          : 'Card';
  String get credit => isArabic
      ? 'آجل'
      : isFrench
          ? 'À crédit'
          : 'Credit';
  String get item => isArabic
      ? 'الصنف'
      : isFrench
          ? 'Article'
          : 'Item';
  String get qty => isArabic
      ? 'الكمية'
      : isFrench
          ? 'Qté'
          : 'Qty';
  String get unitPrice => isArabic
      ? 'سعر الوحدة'
      : isFrench
          ? 'Prix unitaire'
          : 'Unit Price';
  String get lineTotal => isArabic
      ? 'الإجمالي'
      : isFrench
          ? 'Total ligne'
          : 'Line Total';
  String get subtotal => isArabic
      ? 'المجموع الفرعي'
      : isFrench
          ? 'Sous-total'
          : 'Subtotal';
  String get discount => isArabic
      ? 'الخصم'
      : isFrench
          ? 'Remise'
          : 'Discount';
  String get total => isArabic
      ? 'الإجمالي'
      : isFrench
          ? 'Total'
          : 'Total';
  String get tax => isArabic
      ? 'الضريبة'
      : isFrench
          ? 'TVA'
          : 'Tax';
  String get netAmount => isArabic
      ? 'الصافي قبل الضريبة'
      : isFrench
          ? 'Montant net avant TVA'
          : 'Net before VAT';
  String get vat => isArabic
      ? 'ضريبة القيمة المضافة'
      : isFrench
          ? 'TVA'
          : 'VAT';
  String get exempt => isArabic
      ? 'معفى'
      : isFrench
          ? 'Exonéré'
          : 'Exempt';
  String get outOfScope => isArabic
      ? 'خارج النطاق'
      : isFrench
          ? 'Hors champ'
          : 'Out of scope';
  String get thankYou => isArabic
      ? 'شكراً لتسوقكم معنا'
      : isFrench
          ? 'Merci pour votre achat'
          : 'Thank you for shopping with us';
}
