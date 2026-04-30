import 'package:flutter/material.dart';

import 'app.dart';
import 'core/services/local_database_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalDatabaseService.initialize();
  runApp(const StoreManagerApp());
}
