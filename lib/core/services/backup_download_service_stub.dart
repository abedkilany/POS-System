import 'dart:io';

import 'package:file_picker/file_picker.dart';

Future<void> downloadTextFile({
  required String filename,
  required String content,
  String? dialogTitle,
  String? cancelMessage,
}) async {
  final savedPath = await FilePicker.platform.saveFile(
    dialogTitle: dialogTitle ??
        (filename.toLowerCase().contains('recovery')
            ? 'Save recovery file'
            : 'Save backup file'),
    fileName: filename,
    type: FileType.custom,
    allowedExtensions: const ['json'],
  );

  if (savedPath == null) {
    throw StateError(cancelMessage ?? 'File save was cancelled.');
  }

  await File(savedPath).writeAsString(content);
}

Future<void> downloadBinaryFile({
  required String filename,
  required List<int> bytes,
  String? dialogTitle,
  String? cancelMessage,
}) async {
  final extension =
      filename.contains('.') ? filename.split('.').last.toLowerCase() : 'vtb';
  final savedPath = await FilePicker.platform.saveFile(
    dialogTitle: dialogTitle ?? 'Save backup file',
    fileName: filename,
    type: FileType.custom,
    allowedExtensions: [extension],
  );

  if (savedPath == null) {
    throw StateError(cancelMessage ?? 'File save was cancelled.');
  }

  await File(savedPath).writeAsBytes(bytes);
}
