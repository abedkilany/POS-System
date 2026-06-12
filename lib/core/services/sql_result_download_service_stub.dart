import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

Future<void> downloadSqlResultFile({
  required String filename,
  required Uint8List bytes,
  required String dialogTitle,
  required List<String> allowedExtensions,
}) async {
  final savedPath = await FilePicker.platform.saveFile(
    dialogTitle: dialogTitle,
    fileName: filename,
    type: FileType.custom,
    allowedExtensions: allowedExtensions,
  );

  if (savedPath == null) {
    throw StateError('Export was cancelled.');
  }

  await File(savedPath).writeAsBytes(bytes, flush: true);
}
