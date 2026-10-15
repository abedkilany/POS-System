part of 'google_drive_backup_service.dart';

List<int> _buildZipBytesInIsolate(Map<String, String> input) {
  final backupBytes = utf8.encode(input['backupJson']!);
  final generatedAt = DateTime.parse(input['generatedAt']!);
  final manifest = jsonEncode(<String, Object?>{
    'app': 'Ventio',
    'type': 'google-drive-backup',
    'reason': input['reason']!,
    'generatedAt': generatedAt.toIso8601String(),
    'content': 'backup.json',
    'encrypted': true,
    'cipher': 'aes-256-gcm',
    'keySource': 'store-recovery-key',
  });
  final manifestBytes = utf8.encode(manifest);
  final archive = Archive()
    ..addFile(ArchiveFile('backup.json', backupBytes.length, backupBytes))
    ..addFile(
        ArchiveFile('manifest.json', manifestBytes.length, manifestBytes));
  return ZipEncoder().encode(archive);
}
