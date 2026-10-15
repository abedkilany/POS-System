part of 'invoice_pdf_service.dart';

extension _InvoicePdfServicePart2 on _InvoicePdfServiceImplementation {
  pw.Widget _buildReceiptFooter({
    required pw.Context context,
    required StoreProfile profile,
    required _InvoicePdfLabels labels,
    required bool isArabic,
  }) {
    final contact = <String>[
      if (profile.phone.trim().isNotEmpty) profile.phone.trim(),
      if (profile.address.trim().isNotEmpty) profile.address.trim(),
    ].join(' • ');
    return pw.Column(
      children: [
        pw.SizedBox(height: 5),
        pw.Container(height: .7, color: _line),
        pw.SizedBox(height: 4),
        pw.Text(
          labels.thankYou,
          textDirection: isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
          textAlign: pw.TextAlign.center,
          style: const pw.TextStyle(fontSize: 7, color: _muted),
        ),
        if (contact.isNotEmpty) ...[
          pw.SizedBox(height: 2),
          pw.Text(
            contact,
            textDirection: _containsArabic(contact)
                ? pw.TextDirection.rtl
                : pw.TextDirection.ltr,
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(fontSize: 6.2, color: _muted),
          ),
        ],
        pw.SizedBox(height: 2),
        pw.Text(
          '${context.pageNumber} / ${context.pagesCount}',
          textDirection: pw.TextDirection.ltr,
          textAlign: pw.TextAlign.center,
          style: const pw.TextStyle(fontSize: 5.8, color: _muted),
        ),
      ],
    );
  }

