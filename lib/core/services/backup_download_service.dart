import 'backup_download_service_stub.dart'
    if (dart.library.html) 'backup_download_service_web.dart' as impl;

Future<void> downloadTextFile({
  required String filename,
  required String content,
  String? dialogTitle,
  String? cancelMessage,
}) {
  return impl.downloadTextFile(
      filename: filename,
      content: content,
      dialogTitle: dialogTitle,
      cancelMessage: cancelMessage);
}

Future<void> downloadBinaryFile({
  required String filename,
  required List<int> bytes,
  String? dialogTitle,
  String? cancelMessage,
}) {
  return impl.downloadBinaryFile(
      filename: filename,
      bytes: bytes,
      dialogTitle: dialogTitle,
      cancelMessage: cancelMessage);
}
