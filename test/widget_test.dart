import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ventio/app.dart';
import 'package:ventio/core/services/local_database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('VentioApp builds without crashing', (tester) async {
    SharedPreferences.setMockInitialValues({});
    LocalDatabaseService.useInMemoryStoreForTesting(const <String, String>{});

    await tester.pumpWidget(const VentioApp());
    await tester.pump();

    expect(find.byType(VentioApp), findsOneWidget);
  });
}
