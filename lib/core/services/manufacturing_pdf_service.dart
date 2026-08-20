import 'dart:typed_data';
import 'dart:ui' show Locale;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../models/manufacturing.dart';
import '../../models/store_profile.dart';
import 'professional_pdf_theme.dart';

class ManufacturingPdfService {
  static Future<Uint8List> buildBillOfMaterialsPdf({
    required BillOfMaterials bom,
    required StoreProfile profile,
    Locale locale = const Locale('en'),
  }) async {
    final labels = _Labels(locale.languageCode);
    final isArabic = labels.isArabic;
    final pdf = pw.Document(theme: await ProfessionalPdfTheme.loadTheme());
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(24, 22, 24, 22),
        textDirection: isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        header: (context) => context.pageNumber == 1
            ? ProfessionalPdfTheme.header(
                profile: profile,
                title: labels.recipe,
                englishTitle: 'MANUFACTURING RECIPE',
                isArabic: isArabic,
                meta: [
                  MapEntry(labels.recipeName, bom.name),
                  MapEntry(labels.outputProduct, bom.outputProductName),
                  MapEntry(labels.outputQuantity, _qty(bom.outputQuantity)),
                ],
              )
            : ProfessionalPdfTheme.compactHeader(profile: profile, title: labels.recipe),
        footer: (context) => ProfessionalPdfTheme.footer(context: context, profile: profile, isArabic: isArabic, languageCode: labels.languageCode),
        build: (_) => [
          ProfessionalPdfTheme.infoStrip(
            isArabic: isArabic,
            entries: [
              MapEntry(labels.recipeName, bom.name),
              MapEntry(labels.outputProduct, bom.outputProductName),
              MapEntry(labels.unitCost, bom.unitCost.toStringAsFixed(2)),
            ],
          ),
          pw.SizedBox(height: 14),
          ProfessionalPdfTheme.table(
            headers: [labels.component, labels.quantity, labels.unitCost, labels.totalCost],
            data: bom.components.map((item) => [
              item.productName,
              _qty(item.quantity),
              item.unitCost.toStringAsFixed(2),
              item.lineCost.toStringAsFixed(2),
            ]).toList(growable: false),
            columnWidths: const {
              0: pw.FlexColumnWidth(2.7),
              1: pw.FlexColumnWidth(1),
              2: pw.FlexColumnWidth(1),
              3: pw.FlexColumnWidth(1),
            },
          ),
          if (bom.notes.trim().isNotEmpty) ...[
            pw.SizedBox(height: 14),
            ProfessionalPdfTheme.note(labels.notes, bom.notes.trim(), isArabic: isArabic),
          ],
        ],
      ),
    );
    return pdf.save();
  }

  static Future<void> printBillOfMaterials({
    required BillOfMaterials bom,
    required StoreProfile profile,
    Locale locale = const Locale('en'),
  }) async {
    final bytes = await buildBillOfMaterialsPdf(bom: bom, profile: profile, locale: locale);
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: bom.name.isEmpty ? 'manufacturing-recipe' : bom.name);
  }

  static Future<Uint8List> buildManufacturingOrderPdf({
    required ManufacturingOrder order,
    BillOfMaterials? bom,
    required StoreProfile profile,
    Locale locale = const Locale('en'),
  }) async {
    final labels = _Labels(locale.languageCode);
    final isArabic = labels.isArabic;
    final pdf = pw.Document(theme: await ProfessionalPdfTheme.loadTheme());
    final ratio = bom == null || bom.outputQuantity <= 0 ? 0.0 : order.quantity / bom.outputQuantity;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(24, 22, 24, 22),
        textDirection: isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        header: (context) => context.pageNumber == 1
            ? ProfessionalPdfTheme.header(
                profile: profile,
                title: labels.order,
                englishTitle: 'MANUFACTURING ORDER',
                isArabic: isArabic,
                meta: [
                  MapEntry(labels.orderNo, order.orderNo),
                  MapEntry(labels.date, _date(order.date)),
                  MapEntry(labels.status, order.status),
                ],
              )
            : ProfessionalPdfTheme.compactHeader(profile: profile, title: labels.order),
        footer: (context) => ProfessionalPdfTheme.footer(context: context, profile: profile, isArabic: isArabic, languageCode: labels.languageCode),
        build: (_) => [
          ProfessionalPdfTheme.infoStrip(
            isArabic: isArabic,
            entries: [
              MapEntry(labels.recipeName, order.bomName),
              MapEntry(labels.outputProduct, order.outputProductName),
              MapEntry(labels.producedQuantity, _qty(order.quantity)),
            ],
          ),
          pw.SizedBox(height: 10),
          ProfessionalPdfTheme.infoStrip(
            isArabic: isArabic,
            entries: [
              MapEntry(labels.rawWarehouse, order.rawMaterialsWarehouseName),
              MapEntry(labels.finishedWarehouse, order.finishedGoodsWarehouseName),
            ],
          ),
          if (bom != null && bom.components.isNotEmpty) ...[
            pw.SizedBox(height: 16),
            pw.Text(labels.consumedMaterials, textDirection: isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr, style: pw.TextStyle(color: ProfessionalPdfTheme.navy, fontSize: 12, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            ProfessionalPdfTheme.table(
              headers: [labels.component, labels.quantity],
              data: bom.components.map((item) => [item.productName, _qty(item.quantity * ratio)]).toList(growable: false),
              columnWidths: const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(1)},
            ),
          ],
          if (order.notes.trim().isNotEmpty) ...[
            pw.SizedBox(height: 14),
            ProfessionalPdfTheme.note(labels.notes, order.notes.trim(), isArabic: isArabic),
          ],
        ],
      ),
    );
    return pdf.save();
  }

  static Future<void> printManufacturingOrder({
    required ManufacturingOrder order,
    BillOfMaterials? bom,
    required StoreProfile profile,
    Locale locale = const Locale('en'),
  }) async {
    final bytes = await buildManufacturingOrderPdf(order: order, bom: bom, profile: profile, locale: locale);
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: order.orderNo.isEmpty ? 'manufacturing-order' : order.orderNo);
  }

  static Future<Uint8List> buildManufacturingOrdersPdf({
    required List<ManufacturingOrder> orders,
    required Map<String, BillOfMaterials> bomsById,
    required bool includeDetails,
    required StoreProfile profile,
    Locale locale = const Locale('en'),
  }) async {
    final labels = _Labels(locale.languageCode);
    final isArabic = labels.isArabic;
    final pdf = pw.Document(theme: await ProfessionalPdfTheme.loadTheme());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(24, 22, 24, 22),
        textDirection: isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        header: (context) => context.pageNumber == 1
            ? ProfessionalPdfTheme.header(
                profile: profile,
                title: labels.orders,
                englishTitle: 'MANUFACTURING ORDERS',
                isArabic: isArabic,
                meta: [MapEntry(labels.orderCount, '${orders.length}')],
              )
            : ProfessionalPdfTheme.compactHeader(profile: profile, title: labels.orders),
        footer: (context) => ProfessionalPdfTheme.footer(context: context, profile: profile, isArabic: isArabic, languageCode: labels.languageCode),
        build: (_) => [
          if (!includeDetails)
            ProfessionalPdfTheme.table(
              headers: [labels.orderNo, labels.date, labels.outputProduct, labels.producedQuantity, labels.status, labels.recipeName],
              data: orders.map((order) => [
                order.orderNo,
                _date(order.date),
                order.outputProductName,
                _qty(order.quantity),
                order.status,
                order.bomName,
              ]).toList(growable: false),
              cellStyle: const pw.TextStyle(fontSize: 7.5),
            )
          else
            for (final order in orders) ...[
              _manufacturingOrderBlock(order: order, bom: bomsById[order.bomId], labels: labels),
              pw.SizedBox(height: 10),
            ],
        ],
      ),
    );
    return pdf.save();
  }

  static Future<void> printManufacturingOrders({
    required List<ManufacturingOrder> orders,
    required Map<String, BillOfMaterials> bomsById,
    required bool includeDetails,
    required StoreProfile profile,
    Locale locale = const Locale('en'),
  }) async {
    if (orders.isEmpty) return;
    final bytes = await buildManufacturingOrdersPdf(orders: orders, bomsById: bomsById, includeDetails: includeDetails, profile: profile, locale: locale);
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'manufacturing-orders-${orders.length}');
  }

  static pw.Widget _manufacturingOrderBlock({
    required ManufacturingOrder order,
    required BillOfMaterials? bom,
    required _Labels labels,
  }) {
    final ratio = bom == null || bom.outputQuantity <= 0 ? 0.0 : order.quantity / bom.outputQuantity;
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: ProfessionalPdfTheme.line, width: .8)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Directionality(
            textDirection: labels.isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.start,
              children: [
                pw.Text(
                  '${labels.orderNo}:',
                  textDirection: labels.isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
                  style: pw.TextStyle(
                    color: ProfessionalPdfTheme.navy,
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
                pw.SizedBox(width: 4),
                pw.Text(
                  order.orderNo,
                  textDirection: pw.TextDirection.ltr,
                  style: pw.TextStyle(
                    color: ProfessionalPdfTheme.navy,
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 5),
          ProfessionalPdfTheme.infoStrip(
            isArabic: labels.isArabic,
            flexes: const [23, 40, 17, 20],
            verticalPadding: 7,
            entries: [
              MapEntry(labels.date, _date(order.date)),
              MapEntry(labels.outputProduct, order.outputProductName),
              MapEntry(labels.producedQuantity, _qty(order.quantity)),
              MapEntry(labels.status, order.status),
            ],
          ),
          if (bom != null && bom.components.isNotEmpty) ...[
            pw.SizedBox(height: 7),
            ProfessionalPdfTheme.table(
              headers: [labels.component, labels.quantity],
              data: bom.components.map((item) => [item.productName, _qty(item.quantity * ratio)]).toList(growable: false),
              columnWidths: const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(1)},
            ),
          ] else ...[
            pw.SizedBox(height: 8),
            pw.Text(labels.noRecipeDetails, textDirection: labels.isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr, style: const pw.TextStyle(color: ProfessionalPdfTheme.muted, fontSize: 8)),
          ],
        ],
      ),
    );
  }

  static String _qty(double value) {
    if ((value - value.roundToDouble()).abs() < 0.000001) return value.toStringAsFixed(0);
    return value.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }

  static String _date(DateTime value) {
    final d = value.toLocal();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}

