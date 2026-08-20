import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../models/product.dart';
import '../../models/store_profile.dart';
import 'professional_pdf_theme.dart';

class PriceListPdfService {
  static Future<Uint8List> build({
    required List<Product> products,
    required StoreProfile profile,
    required String title,
    List<String> fields = const <String>[],
    String Function(Product product, String field)? valueResolver,
    bool arabic = false,
  }) async {
    final theme = await ProfessionalPdfTheme.loadTheme();
    final pdf = pw.Document(theme: theme);
    final now = DateTime.now().toLocal();
    final date = '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

    final headers = [
      arabic ? 'المنتج' : 'Product',
      ...fields.map((field) => _fieldLabel(field, arabic)),
    ];
    final data = products.map((p) => [
      p.name,
      ...fields.map((field) => valueResolver?.call(p, field) ?? _fieldValue(p, field)),
    ]).toList(growable: false);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(24, 22, 24, 22),
        textDirection: arabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        header: (context) => context.pageNumber == 1
            ? ProfessionalPdfTheme.header(
                profile: profile,
                title: title,
                englishTitle: 'PRICE LIST',
                isArabic: arabic,
                meta: [
                  MapEntry(arabic ? 'التاريخ' : 'Date', date),
                  MapEntry(arabic ? 'عدد الأصناف' : 'Products', '${products.length}'),
                ],
              )
            : ProfessionalPdfTheme.compactHeader(profile: profile, title: title),
        footer: (context) => ProfessionalPdfTheme.footer(context: context, profile: profile, isArabic: arabic),
        build: (_) => [
          if (products.isEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 30),
              child: pw.Center(child: pw.Text(arabic ? 'لا توجد أصناف.' : 'No products.')),
            )
          else
            ProfessionalPdfTheme.table(headers: headers, data: data),
        ],
      ),
    );
    return pdf.save();
  }

  static Future<void> printPriceList({
    required List<Product> products,
    required StoreProfile profile,
    required String title,
    List<String> fields = const <String>[],
    String Function(Product product, String field)? valueResolver,
    bool arabic = false,
  }) async {
    final bytes = await build(products: products, profile: profile, title: title, fields: fields, valueResolver: valueResolver, arabic: arabic);
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'price-list');
  }

  static String _fieldLabel(String field, bool arabic) {
    switch (field) {
      case 'name':
        return arabic ? 'الاسم' : 'Name';
      case 'nameEn':
        return arabic ? 'الاسم الإنجليزي' : 'English name';
      case 'nameAr':
        return arabic ? 'الاسم العربي' : 'Arabic name';
      case 'code':
        return arabic ? 'الكود' : 'Code';
      case 'barcode':
        return arabic ? 'الباركود' : 'Barcode';
      case 'category':
        return arabic ? 'الفئة' : 'Category';
      case 'brand':
        return arabic ? 'الماركة' : 'Brand';
      case 'supplier':
        return arabic ? 'المورد' : 'Supplier';
      case 'description':
        return arabic ? 'الوصف' : 'Description';
      case 'unit':
        return arabic ? 'الوحدة' : 'Unit';
      case 'quantityType':
        return arabic ? 'نوع الكمية' : 'Quantity type';
      case 'stock':
        return arabic ? 'المخزون' : 'Stock';
      case 'lowStockThreshold':
        return arabic ? 'حد المخزون المنخفض' : 'Low stock threshold';
      case 'cost':
        return arabic ? 'الكلفة' : 'Cost';
      case 'price':
        return arabic ? 'التجزئة' : 'Retail';
      case 'wholesale':
        return arabic ? 'الجملة' : 'Wholesale';
      case 'wholesale_bulk':
        return arabic ? 'جملة الجملة' : 'Wholesale bulk';
      case 'isActive':
        return arabic ? 'الحالة' : 'Status';
      case 'imagePath':
        return arabic ? 'الصورة' : 'Image';
      default:
        return field;
    }
  }

  static String _fieldValue(Product product, String field) {
    switch (field) {
      case 'name':
        return product.name;
      case 'nameEn':
        return product.nameEn;
      case 'nameAr':
        return product.nameAr;
      case 'code':
        return product.code;
      case 'barcode':
        return product.barcode;
      case 'category':
        return product.category;
      case 'brand':
        return product.brand;
      case 'supplier':
        return product.supplier;
      case 'description':
        return product.description;
      case 'unit':
        return product.unit;
      case 'quantityType':
        return product.quantityType == ProductQuantityType.measurable ? 'measurable' : 'countable';
      case 'stock':
        return product.stock.toStringAsFixed(2);
      case 'lowStockThreshold':
        return product.lowStockThreshold.toString();
      case 'cost':
        return _formatPrice(product.originalCost, product.costCurrency);
      case 'price':
        return _formatPrice(product.originalPrice, product.originalCurrency);
      case 'wholesale':
        return _formatPrice(product.price, product.originalCurrency);
      case 'wholesale_bulk':
        return _formatPrice(product.price, product.originalCurrency);
      case 'isActive':
        return product.isActive ? 'Active' : 'Inactive';
      case 'imagePath':
        return product.imagePath.isEmpty ? '-' : product.imagePath;
      default:
        return '-';
    }
  }

  static String _formatPrice(double value, String currency) {
    return '$currency ${value.toStringAsFixed(2)}';
  }

}
