import 'dart:io';

import 'package:file_picker/file_picker.dart';

Future<void> downloadTextFile({
  required String filename,
  required String content,
}) async {
  final savedPath = await FilePicker.platform.saveFile(
    dialogTitle: 'Save backup file',
    fileName: filename,
    type: FileType.custom,
    allowedExtensions: const ['json'],
  );

  if (savedPath == null) {
    throw StateError('Backup save was cancelled.');
  }

  await File(savedPath).writeAsString(content);
}
