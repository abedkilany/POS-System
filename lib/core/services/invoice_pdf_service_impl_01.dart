part of 'invoice_pdf_service.dart';

extension _InvoicePdfServicePart1 on _InvoicePdfServiceImplementation {
  Future<Uint8List> buildInvoicePdf({
    required Sale sale,
    required StoreProfile profile,
    Locale locale = const Locale('en'),
    bool isReturn = false,
    PdfPageFormat pageFormat = PdfPageFormat.a4,
  }) async {
    final documentSale = PostedDocumentSnapshotService.saleView(sale);
    final documentProfile =
        PostedDocumentSnapshotService.profileForSale(sale, profile);
    final labels = _InvoicePdfLabels(
      locale.languageCode,
      isReturn: isReturn,
    );
    final isArabic = locale.languageCode == 'ar';
    final pdfFonts = await PdfFontLoader.loadArabicFonts();
    final arabicFont = pdfFonts.regular;
    final arabicBoldFont = pdfFonts.bold;
    // Keep Latin invoices independent from optional bundled TTF parsing.
    // Arabic (or Arabic text inside a Latin invoice) is still covered by
    // the known-good Tahoma assets through the base font/fallback.
    final baseFont = isArabic ? arabicFont : pw.Font.helvetica();
    final boldFont = isArabic ? arabicBoldFont : pw.Font.helveticaBold();
    final logoBytes = _logoBytes(documentProfile.logoDataBase64);

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: baseFont,
        bold: boldFont,
        fontFallback: <pw.Font>[arabicFont],
      ),
    );

    if (_isReceiptPageFormat(pageFormat)) {
      _addReceiptInvoicePage(
        pdf: pdf,
        sale: documentSale,
        profile: documentProfile,
        labels: labels,
        isArabic: isArabic,
        logoBytes: logoBytes,
        pageFormat: pageFormat,
      );
      return pdf.save();
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.fromLTRB(24, 22, 24, 22),
        textDirection: isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        header: (context) => context.pageNumber == 1
            ? _buildHeroHeader(
                sale: documentSale,
                profile: documentProfile,
                logoBytes: logoBytes,
                labels: labels,
                isArabic: isArabic,
              )
            : _buildCompactHeader(
                profile: documentProfile,
                sale: documentSale,
                labels: labels,
              ),
        footer: (context) => _buildFooter(
          context: context,
          profile: documentProfile,
          labels: labels,
        ),
        build: (_) => <pw.Widget>[
          _buildCustomerPaymentStrip(
            sale: documentSale,
            labels: labels,
            isArabic: isArabic,
          ),
          pw.SizedBox(height: 14),
          _buildItemsTable(
            sale: documentSale,
            profile: documentProfile,
            labels: labels,
            isArabic: isArabic,
          ),
          pw.SizedBox(height: 17),
          _buildBottomSection(
            sale: documentSale,
            profile: documentProfile,
            labels: labels,
            isArabic: isArabic,
          ),
        ],
      ),
    );

    return pdf.save();
  }

  Future<void> printInvoice({
    BuildContext? context,
    required Sale sale,
    required StoreProfile profile,
    Locale locale = const Locale('en'),
  }) async {
    await PrintService.printPdf(
      context: context,
      profile: profile,
      documentKey: PrintDocumentKeys.salesInvoice,
      bytesBuilder: (selection) => buildInvoicePdf(
        sale: sale,
        profile: profile,
        locale: locale,
        pageFormat: PrintService.pageFormatFor(
          selection.format,
          fallback: PdfPageFormat.a4,
        ),
      ),
      name: sale.invoiceNo,
      defaultFormat: PdfPageFormat.a4,
    );
  }

  Future<void> shareInvoice({
    required Sale sale,
    required StoreProfile profile,
    Locale locale = const Locale('en'),
  }) async {
    final bytes = await buildInvoicePdf(
      sale: sale,
      profile: profile,
      locale: locale,
    );
    await Printing.sharePdf(
      bytes: bytes,
      filename: '${sale.invoiceNo}.pdf',
    );
  }

  Future<void> printSaleReturn({
    BuildContext? context,
    required CreditNote creditNote,
    required StoreProfile profile,
    Locale locale = const Locale('en'),
  }) async {
    await PrintService.printPdf(
      context: context,
      profile: profile,
      documentKey: PrintDocumentKeys.salesReturn,
      bytesBuilder: (selection) => buildSaleReturnPdf(
        creditNote: creditNote,
        profile: profile,
        locale: locale,
        pageFormat: PrintService.pageFormatFor(
          selection.format,
          fallback: PdfPageFormat.a4,
        ),
      ),
      name: creditNote.creditNoteNo,
      defaultFormat: PdfPageFormat.a4,
    );
  }

  Future<Uint8List> buildSaleReturnPdf({
    required CreditNote creditNote,
    required StoreProfile profile,
    Locale locale = const Locale('en'),
    PdfPageFormat pageFormat = PdfPageFormat.a4,
  }) {
    final subtotal = creditNote.items.fold<double>(
      0,
      (sum, item) => sum + item.lineTotal,
    );
    final discount =
        (subtotal - creditNote.amount).clamp(0, double.infinity).toDouble();
    final sale = Sale(
      id: creditNote.id,
      invoiceNo: creditNote.creditNoteNo,
      customerName: creditNote.customerName,
      customerId: creditNote.customerId,
      date: creditNote.date,
      status: 'Issued',
      items: creditNote.items,
      discount: discount,
      invoiceCurrency: creditNote.currency,
      paymentCurrency: creditNote.currency,
      transactionAmount: creditNote.amount,
      baseAmount: creditNote.amount,
      paidAmount: creditNote.amount,
      paymentMethod: creditNote.refundMethod,
      paymentStatus: 'refunded',
      note: creditNote.note,
      postedSnapshot: creditNote.postedSnapshot,
    );
    return buildInvoicePdf(
      sale: sale,
      profile: profile,
      locale: locale,
      isReturn: true,
      pageFormat: pageFormat,
    );
  }

  bool _isReceiptPageFormat(PdfPageFormat pageFormat) {
    return pageFormat.width <= 100 * PdfPageFormat.mm;
  }

  void _addReceiptInvoicePage({
    required pw.Document pdf,
    required Sale sale,
    required StoreProfile profile,
    required _InvoicePdfLabels labels,
    required bool isArabic,
    required Uint8List? logoBytes,
    required PdfPageFormat pageFormat,
  }) {
    final hasTax = sale.hasTaxBreakdown &&
        sale.postedSnapshot != null &&
        sale.postedSnapshot!.lines.length == sale.items.length;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.fromLTRB(6 * PdfPageFormat.mm,
            6 * PdfPageFormat.mm, 6 * PdfPageFormat.mm, 5 * PdfPageFormat.mm),
        textDirection: isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        header: (context) => context.pageNumber == 1
            ? _buildReceiptHeader(
                sale: sale,
                profile: profile,
                labels: labels,
                isArabic: isArabic,
                logoBytes: logoBytes,
              )
            : _buildReceiptCompactHeader(
                sale: sale,
                profile: profile,
                labels: labels,
                isArabic: isArabic,
              ),
        footer: (context) => _buildReceiptFooter(
          context: context,
          profile: profile,
          labels: labels,
          isArabic: isArabic,
        ),
        build: (_) => <pw.Widget>[
          _buildReceiptCustomerBlock(
            sale: sale,
            labels: labels,
            isArabic: isArabic,
          ),
          pw.SizedBox(height: 8),
          _buildReceiptItems(
            sale: sale,
            profile: profile,
            labels: labels,
            isArabic: isArabic,
            hasTax: hasTax,
          ),
          pw.SizedBox(height: 8),
          _buildReceiptTotals(
            sale: sale,
            profile: profile,
            labels: labels,
            isArabic: isArabic,
          ),
        ],
      ),
    );
  }

  pw.Widget _buildReceiptHeader({
    required Sale sale,
    required StoreProfile profile,
    required _InvoicePdfLabels labels,
    required bool isArabic,
    required Uint8List? logoBytes,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _brandRule(),
        pw.SizedBox(height: 7),
        if (logoBytes != null)
          pw.Container(
            height: 38,
            alignment: pw.Alignment.center,
            child: pw.Image(
              pw.MemoryImage(logoBytes),
              fit: pw.BoxFit.contain,
            ),
          )
        else
          pw.Text(
            profile.name,
            textAlign: pw.TextAlign.center,
            maxLines: 2,
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
              color: _navy,
            ),
          ),
        pw.SizedBox(height: 4),
        pw.Text(
          labels.salesInvoice,
          textDirection: isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
            color: _gold,
          ),
        ),
        pw.SizedBox(height: 7),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 6),
          decoration: pw.BoxDecoration(
            color: _soft,
            borderRadius: pw.BorderRadius.circular(5),
          ),
          child: pw.Column(
            children: [
              _receiptMetaRow(
                labels.invoiceNo,
                sale.invoiceNo,
                isArabic: isArabic,
              ),
              pw.SizedBox(height: 3),
              _receiptMetaRow(
                labels.date,
                _formatDate(sale.date),
                isArabic: isArabic,
              ),
              pw.SizedBox(height: 3),
              _receiptMetaRow(
                labels.time,
                _formatTime(sale.date),
                isArabic: isArabic,
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 7),
      ],
    );
  }

  pw.Widget _buildReceiptCompactHeader({
    required Sale sale,
    required StoreProfile profile,
    required _InvoicePdfLabels labels,
    required bool isArabic,
  }) {
    return pw.Column(
      children: [
        pw.Text(
          profile.name,
          textAlign: pw.TextAlign.center,
          maxLines: 2,
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
            color: _navy,
          ),
        ),
        pw.SizedBox(height: 3),
        pw.Container(height: .8, color: _navy),
        pw.SizedBox(height: 5),
        _receiptMetaRow(
          labels.invoiceNo,
          sale.invoiceNo,
          isArabic: isArabic,
        ),
        pw.SizedBox(height: 5),
      ],
    );
  }

  pw.Widget _receiptMetaRow(
    String label,
    String value, {
    required bool isArabic,
  }) {
    final valueIsArabic = _containsArabic(value);
    return pw.Directionality(
      textDirection: isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              label,
              textDirection:
                  isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
              textAlign: isArabic ? pw.TextAlign.right : pw.TextAlign.left,
              style: const pw.TextStyle(fontSize: 7.2, color: _muted),
            ),
          ),
          pw.SizedBox(width: 6),
          pw.Text(
            value,
            textDirection:
                valueIsArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
            textAlign: valueIsArabic ? pw.TextAlign.right : pw.TextAlign.left,
            style: const pw.TextStyle(
              fontSize: 7.8,
              fontWeight: pw.FontWeight.bold,
              color: _ink,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildReceiptCustomerBlock({
    required Sale sale,
    required _InvoicePdfLabels labels,
    required bool isArabic,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 6),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _line, width: .6),
        borderRadius: pw.BorderRadius.circular(5),
      ),
      child: pw.Column(
        children: [
          _receiptMetaRow(
            labels.customer,
            sale.customerName,
            isArabic: isArabic,
          ),
          pw.SizedBox(height: 4),
          pw.Container(height: .5, color: _line),
          pw.SizedBox(height: 4),
          _receiptMetaRow(
            labels.paymentMethod,
            _paymentMethodLabel(sale.paymentMethod, labels),
            isArabic: isArabic,
          ),
        ],
      ),
    );
  }

  pw.Widget _buildReceiptItems({
    required Sale sale,
    required StoreProfile profile,
    required _InvoicePdfLabels labels,
    required bool isArabic,
    required bool hasTax,
  }) {
    final rows = <pw.Widget>[];
    for (var index = 0; index < sale.items.length; index += 1) {
      final item = sale.items[index];
      final quantity = item.quantity % 1 == 0
          ? item.quantity.toStringAsFixed(0)
          : item.quantity.toStringAsFixed(3);
      final unitName = item.unitName.trim();
      final taxText = hasTax
          ? _taxLineLabel(
              sale.postedSnapshot!.lines[index].taxCode,
              sale.postedSnapshot!.lines[index].taxMode,
              sale.postedSnapshot!.lines[index].taxRate,
              labels,
            )
          : '';

      rows.add(
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 5),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: _line, width: .55),
            ),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Text(
                item.productName,
                textDirection:
                    isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
                textAlign: isArabic ? pw.TextAlign.right : pw.TextAlign.left,
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: _ink,
                  lineSpacing: 1.15,
                ),
              ),
              if (unitName.isNotEmpty) ...[
                pw.SizedBox(height: 1),
                pw.Text(
                  unitName,
                  textDirection:
                      isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
                  textAlign: isArabic ? pw.TextAlign.right : pw.TextAlign.left,
                  style: const pw.TextStyle(fontSize: 6.8, color: _muted),
                ),
              ],
              pw.SizedBox(height: 3),
              pw.Directionality(
                textDirection: pw.TextDirection.ltr,
                child: pw.Row(
                  children: [
                    pw.Expanded(
                      child: pw.Text(
                        '$quantity × ${_formatMoney(item.unitPrice, profile)}',
                        style: const pw.TextStyle(
                          fontSize: 7.8,
                          color: _muted,
                        ),
                      ),
                    ),
                    pw.SizedBox(width: 4),
                    pw.Text(
                      _formatMoney(item.lineTotal, profile),
                      textAlign: pw.TextAlign.right,
                      style: pw.TextStyle(
                        fontSize: 8.4,
                        fontWeight: pw.FontWeight.bold,
                        color: _ink,
                      ),
                    ),
                  ],
                ),
              ),
              if (taxText.isNotEmpty) ...[
                pw.SizedBox(height: 2),
                pw.Directionality(
                  textDirection: pw.TextDirection.ltr,
                  child: pw.Row(
                    children: [
                      pw.Expanded(
                        child: pw.Text(
                          taxText,
                          textDirection: _containsArabic(taxText)
                              ? pw.TextDirection.rtl
                              : pw.TextDirection.ltr,
                          textAlign: pw.TextAlign.left,
                          style: const pw.TextStyle(
                            fontSize: 6.7,
                            color: _muted,
                          ),
                        ),
                      ),
                      pw.SizedBox(width: 4),
                      pw.Text(
                        labels.tax,
                        textDirection: isArabic
                            ? pw.TextDirection.rtl
                            : pw.TextDirection.ltr,
                        textAlign: pw.TextAlign.right,
                        style: const pw.TextStyle(
                          fontSize: 6.7,
                          color: _muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(
          labels.item,
          textDirection: isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
          textAlign: isArabic ? pw.TextAlign.right : pw.TextAlign.left,
          style: pw.TextStyle(
            fontSize: 8.5,
            fontWeight: pw.FontWeight.bold,
            color: _navy,
          ),
        ),
        pw.SizedBox(height: 2),
        ...rows,
      ],
    );
  }

  pw.Widget _buildReceiptTotals({
    required Sale sale,
    required StoreProfile profile,
    required _InvoicePdfLabels labels,
    required bool isArabic,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _receiptTotalsLine(
          labels.subtotal,
          _formatMoney(sale.subtotal, profile),
          isArabic: isArabic,
        ),
        if (sale.discount > 0) ...[
          pw.SizedBox(height: 3),
          _receiptTotalsLine(
            labels.discount,
            _formatMoney(sale.discount, profile),
            isArabic: isArabic,
          ),
        ],
        if (sale.hasTaxBreakdown) ...[
          pw.SizedBox(height: 3),
          _receiptTotalsLine(
            labels.netAmount,
            _formatMoney(sale.taxableAmount, profile),
            isArabic: isArabic,
          ),
          pw.SizedBox(height: 3),
          _receiptTotalsLine(
            labels.vat,
            _formatMoney(sale.taxAmount, profile),
            isArabic: isArabic,
          ),
        ],
        pw.SizedBox(height: 6),
        pw.Container(height: .7, color: _line),
        pw.SizedBox(height: 6),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: pw.BoxDecoration(
            color: _navy,
            borderRadius: pw.BorderRadius.circular(3),
          ),
          child: pw.Directionality(
            textDirection: pw.TextDirection.ltr,
            child: pw.Row(
              children: [
                pw.Container(width: 3, height: 20, color: _gold),
                pw.SizedBox(width: 6),
                pw.Expanded(
                  child: pw.Text(
                    _formatMoney(sale.total, profile),
                    style: pw.TextStyle(
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                    ),
                  ),
                ),
                pw.SizedBox(width: 5),
                pw.Text(
                  labels.total,
                  textDirection:
                      isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
                  textAlign: pw.TextAlign.right,
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (sale.note.trim().isNotEmpty) ...[
          pw.SizedBox(height: 6),
          pw.Text(
            sale.note.trim(),
            textDirection:
                isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
            textAlign: isArabic ? pw.TextAlign.right : pw.TextAlign.left,
            style: const pw.TextStyle(fontSize: 7, color: _muted),
          ),
        ],
      ],
    );
  }

  pw.Widget _receiptTotalsLine(
    String label,
    String value, {
    required bool isArabic,
  }) {
    return pw.Directionality(
      textDirection: pw.TextDirection.ltr,
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              value,
              style: const pw.TextStyle(fontSize: 8.2, color: _ink),
            ),
          ),
          pw.SizedBox(width: 5),
          pw.Text(
            label,
            textDirection:
                isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
            textAlign: pw.TextAlign.right,
            style: const pw.TextStyle(fontSize: 7.8, color: _ink),
          ),
        ],
      ),
    );
  }
}
