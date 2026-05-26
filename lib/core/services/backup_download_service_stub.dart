import 'dart:io';

import 'package:file_picker/file_picker.dart';

Future<void> downloadTextFile({
  required String filename,
  required String content,
}) async {
  final savedPath = await FilePicker.platform.saveFile(
    dialogTitle: filename.toLowerCase().contains('recovery') ? 'Save recovery file' : 'Save backup file',
    fileName: filename,
    type: FileType.custom,
    allowedExtensions: const ['json'],
  );

  if (savedPath == null) {
    throw StateError('File save was cancelled.');
  }

  await File(savedPath).writeAsString(content);
}
