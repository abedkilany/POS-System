import 'backup_download_service_stub.dart'
    if (dart.library.html) 'backup_download_service_web.dart' as impl;

Future<void> downloadTextFile({
  required String filename,
  required String content,
}) {
  return impl.downloadTextFile(filename: filename, content: content);
}
