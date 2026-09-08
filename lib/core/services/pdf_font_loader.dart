import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;

import 'pdf_system_font_loader_stub.dart'
    if (dart.library.io) 'pdf_system_font_loader_io.dart';

class PdfFontPair {
  const PdfFontPair({required this.regular, required this.bold});

  final pw.Font regular;
  final pw.Font bold;
}

/// Loads the Arabic-capable fonts used by Ventio PDFs.
///
/// Some older Ventio packages contain damaged Tahoma assets.  The PDF package
/// can fail while parsing those files before the native print dialog is even
/// opened.  We therefore validate the bundled font bytes first and, on native
/// platforms, fall back to a known system font pair when the bundle is missing
/// or corrupt.
class PdfFontLoader {
  static ByteData? _cachedRegularBytes;
  static ByteData? _cachedBoldBytes;

  static Future<PdfFontPair> loadArabicFonts() async {
    final cachedRegular = _cachedRegularBytes;
    final cachedBold = _cachedBoldBytes;
    if (cachedRegular != null && cachedBold != null) {
      return PdfFontPair(
        regular: pw.Font.ttf(cachedRegular),
        bold: pw.Font.ttf(cachedBold),
      );
    }

    final bundled = await _loadBundledTahoma();
    if (bundled != null) {
      _cachedRegularBytes = bundled[0];
      _cachedBoldBytes = bundled[1];
      return PdfFontPair(
        regular: pw.Font.ttf(bundled[0]),
        bold: pw.Font.ttf(bundled[1]),
      );
    }

    final systemFonts = await loadSystemPdfFontPairBytes();
    if (systemFonts != null &&
        systemFonts.length >= 2 &&
        _looksLikeUsableSfnt(systemFonts[0]) &&
        _looksLikeUsableSfnt(systemFonts[1])) {
      _cachedRegularBytes = systemFonts[0];
      _cachedBoldBytes = systemFonts[1];
      return PdfFontPair(
        regular: pw.Font.ttf(systemFonts[0]),
        bold: pw.Font.ttf(systemFonts[1]),
      );
    }

    throw StateError('PDF_FONT_UNAVAILABLE_OR_CORRUPT');
  }

  static Future<List<ByteData>?> _loadBundledTahoma() async {
    try {
      final regular = await rootBundle.load('assets/fonts/Tahoma.ttf');
      final bold = await rootBundle.load('assets/fonts/Tahoma-Bold.ttf');
      if (_looksLikeUsableSfnt(regular) && _looksLikeUsableSfnt(bold)) {
        return <ByteData>[regular, bold];
      }
    } catch (_) {
      // Fall through to the native system-font fallback.
    }
    return null;
  }

  /// Lightweight structural validation that catches the corrupted font files
  /// found in older Ventio asset bundles without depending on the PDF parser.
  static bool _looksLikeUsableSfnt(ByteData data) {
    try {
      final length = data.lengthInBytes;
      if (length < 12) return false;

      final signature = data.getUint32(0, Endian.big);
      const trueType = 0x00010000;
      const openType = 0x4F54544F; // OTTO
      if (signature != trueType && signature != openType) return false;

      final tableCount = data.getUint16(4, Endian.big);
      if (tableCount <= 0 || tableCount > 128) return false;
      final directoryEnd = 12 + (tableCount * 16);
      if (directoryEnd > length) return false;

      int? cmapOffset;
      int? cmapLength;
      var hasHead = false;

      for (var index = 0; index < tableCount; index++) {
        final recordOffset = 12 + (index * 16);
        final tag = String.fromCharCodes(<int>[
          data.getUint8(recordOffset),
          data.getUint8(recordOffset + 1),
          data.getUint8(recordOffset + 2),
          data.getUint8(recordOffset + 3),
        ]);
        final offset = data.getUint32(recordOffset + 8, Endian.big);
        final tableLength = data.getUint32(recordOffset + 12, Endian.big);

        if (offset > length || tableLength > length - offset) return false;
        if (tag == 'head') hasHead = true;
        if (tag == 'cmap') {
          cmapOffset = offset;
          cmapLength = tableLength;
        }
      }

      if (!hasHead || cmapOffset == null || cmapLength == null) return false;
      if (cmapLength < 4 || cmapOffset + 4 > length) return false;

      // A valid cmap starts with version 0 followed by the subtable count.
      final cmapVersion = data.getUint16(cmapOffset, Endian.big);
      final cmapTables = data.getUint16(cmapOffset + 2, Endian.big);
      if (cmapVersion != 0 || cmapTables <= 0 || cmapTables > 256) return false;
      if (4 + (cmapTables * 8) > cmapLength) return false;

      return true;
    } catch (_) {
      return false;
    }
  }
}
