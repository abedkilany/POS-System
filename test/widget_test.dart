import 'package:flutter_test/flutter_test.dart';

import 'package:store_manager_pro/app.dart';
import 'package:store_manager_pro/core/services/local_database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('StoreManagerApp starts without crashing', (WidgetTester tester) async {
    await LocalDatabaseService.initialize();
    await tester.pumpWidget(const StoreManagerApp());
    await tester.pump();

    expect(find.byType(StoreManagerApp), findsOneWidget);
  });
}
