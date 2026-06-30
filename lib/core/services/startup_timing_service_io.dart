import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<String?> saveTextReport(String content) async {
  final support = await getApplicationSupportDirectory();
  final directory = Directory(p.join(support.path, 'startup_reports'));
  await directory.create(recursive: true);
  final timestamp = DateTime.now()
      .toUtc()
      .toIso8601String()
      .replaceAll(RegExp(r'[^0-9]'), '')
      .substring(0, 14);
  final file = File(p.join(directory.path, 'startup_timing_$timestamp.txt'));
  await file.writeAsString(content);
  return file.path;
}
