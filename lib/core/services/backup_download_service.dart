import 'backup_download_service_stub.dart'
    if (dart.library.html) 'backup_download_service_web.dart' as impl;

Future<void> downloadTextFile({
  required String filename,
  required String content,
  String? dialogTitle,
  String? cancelMessage,
}) {
  return impl.downloadTextFile(filename: filename, content: content, dialogTitle: dialogTitle, cancelMessage: cancelMessage);
}
