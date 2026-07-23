import 'dart:async';

import 'package:flutter/material.dart';

import 'app.dart';
import 'core/services/local_database_service.dart';
import 'core/services/startup_timing_service.dart';

Future<void> main() async {
  StartupTimingService.event('main_start');
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(StartupTimingService.measure(
    'local_database.initialize',
    LocalDatabaseService.initialize,
    category: 'bootstrap',
  ));
  StartupTimingService.event('runApp_called');
  runApp(const VentioApp());
}