  pw.Widget _buildHeroHeader({
    required Sale sale,
    required StoreProfile profile,
    required Uint8List? logoBytes,
    required _InvoicePdfLabels labels,
    required bool isArabic,
  }) {
    return pw.Column(
      children: [
        _brandRule(),
        pw.SizedBox(height: 16),
        pw.Directionality(
          textDirection: pw.TextDirection.ltr,
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                flex: 31,
                child: _invoiceInfoBlock(
                  sale: sale,
                  labels: labels,
                  isArabic: isArabic,
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                flex: 38,
                child: _centerBrandBlock(
                  profile: profile,
                  logoBytes: logoBytes,
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                flex: 31,
                child: _companyInfoBlock(
                  profile: profile,
                  isArabic: isArabic,
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 15),
      ],
    );
  }

  pw.Widget _brandRule() {
    return pw.Directionality(
      textDirection: pw.TextDirection.ltr,
      child: pw.Row(
        children: [
          pw.Container(
              width: 4,
              height: 4,
              decoration: const pw.BoxDecoration(
                  color: _gold, shape: pw.BoxShape.circle)),
          pw.SizedBox(width: 5),
          pw.Expanded(flex: 42, child: pw.Container(height: 2.2, color: _navy)),
          pw.Expanded(flex: 18, child: pw.Container(height: 2.2, color: _gold)),
          pw.Expanded(flex: 42, child: pw.Container(height: 2.2, color: _navy)),
          pw.SizedBox(width: 5),
          pw.Container(
              width: 4,
              height: 4,
              decoration: const pw.BoxDecoration(
                  color: _gold, shape: pw.BoxShape.circle)),
        ],
      ),
    );
  }

  pw.Widget _invoiceInfoBlock({
    required Sale sale,
    required _InvoicePdfLabels labels,
    required bool isArabic,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          labels.salesInvoice,
          textDirection: isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
          style: pw.TextStyle(
            color: _navy,
            fontSize: 17,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          'SALES INVOICE',
          textDirection: pw.TextDirection.ltr,
          style: const pw.TextStyle(
            color: _gold,
            fontSize: 7.2,
            letterSpacing: 1.8,
          ),
        ),
        pw.SizedBox(height: 14),
        _metaItem(labels.invoiceNo, sale.invoiceNo, isArabic: isArabic),
        pw.SizedBox(height: 8),
        _metaItem(labels.date, _formatDate(sale.date), isArabic: isArabic),
        pw.SizedBox(height: 8),
        _metaItem(labels.time, _formatTime(sale.date), isArabic: isArabic),
      ],
    );
  }

  pw.Widget _metaItem(String label, String value, {required bool isArabic}) {
    return pw.Directionality(
      textDirection: pw.TextDirection.ltr,
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  label,
                  textDirection:
                      isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
                  textAlign: isArabic ? pw.TextAlign.right : pw.TextAlign.left,
                  style: const pw.TextStyle(fontSize: 6.8, color: _muted),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  value,
                  textDirection: pw.TextDirection.ltr,
                  style: pw.TextStyle(
                    fontSize: 8.2,
                    fontWeight: pw.FontWeight.bold,
                    color: _ink,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _centerBrandBlock({
    required StoreProfile profile,
    required Uint8List? logoBytes,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        if (logoBytes != null)
          pw.Container(
            height: 108,
            alignment: pw.Alignment.center,
            child: pw.Image(
              pw.MemoryImage(logoBytes),
              fit: pw.BoxFit.contain,
            ),
          )
        else
          pw.Container(
            height: 74,
            alignment: pw.Alignment.center,
            child: pw.Text(
              profile.name,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: 22,
                fontWeight: pw.FontWeight.bold,
                color: _navy,
              ),
            ),
          ),
      ],
    );
  }

  pw.Widget _companyInfoBlock({
    required StoreProfile profile,
    required bool isArabic,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Text(
          profile.name,
          textAlign: pw.TextAlign.right,
          style: pw.TextStyle(
            fontSize: 13.5,
            fontWeight: pw.FontWeight.bold,
            color: _navy,
          ),
        ),
        pw.SizedBox(height: 6),
        if (profile.phone.trim().isNotEmpty)
          _companyLine(
            label: profile.phone.trim(),
            isArabic: false,
          ),
        if (profile.address.trim().isNotEmpty) ...[
          pw.SizedBox(height: 6),
          _companyLine(
            label: profile.address.trim(),
            isArabic: isArabic,
          ),
        ],
        if (profile.vatNumber.trim().isNotEmpty ||
            profile.taxRegistrationNumber.trim().isNotEmpty) ...[
          pw.SizedBox(height: 6),
          _companyLine(
            label:
                'VAT: ${profile.vatNumber.trim().isNotEmpty ? profile.vatNumber.trim() : profile.taxRegistrationNumber.trim()}',
            isArabic: false,
          ),
        ],
      ],
    );
  }

  pw.Widget _companyLine({
    required String label,
    required bool isArabic,
  }) {
    return pw.Directionality(
      textDirection: pw.TextDirection.rtl,
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 5,
            height: 5,
            margin: const pw.EdgeInsets.only(top: 3),
            decoration:
                const pw.BoxDecoration(color: _gold, shape: pw.BoxShape.circle),
          ),
          pw.SizedBox(width: 6),
          pw.Expanded(
            child: pw.Text(
              label,
              textDirection:
                  isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
              textAlign: pw.TextAlign.right,
              style: const pw.TextStyle(
                fontSize: 7.4,
                color: _ink,
                lineSpacing: 1.7,
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildCompactHeader({
    required StoreProfile profile,
    required Sale sale,
    required _InvoicePdfLabels labels,
  }) {
    return pw.Column(
      children: [
        pw.Row(
          children: [
            pw.Expanded(
              child: pw.Text(
                profile.name,
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: _navy,
                ),
              ),
            ),
            pw.Text(
              '${labels.invoiceNo}: ${sale.invoiceNo}',
              textDirection:
                  labels.isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
              style: const pw.TextStyle(fontSize: 7, color: _muted),
            ),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Container(height: 1, color: _navy),
        pw.SizedBox(height: 9),
      ],
    );
  }

  pw.Widget _buildCustomerPaymentStrip({
    required Sale sale,
    required _InvoicePdfLabels labels,
    required bool isArabic,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 15, vertical: 8),
      decoration: pw.BoxDecoration(
        color: _soft,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Directionality(
        textDirection: pw.TextDirection.ltr,
        child: pw.Row(
          children: [
            pw.Expanded(
              child: _stripInfo(
                label: labels.customer,
                value: sale.customerName,
                alignRight: false,
                valueDirection:
                    isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
              ),
            ),
            pw.Container(width: .7, height: 26, color: _line),
            pw.Expanded(
              child: _stripInfo(
                label: labels.paymentMethod,
                value: _paymentMethodLabel(sale.paymentMethod, labels),
                alignRight: true,
                valueDirection:
                    isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
              ),
            ),
          ],
        ),
      ),
    );
  }

  pw.Widget _stripInfo({
    required String label,
    required String value,
    required bool alignRight,
    required pw.TextDirection valueDirection,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10),
      child: pw.Column(
        crossAxisAlignment: alignRight
            ? pw.CrossAxisAlignment.end
            : pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            textDirection: valueDirection,
            textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
            style: pw.TextStyle(
              fontSize: 7.6,
              fontWeight: pw.FontWeight.bold,
              color: _navy,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            value,
            textDirection: valueDirection,
            textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
            style: pw.TextStyle(
              fontSize: 10.2,
              fontWeight: pw.FontWeight.bold,
              color: _ink,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildItemsTable({
    required Sale sale,
    required StoreProfile profile,
    required _InvoicePdfLabels labels,
    required bool isArabic,
  }) {
    final hasTax = sale.hasTaxBreakdown &&
        sale.postedSnapshot != null &&
        sale.postedSnapshot!.lines.length == sale.items.length;
    final headers = <String>[
      labels.item,
      labels.qty,
      labels.unitPrice,
      if (hasTax) labels.tax,
      labels.lineTotal,
    ];

    final data = <List<String>>[];
    for (var index = 0; index < sale.items.length; index += 1) {
      final item = sale.items[index];
      final quantity = item.quantity % 1 == 0
          ? item.quantity.toStringAsFixed(0)
          : item.quantity.toStringAsFixed(3);
      final row = <String>[
        item.productName,
        quantity,
        _formatMoney(item.unitPrice, profile),
      ];
      if (hasTax) {
        final line = sale.postedSnapshot!.lines[index];
        row.add(
            _taxLineLabel(line.taxCode, line.taxMode, line.taxRate, labels));
      }
      row.add(_formatMoney(item.lineTotal, profile));
      data.add(row);
    }

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: data,
      headerCount: 1,
      border: const pw.TableBorder(
        left: pw.BorderSide(color: _line, width: .55),
        right: pw.BorderSide(color: _line, width: .55),
        bottom: pw.BorderSide(color: _line, width: .55),
        horizontalInside: pw.BorderSide(color: _line, width: .5),
        verticalInside: pw.BorderSide(color: _line, width: .45),
      ),
      headerDecoration: pw.BoxDecoration(
        color: _navy,
        borderRadius: pw.BorderRadius.circular(4),
      ),
      oddRowDecoration: const pw.BoxDecoration(color: PdfColors.white),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 11),
      headerStyle: pw.TextStyle(
        color: PdfColors.white,
        fontSize: 8.1,
        fontWeight: pw.FontWeight.bold,
      ),
      cellStyle: const pw.TextStyle(fontSize: 8.2, color: _ink),
      columnWidths: hasTax
          ? const <int, pw.TableColumnWidth>{
              0: pw.FlexColumnWidth(4.5),
              1: pw.FlexColumnWidth(1.15),
              2: pw.FlexColumnWidth(1.8),
              3: pw.FlexColumnWidth(1.45),
              4: pw.FlexColumnWidth(1.8),
            }
          : const <int, pw.TableColumnWidth>{
              0: pw.FlexColumnWidth(5.0),
              1: pw.FlexColumnWidth(1.25),
              2: pw.FlexColumnWidth(2.0),
              3: pw.FlexColumnWidth(2.0),
            },
      headerAlignment: pw.Alignment.center,
      cellAlignments: <int, pw.Alignment>{
        0: isArabic ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
        for (var index = 1; index < headers.length; index += 1)
          index: pw.Alignment.center,
      },
    );
  }

  String _taxLineLabel(
    String code,
    String mode,
    double rate,
    _InvoicePdfLabels labels,
  ) {
    final displayCode =
        labels.isArabic && code.trim().toUpperCase() == 'VAT' ? '' : code;
    if (mode == 'exempt') {
      return displayCode.isEmpty
          ? labels.exempt
          : '$displayCode ${labels.exempt}';
    }
    if (mode == 'out_of_scope') {
      return displayCode.isEmpty
          ? labels.outOfScope
          : '$displayCode ${labels.outOfScope}';
    }
    if (mode == 'zero_rated') {
      return displayCode.isEmpty ? '0%' : '$displayCode 0%';
    }
    if (mode == 'standard') {
      final value = rate == rate.roundToDouble()
          ? rate.toStringAsFixed(0)
          : rate.toStringAsFixed(2);
      return displayCode.isEmpty ? '$value%' : '$displayCode $value%';
    }
    return '-';
  }

  pw.Widget _buildBottomSection({
    required Sale sale,
    required StoreProfile profile,
    required _InvoicePdfLabels labels,
    required bool isArabic,
  }) {
    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Container(
        width: 330,
        child: pw.Column(
          children: [
            _totalsLine(
              label: labels.subtotal,
              value: _formatMoney(sale.subtotal, profile),
              isArabic: isArabic,
            ),
            pw.SizedBox(height: 7),
            _totalsLine(
              label: labels.discount,
              value: _formatMoney(sale.discount, profile),
              isArabic: isArabic,
            ),
            if (sale.hasTaxBreakdown) ...[
              pw.SizedBox(height: 7),
              _totalsLine(
                label: labels.netAmount,
                value: _formatMoney(sale.taxableAmount, profile),
                isArabic: isArabic,
              ),
              pw.SizedBox(height: 7),
              _totalsLine(
                label: labels.vat,
                value: _formatMoney(sale.taxAmount, profile),
                isArabic: isArabic,
              ),
            ],
            pw.SizedBox(height: 9),
            pw.Container(height: .8, color: _line),
            pw.SizedBox(height: 9),
            pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: pw.BoxDecoration(
                color: _navy,
                border: const pw.Border(
                  right: pw.BorderSide(color: _gold, width: 5),
                ),
              ),
              child: pw.Directionality(
                textDirection: pw.TextDirection.ltr,
                child: pw.Row(
                  children: [
                    pw.Text(
                      _formatMoney(sale.total, profile),
                      textDirection: pw.TextDirection.ltr,
                      style: pw.TextStyle(
                        fontSize: 17.5,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                      ),
                    ),
                    pw.Spacer(),
                    pw.Text(
                      labels.total,
                      textDirection: isArabic
                          ? pw.TextDirection.rtl
                          : pw.TextDirection.ltr,
                      textAlign: pw.TextAlign.right,
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (sale.note.trim().isNotEmpty) ...[
              pw.SizedBox(height: 9),
              pw.Text(
                sale.note.trim(),
                textDirection:
                    isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
                textAlign: isArabic ? pw.TextAlign.right : pw.TextAlign.left,
                style: const pw.TextStyle(fontSize: 7, color: _muted),
              ),
            ],
          ],
        ),
      ),
    );
  }

  pw.Widget _totalsLine({
    required String label,
    required String value,
    required bool isArabic,
  }) {
    return pw.Directionality(
      textDirection: pw.TextDirection.ltr,
      child: pw.Row(
        children: [
          pw.Text(
            value,
            textDirection: pw.TextDirection.ltr,
            style: pw.TextStyle(
              fontSize: 10.2,
              fontWeight: pw.FontWeight.bold,
              color: _ink,
            ),
          ),
          pw.Spacer(),
          pw.Text(
            label,
            textDirection:
                isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
            textAlign: pw.TextAlign.right,
            style: const pw.TextStyle(fontSize: 8.2, color: _ink),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildFooter({
    required pw.Context context,
    required StoreProfile profile,
    required _InvoicePdfLabels labels,
  }) {
    final contact = <String>[
      if (profile.phone.trim().isNotEmpty) profile.phone.trim(),
      if (profile.address.trim().isNotEmpty) profile.address.trim(),
    ].join('   |   ');

    return pw.Column(
      children: [
        pw.SizedBox(height: 9),
        _brandRule(),
        pw.SizedBox(height: 7),
        pw.Directionality(
          textDirection: pw.TextDirection.ltr,
          child: pw.Row(
            children: [
              pw.Text(
                '${context.pageNumber} / ${context.pagesCount}',
                style: const pw.TextStyle(fontSize: 6, color: _muted),
              ),
              pw.Expanded(
                child: pw.Text(
                  contact.isEmpty ? profile.name : contact,
                  textDirection: _containsArabic(contact)
                      ? pw.TextDirection.rtl
                      : pw.TextDirection.ltr,
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(fontSize: 6.3, color: _muted),
                ),
              ),
              pw.SizedBox(width: 38),
            ],
          ),
        ),
      ],
    );
  }

  String _paymentMethodLabel(
    String raw,
    _InvoicePdfLabels labels,
  ) {
    final value = raw.trim().toLowerCase();
    if (value == 'cash' || value == 'نقد' || value == 'نقداً') {
      return labels.cash;
    }
    if (value == 'card' || value == 'credit card' || value == 'visa') {
      return labels.card;
    }
    if (value == 'credit' || value == 'deferred' || value == 'آجل') {
      return labels.credit;
    }
    return raw.trim().isEmpty ? labels.cash : raw.trim();
  }

  Uint8List? _logoBytes(String rawBase64) {
    final value = rawBase64.trim();
    if (value.isEmpty) return null;
    try {
      final normalized = value.startsWith('data:image/')
          ? value.substring(value.indexOf(',') + 1)
          : value;
      return base64Decode(normalized);
    } catch (_) {
      return null;
    }
  }

  bool _containsArabic(String value) {
    return RegExp(r'[\u0600-\u06FF]').hasMatch(value);
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.day)}-${two(local.month)}-${local.year}';
  }

  String _formatTime(DateTime date) {
    final local = date.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}';
  }
}
