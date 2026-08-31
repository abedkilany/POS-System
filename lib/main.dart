import 'dart:async';

import 'package:flutter/material.dart';

import 'app.dart';
import 'core/services/local_database_service.dart';
import 'core/services/account_auth_service.dart';
import 'core/services/startup_timing_service.dart';

Future<void> main() async {
  StartupTimingService.event('main_start');
  WidgetsFlutterBinding.ensureInitialized();
  await LocalDatabaseService.initializeSecureStorage();
  unawaited(StartupTimingService.measure(
    'local_database.initialize',
    () async {
      await LocalDatabaseService.initialize();
      await AccountAuthCache.migrateLegacySecrets();
    },
    category: 'bootstrap',
  ));
  StartupTimingService.event('runApp_called');
  runApp(const VentioApp());
}
