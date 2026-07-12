import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ventio/app.dart';
import 'package:ventio/core/localization/app_localizations.dart';
import 'package:ventio/core/repositories/auth_repository.dart';
import 'package:ventio/core/services/local_database_service.dart';
import 'package:ventio/core/services/password_hashing.dart';
import 'package:ventio/core/theme/app_theme.dart';
import 'package:ventio/data/app_store.dart';
import 'package:ventio/models/app_user.dart';
import 'package:ventio/models/user_role.dart';

Widget _testApp({required AppStore store, Locale locale = const Locale('en')}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.lightTheme,
    locale: locale,
    supportedLocales: const [Locale('en'), Locale('ar')],
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: MainShell(
      store: store,
      onLocaleChanged: (_) {},
      onThemeModeChanged: (_) {},
      themeMode: ThemeMode.system,
    ),
  );
}

Future<AppStore> _readyStore() async {
  LocalDatabaseService.useInMemoryStoreForTesting();
  final store = AppStore();
  await store.initialize();
  final role = UserRole(
    id: 'shell_admin',
    name: 'Shell Admin',
    permissions: Set<String>.from(AppPermission.all),
  );
  final passwordHash = await PasswordHashing.hashPassword('AdminPass123');
  final user = AppUser(
    id: 'shell_admin_user',
    fullName: 'Shell Admin',
    username: 'shell_admin',
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
    'shell_admin',
    'AdminPass123',
    remember: true,
  );
  if (!loggedIn) {
    throw StateError('Failed to prepare the shell integration test user.');
  }
  return store;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('App shell integration flows', () {
    testWidgets('compact layout opens drawer and navigates to inventory',
        (tester) async {
      await binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() async => binding.setSurfaceSize(null));
      await tester.pumpWidget(_testApp(store: await _readyStore()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Ventio • Dashboard'), findsOneWidget);

      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Inventory').last);
      await tester.pumpAndSettle();

      expect(find.textContaining('Ventio • Inventory'), findsOneWidget);
    });

    testWidgets('Arabic locale uses RTL directionality for the shell',
        (tester) async {
      await binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() async => binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _testApp(store: await _readyStore(), locale: const Locale('ar')),
      );
      await tester.pumpAndSettle();

      final directionality =
          tester.widget<Directionality>(find.byType(Directionality).first);
      expect(directionality.textDirection, TextDirection.rtl);
    });
  });
}
