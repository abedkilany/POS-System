import 'dart:typed_data';

import 'sql_result_download_service_stub.dart'
    if (dart.library.html) 'sql_result_download_service_web.dart' as impl;

Future<void> downloadSqlResultFile({
  required String filename,
  required Uint8List bytes,
  required String dialogTitle,
  required List<String> allowedExtensions,
}) {
  return impl.downloadSqlResultFile(
    filename: filename,
    bytes: bytes,
    dialogTitle: dialogTitle,
    allowedExtensions: allowedExtensions,
  );
}
