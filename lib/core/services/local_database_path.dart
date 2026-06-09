import 'local_database_path_stub.dart'
    if (dart.library.io) 'local_database_path_io.dart';

Future<String> getVentioHiveDirectoryPath() => getVentioHiveDirectoryPathImpl();

Future<bool> hasLegacyVentioHiveDatabase() => hasLegacyVentioHiveDatabaseImpl();

Future<void> retireLegacyVentioHiveFilesIfPresent() => retireLegacyVentioHiveFilesIfPresentImpl();
