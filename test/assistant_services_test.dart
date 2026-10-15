import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ventio/core/services/local_database_service.dart';
import 'package:ventio/data/app_store.dart';
import 'package:ventio/features/assistant/assistant_conversation_service.dart';
import 'package:ventio/features/assistant/assistant_how_to_knowledge_service.dart';
import 'package:ventio/features/assistant/assistant_provider.dart';
import 'package:ventio/features/assistant/assistant_provider_settings_service.dart';
import 'package:ventio/features/assistant/assistant_provider_transport.dart';

const _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

Map<String, String> _hostIdentitySeed() {
  final now = DateTime.utc(2026, 1, 1).toIso8601String();
  return <String, String>{
    'app_identity_v1': jsonEncode(<String, Object?>{
      'storeId': 'ST-ASSISTANT-TEST',
      'branchId': 'BR-ASSISTANT-TEST',
      'deviceId': 'DV-ASSISTANT-TEST',
      'deviceName': 'Assistant Test Host',
      'platform': 'windows',
      'deviceRole': 'host',
      'appRole': 'store',
      'syncMode': 'localOnly',
      'createdAt': now,
      'updatedAt': now,
      'hostDeviceId': '',
      'controlPlaneTenantId': '',
      'deviceToken': 'assistant-test-device',
      'storeEpoch': 1,
      'recoveryKey': 'RK-ASSISTANT-TEST',
      'activeSyncTransport': 'local',
    }),
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Assistant provider settings and conversation safety', () {
    late AppStore store;
    late Map<String, String> secureValues;
    var secureReadCount = 0;

    setUp(() async {
      SharedPreferences.setMockInitialValues(const <String, Object>{});
      secureValues = <String, String>{};
      secureReadCount = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_secureStorageChannel, (call) async {
        final arguments = call.arguments as Map;
        final key = arguments['key'] as String;
        switch (call.method) {
          case 'read':
            secureReadCount += 1;
            return secureValues[key];
          case 'write':
            secureValues[key] = arguments['value'] as String? ?? '';
            return null;
          case 'delete':
            secureValues.remove(key);
            return null;
          case 'containsKey':
            return secureValues.containsKey(key);
          case 'readAll':
            return secureValues;
          case 'deleteAll':
            secureValues.clear();
            return null;
          default:
            return null;
        }
      });
      LocalDatabaseService.clearInMemoryStoreForTesting();
      LocalDatabaseService.useInMemoryStoreForTesting(_hostIdentitySeed());
      store = AppStore();
      await store.runtime.initialize();
      await store.security.completeInitialAdminSetup(
        fullName: 'Assistant Admin',
        username: 'assistant-admin',
        password: 'AssistantPass123',
      );
    });

    tearDown(() async {
      store.dispose();
      LocalDatabaseService.clearInMemoryStoreForTesting();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_secureStorageChannel, null);
    });

    test('stores provider credentials in secure storage and deletes them',
        () async {
      await AssistantProviderSettingsService.saveApiKey(
        store: store,
        provider: AssistantProvider.openAi,
        apiKey: '  openai-test-key  ',
      );

      expect(
        await AssistantProviderSettingsService.readApiKey(
          store: store,
          provider: AssistantProvider.openAi,
        ),
        'openai-test-key',
      );
      expect(
        await AssistantProviderSettingsService.readApiKey(
          store: store,
          provider: AssistantProvider.gemini,
        ),
        isNull,
      );

      await AssistantProviderSettingsService.deleteApiKey(
        store: store,
        provider: AssistantProvider.openAi,
      );
      expect(
        await AssistantProviderSettingsService.hasApiKey(
          store: store,
          provider: AssistantProvider.openAi,
        ),
        isFalse,
      );
    });

    test('keeps business-data consent specific to provider and revocable',
        () async {
      await AssistantProviderSettingsService.setBusinessDataConsent(
        store: store,
        provider: AssistantProvider.openAi,
        granted: true,
      );

      expect(
        await AssistantProviderSettingsService.hasBusinessDataConsent(
          store: store,
          provider: AssistantProvider.openAi,
        ),
        isTrue,
      );
      expect(
        await AssistantProviderSettingsService.hasBusinessDataConsent(
          store: store,
          provider: AssistantProvider.gemini,
        ),
        isFalse,
      );

      await AssistantProviderSettingsService.setBusinessDataConsent(
        store: store,
        provider: AssistantProvider.openAi,
        granted: false,
      );
      expect(
        await AssistantProviderSettingsService.hasBusinessDataConsent(
          store: store,
          provider: AssistantProvider.openAi,
        ),
        isFalse,
      );
    });

    test('requires consent before reading a key or contacting a provider',
        () async {
      var requestCount = 0;
      final transport = AssistantProviderTransport(
        client: MockClient((_) async {
          requestCount += 1;
          return http.Response('{}', 200);
        }),
      );
      addTearDown(transport.close);
      final service = AssistantConversationService(transport: transport);

      await expectLater(
        service.ask(
          store: store,
          provider: AssistantProvider.openAi,
          model: 'gpt-5',
          question: 'What were sales today?',
        ),
        throwsA(isA<AssistantConversationException>().having(
          (error) => error.code,
          'code',
          'business_data_consent_required',
        )),
      );

      expect(secureReadCount, 0);
      expect(requestCount, 0);
    });

    test('bounds outgoing history by turn count and character budget',
        () async {
      await AssistantProviderSettingsService.setBusinessDataConsent(
        store: store,
        provider: AssistantProvider.openAi,
        granted: true,
      );
      await AssistantProviderSettingsService.saveApiKey(
        store: store,
        provider: AssistantProvider.openAi,
        apiKey: 'assistant-test-key',
      );

      late Map<String, dynamic> turnLimitedBody;
      final turnLimitedTransport = AssistantProviderTransport(
        client: MockClient((request) async {
          turnLimitedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode(<String, Object?>{
              'output_text': 'Short answer.',
              'output': <Object?>[],
            }),
            200,
          );
        }),
      );
      addTearDown(turnLimitedTransport.close);
      final turnLimitedService = AssistantConversationService(
        transport: turnLimitedTransport,
      );
      await turnLimitedService.ask(
        store: store,
        provider: AssistantProvider.openAi,
        model: 'gpt-5',
        question: 'What is this?',
        history: List<AssistantChatTurn>.generate(
          25,
          (index) => AssistantChatTurn.user('history-$index'),
        ),
      );

      final turnLimitedInput = turnLimitedBody['input'] as List<dynamic>;
      expect(turnLimitedInput, hasLength(21));
      expect(turnLimitedInput.first['content'], 'history-5');
      expect(turnLimitedInput.last['content'], 'What is this?');

      late Map<String, dynamic> characterLimitedBody;
      final characterLimitedTransport = AssistantProviderTransport(
        client: MockClient((request) async {
          characterLimitedBody =
              jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode(<String, Object?>{
              'output_text': 'Short answer.',
              'output': <Object?>[],
            }),
            200,
          );
        }),
      );
      addTearDown(characterLimitedTransport.close);
      final characterLimitedService = AssistantConversationService(
        transport: characterLimitedTransport,
      );
      await characterLimitedService.ask(
        store: store,
        provider: AssistantProvider.openAi,
        model: 'gpt-5',
        question: 'What is this?',
        history: List<AssistantChatTurn>.generate(
          20,
          (_) => AssistantChatTurn.user(List<String>.filled(1200, 'x').join()),
        ),
      );

      final characterLimitedInput =
          characterLimitedBody['input'] as List<dynamic>;
      expect(characterLimitedInput, hasLength(17));
      expect(
        (characterLimitedInput.first['content'] as String).length,
        1200,
      );
      expect(characterLimitedInput.last['content'], 'What is this?');
    });

    test('rejects blank and oversized questions before provider access',
        () async {
      var requestCount = 0;
      final transport = AssistantProviderTransport(
        client: MockClient((_) async {
          requestCount += 1;
          return http.Response('{}', 200);
        }),
      );
      addTearDown(transport.close);
      final service = AssistantConversationService(transport: transport);

      for (final question in <String>[
        '  ',
        List<String>.filled(35001, 'x').join()
      ]) {
        await expectLater(
          service.ask(
            store: store,
            provider: AssistantProvider.openAi,
            model: 'gpt-5',
            question: question,
          ),
          throwsA(isA<AssistantConversationException>().having(
            (error) => error.code,
            'code',
            'invalid_question',
          )),
        );
      }
      expect(requestCount, 0);
      expect(secureReadCount, 0);
    });
  });

  group('AssistantHowToKnowledgeService', () {
    test('adds only the relevant bounded guide for a how-to question', () {
      final guide = AssistantHowToKnowledgeService.contextFor(
        'كيف أنشئ فاتورة مبيعات؟',
      );
      final unrelated = AssistantHowToKnowledgeService.contextFor(
        'What were sales today?',
      );

      expect(guide, contains('Create a sales invoice'));
      expect(guide, contains('المبيعات'));
      expect(guide.length, lessThanOrEqualTo(4200));
      expect(unrelated, isEmpty);
    });
  });
}
