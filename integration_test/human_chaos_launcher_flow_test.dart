import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ventio/core/localization/app_localizations.dart';
import 'package:ventio/core/repositories/auth_repository.dart';
import 'package:ventio/core/services/local_database_service.dart';
import 'package:ventio/core/services/password_hashing.dart';
import 'package:ventio/core/theme/app_theme.dart';
import 'package:ventio/data/app_store.dart';
import 'package:ventio/models/app_user.dart';
import 'package:ventio/models/user_role.dart';
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
  LocalDatabaseService.clearInMemoryStoreForTesting();
  LocalDatabaseService.useInMemoryStoreForTesting();
  final store = AppStore();
  await store.initialize();
  final role = UserRole(
    id: 'chaos_admin',
    name: 'Chaos Admin',
    permissions: Set<String>.from(AppPermission.all),
  );
  final passwordHash = await PasswordHashing.hashPassword('AdminPass123');
  final user = AppUser(
    id: 'chaos_admin_user',
    fullName: 'Chaos Admin',
    username: 'chaos_admin',
    passwordHash: passwordHash,
    roleId: role.id,
  );
  await LocalDatabaseService.replaceBusinessEntityJsonListImmediate(
    'roles_v1',
    [role.toJson()],
    sortIndices: const [0],
  );
  await LocalDatabaseService.replaceBusinessEntityJsonListImmediate(
    'users_v1',
    [user.toJson()],
    sortIndices: const [0],
  );
  await store.refreshAfterDatabaseChange('roles_v1');
  await store.refreshAfterDatabaseChange('users_v1');
  final loggedIn = await AuthRepository.login(
    store,
    'chaos_admin',
    'AdminPass123',
    remember: true,
  );
  if (!loggedIn) {
    throw StateError('Failed to prepare the human chaos integration user.');
  }
  await store.setStressLabEnabled(true);
  return store;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('all-scenarios launcher is a single real UI button',
      (tester) async {
    await binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() async => binding.setSurfaceSize(null));
    final store = await _readyStore();
    addTearDown(() async {
      await store.prepareForShutdown();
      store.dispose();
      LocalDatabaseService.clearInMemoryStoreForTesting();
    });
    await tester.pumpWidget(_testApp(store));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
        find.byKey(const ValueKey('RealUserScenarioButton')), findsOneWidget);
    expect(find.text('Run all scenarios'), findsOneWidget);

    // The old mode/iterations/seed chooser was intentionally removed: one
    // click now launches the complete STANDARD + HUMAN CHAOS sequence.
    expect(find.text('New employee & chaos lab'), findsNothing);
    expect(find.text('Chaos episodes'), findsNothing);
    expect(find.text('Start chaos'), findsNothing);
  });
}