class _Labels {
  const _Labels(this.languageCode);
  final String languageCode;
  bool get isArabic => languageCode == 'ar';
  bool get isFrench => languageCode == 'fr';
  String _v(String ar, String en, String fr) => isArabic ? ar : isFrench ? fr : en;
  String get recipe => _v('وصفة تصنيع', 'Manufacturing Recipe', 'Recette de fabrication');
  String get order => _v('أمر تصنيع', 'Manufacturing Order', 'Ordre de fabrication');
  String get phone => _v('الهاتف', 'Phone', 'Téléphone');
  String get address => _v('العنوان', 'Address', 'Adresse');
  String get recipeName => _v('الوصفة', 'Recipe', 'Recette');
  String get outputProduct => _v('المنتج النهائي', 'Output product', 'Produit fini');
  String get outputQuantity => _v('كمية الناتج', 'Output quantity', 'Quantité produite');
  String get unitCost => _v('تكلفة الوحدة', 'Unit cost', 'Coût unitaire');
  String get component => _v('المادة', 'Component', 'Composant');
  String get quantity => _v('الكمية', 'Quantity', 'Quantité');
  String get totalCost => _v('التكلفة الإجمالية', 'Total cost', 'Coût total');
  String get notes => _v('ملاحظات', 'Notes', 'Notes');
  String get orderNo => _v('رقم الأمر', 'Order no.', 'N° ordre');
  String get date => _v('التاريخ', 'Date', 'Date');
  String get producedQuantity => _v('الكمية المصنعة', 'Produced quantity', 'Quantité fabriquée');
  String get status => _v('الحالة', 'Status', 'Statut');
  String get rawWarehouse => _v('مستودع المواد الأولية', 'Raw materials warehouse', 'Entrepôt matières premières');
  String get finishedWarehouse => _v('مستودع المنتج النهائي', 'Finished goods warehouse', 'Entrepôt produits finis');
  String get consumedMaterials => _v('المواد المستهلكة', 'Consumed materials', 'Matières consommées');
  String get orders => _v('أوامر التصنيع', 'Manufacturing Orders', 'Ordres de fabrication');
  String get orderCount => _v('عدد الأوامر', 'Order count', 'Nombre d’ordres');
  String get recipeDetails => _v('تفاصيل الوصفة', 'Recipe details', 'Détails de la recette');
  String get noRecipeDetails => _v('لا توجد تفاصيل وصفة متاحة', 'No recipe details available', 'Aucun détail de recette disponible');
}
