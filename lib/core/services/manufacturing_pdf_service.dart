import 'dart:ui' show Locale;

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../models/manufacturing.dart';
import '../../models/store_profile.dart';

class ManufacturingPdfService {
  static Future<_Fonts> _fonts() async => _Fonts(
        pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf')),
        pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf')),
      );

  static Future<Uint8List> buildBillOfMaterialsPdf({
    required BillOfMaterials bom,
    required StoreProfile profile,
    Locale locale = const Locale('en'),
  }) async {
    final fonts = await _fonts();
    final labels = _Labels(locale.languageCode);
    final pdf = pw.Document(theme: pw.ThemeData.withFont(base: fonts.base, bold: fonts.bold));
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        textDirection: labels.isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        build: (_) => [
          _header(profile, labels.recipe, labels),
          pw.SizedBox(height: 18),
          _infoBox([
            '${labels.recipeName}: ${bom.name}',
            '${labels.outputProduct}: ${bom.outputProductName}',
            '${labels.outputQuantity}: ${_qty(bom.outputQuantity)}',
            '${labels.unitCost}: ${bom.unitCost.toStringAsFixed(2)}',
          ]),
          pw.SizedBox(height: 18),
          pw.TableHelper.fromTextArray(
            border: null,
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headers: [labels.component, labels.quantity, labels.unitCost, labels.totalCost],
            data: bom.components
                .map((item) => [
                      item.productName,
                      _qty(item.quantity),
                      item.unitCost.toStringAsFixed(2),
                      item.lineCost.toStringAsFixed(2),
                    ])
                .toList(growable: false),
          ),
          if (bom.notes.trim().isNotEmpty) ...[
            pw.SizedBox(height: 18),
            pw.Text('${labels.notes}: ${bom.notes.trim()}'),
          ],
          if (profile.footerNote.trim().isNotEmpty) ...[
            pw.SizedBox(height: 24),
            pw.Text(profile.footerNote),
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
    final fonts = await _fonts();
    final labels = _Labels(locale.languageCode);
    final pdf = pw.Document(theme: pw.ThemeData.withFont(base: fonts.base, bold: fonts.bold));
    final ratio = bom == null || bom.outputQuantity <= 0 ? 0.0 : order.quantity / bom.outputQuantity;
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        textDirection: labels.isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        build: (_) => [
          _header(profile, labels.order, labels),
          pw.SizedBox(height: 18),
          _infoBox([
            '${labels.orderNo}: ${order.orderNo}',
            '${labels.date}: ${_date(order.date)}',
            '${labels.recipeName}: ${order.bomName}',
            '${labels.outputProduct}: ${order.outputProductName}',
            '${labels.producedQuantity}: ${_qty(order.quantity)}',
            '${labels.status}: ${order.status}',
            '${labels.rawWarehouse}: ${order.rawMaterialsWarehouseName}',
            '${labels.finishedWarehouse}: ${order.finishedGoodsWarehouseName}',
          ]),
          if (bom != null && bom.components.isNotEmpty) ...[
            pw.SizedBox(height: 18),
            pw.Text(labels.consumedMaterials, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              border: null,
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headers: [labels.component, labels.quantity],
              data: bom.components
                  .map((item) => [item.productName, _qty(item.quantity * ratio)])
                  .toList(growable: false),
            ),
          ],
          if (order.notes.trim().isNotEmpty) ...[
            pw.SizedBox(height: 18),
            pw.Text('${labels.notes}: ${order.notes.trim()}'),
          ],
          if (profile.footerNote.trim().isNotEmpty) ...[
            pw.SizedBox(height: 24),
            pw.Text(profile.footerNote),
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
    final fonts = await _fonts();
    final labels = _Labels(locale.languageCode);
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(base: fonts.base, bold: fonts.bold),
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        textDirection:
            labels.isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        build: (_) => [
          _header(profile, labels.orders, labels),
          pw.SizedBox(height: 8),
          pw.Text('${labels.orderCount}: ${orders.length}'),
          pw.SizedBox(height: 16),
          if (!includeDetails)
            pw.TableHelper.fromTextArray(
              border: null,
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey300),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headers: [
                labels.orderNo,
                labels.date,
                labels.outputProduct,
                labels.producedQuantity,
                labels.status,
                labels.recipeName,
              ],
              data: orders
                  .map((order) => [
                        order.orderNo,
                        _date(order.date),
                        order.outputProductName,
                        _qty(order.quantity),
                        order.status,
                        order.bomName,
                      ])
                  .toList(growable: false),
            )
          else
            for (final order in orders) ...[
              _manufacturingOrderBlock(
                order: order,
                bom: bomsById[order.bomId],
                labels: labels,
              ),
              pw.SizedBox(height: 14),
            ],
          if (profile.footerNote.trim().isNotEmpty) ...[
            pw.SizedBox(height: 24),
            pw.Text(profile.footerNote),
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
    final bytes = await buildManufacturingOrdersPdf(
      orders: orders,
      bomsById: bomsById,
      includeDetails: includeDetails,
      profile: profile,
      locale: locale,
    );
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'manufacturing-orders-${orders.length}',
    );
  }

  static pw.Widget _manufacturingOrderBlock({
    required ManufacturingOrder order,
    required BillOfMaterials? bom,
    required _Labels labels,
  }) {
    final ratio =
        bom == null || bom.outputQuantity <= 0 ? 0.0 : order.quantity / bom.outputQuantity;
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '${labels.orderNo}: ${order.orderNo}',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13),
          ),
          pw.SizedBox(height: 5),
          pw.Text(
            '${labels.date}: ${_date(order.date)}   •   ${labels.outputProduct}: ${order.outputProductName}   •   ${labels.producedQuantity}: ${_qty(order.quantity)}',
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            '${labels.status}: ${order.status}   •   ${labels.recipeName}: ${order.bomName}',
          ),
          pw.SizedBox(height: 8),
          if (bom != null && bom.components.isNotEmpty) ...[
            pw.Text(
              labels.recipeDetails,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 5),
            pw.TableHelper.fromTextArray(
              border: null,
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey200),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headers: [labels.component, labels.quantity],
              data: bom.components
                  .map((item) => [
                        item.productName,
                        _qty(item.quantity * ratio),
                      ])
                  .toList(growable: false),
            ),
          ] else
            pw.Text(labels.noRecipeDetails),
        ],
      ),
    );
  }

  static pw.Widget _header(StoreProfile profile, String title, _Labels labels) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(profile.name, style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
              if (profile.phone.isNotEmpty) pw.Text('${labels.phone}: ${profile.phone}'),
              if (profile.address.isNotEmpty) pw.Text('${labels.address}: ${profile.address}'),
            ],
          ),
          pw.Text(title, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
        ],
      );

  static pw.Widget _infoBox(List<String> lines) => pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400)),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [for (final line in lines) pw.Padding(padding: const pw.EdgeInsets.only(bottom: 4), child: pw.Text(line))],
        ),
      );

  static String _qty(double value) {
    if ((value - value.roundToDouble()).abs() < 0.000001) return value.toStringAsFixed(0);
    return value.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }

  static String _date(DateTime value) {
    final d = value.toLocal();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}

class _Fonts {
  const _Fonts(this.base, this.bold);
  final pw.Font base;
  final pw.Font bold;
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
