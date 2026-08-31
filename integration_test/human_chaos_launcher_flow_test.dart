import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ventio/core/localization/app_localizations.dart';
import 'package:ventio/core/services/local_database_service.dart';
import 'package:ventio/core/theme/app_theme.dart';
import 'package:ventio/data/app_store.dart';
import 'package:ventio/features/dev_tools/stress_lab_page.dart';

Widget _testApp(AppStore store) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.lightTheme,
    locale: const Locale('en'),
    supportedLocales: const [Locale('en'), Locale('ar')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: StressLabPage(store: store),
  );
}

Future<AppStore> _readyStore() async {
  LocalDatabaseService.useInMemoryStoreForTesting();
  final store = AppStore();
  await store.initialize();
  await store.setStressLabEnabled(true);
  return store;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('all-scenarios launcher is a single real UI button', (tester) async {
    await binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() async => binding.setSurfaceSize(null));
    await tester.pumpWidget(_testApp(await _readyStore()));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('RealUserScenarioButton')), findsOneWidget);
    expect(find.text('Run all scenarios'), findsOneWidget);

    // The old mode/iterations/seed chooser was intentionally removed: one
    // click now launches the complete STANDARD + HUMAN CHAOS sequence.
    expect(find.text('New employee & chaos lab'), findsNothing);
    expect(find.text('Chaos episodes'), findsNothing);
    expect(find.text('Start chaos'), findsNothing);
  });
}
