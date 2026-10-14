import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ventio/features/assistant/assistant_provider.dart';
import 'package:ventio/features/assistant/assistant_provider_transport.dart';

const _tool = <String, Object?>{
  'name': 'sales_summary',
  'description': 'Read sales totals.',
  'parameters': <String, Object?>{
    'type': 'object',
    'properties': <String, Object?>{
      'period': <String, Object?>{'type': 'string'},
    },
    'required': <String>['period'],
  },
};

AssistantProviderTransport _transport(
  Future<http.Response> Function(http.Request request) handler,
) =>
    AssistantProviderTransport(client: MockClient(handler));

http.Response _jsonResponse(Object body, {int statusCode = 200}) =>
    http.Response(
      jsonEncode(body),
      statusCode,
      headers: const <String, String>{'content-type': 'application/json'},
    );

void main() {
  group('AssistantProviderTransport', () {
    test('rejects empty models and API keys before making a request', () async {
      var requestCount = 0;
      final transport = _transport((_) async {
        requestCount += 1;
        return _jsonResponse(const <String, Object?>{});
      });
      addTearDown(transport.close);

      await expectLater(
        transport.complete(
          provider: AssistantProvider.openAi,
          model: '  ',
          apiKey: 'secret',
          systemPrompt: 'system',
          messages: const <AssistantConversationMessage>[
            AssistantConversationMessage.user('question'),
          ],
          tools: const <AssistantJsonMap>[],
        ),
        throwsA(isA<AssistantConversationException>().having(
          (error) => error.code,
          'code',
          'invalid_model',
        )),
      );
      await expectLater(
        transport.complete(
          provider: AssistantProvider.openAi,
          model: 'gpt-5',
          apiKey: ' ',
          systemPrompt: 'system',
          messages: const <AssistantConversationMessage>[
            AssistantConversationMessage.user('question'),
          ],
          tools: const <AssistantJsonMap>[],
        ),
        throwsA(isA<AssistantConversationException>().having(
          (error) => error.code,
          'code',
          'api_key_missing',
        )),
      );

      expect(requestCount, 0);
    });

    test('sends private OpenAI Responses requests and parses tool calls',
        () async {
      late http.Request captured;
      final transport = _transport((request) async {
        captured = request;
        return _jsonResponse(<String, Object?>{
          'status': 'completed',
          'output': <Object?>[
            <String, Object?>{
              'type': 'function_call',
              'call_id': 'call-1',
              'name': 'sales_summary',
              'arguments': '{"period":"today"}',
            },
            <String, Object?>{
              'type': 'message',
              'content': <Object?>[
                <String, Object?>{
                  'type': 'output_text',
                  'text': 'Sales are summarized.',
                },
              ],
            },
          ],
        });
      });
      addTearDown(transport.close);

      final result = await transport.complete(
        provider: AssistantProvider.openAi,
        model: 'gpt-5',
        apiKey: 'openai-test-key',
        systemPrompt: 'Use read-only reports.',
        messages: const <AssistantConversationMessage>[
          AssistantConversationMessage.user('Summarize today.'),
        ],
        tools: const <AssistantJsonMap>[_tool],
        thinkingLevel: AssistantThinkingLevel.deep,
      );

      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(captured.url.host, 'api.openai.com');
      expect(captured.url.path, '/v1/responses');
      expect(captured.headers['authorization'], 'Bearer openai-test-key');
      expect(body['store'], isFalse);
      expect(body['instructions'], 'Use read-only reports.');
      expect(body['max_output_tokens'], 4096);
      expect(body['reasoning'], <String, Object?>{'effort': 'high'});
      expect(body['tool_choice'], 'auto');
      expect(result.text, 'Sales are summarized.');
      expect(result.toolCalls.single.id, 'call-1');
      expect(result.toolCalls.single.name, 'sales_summary');
      expect(result.toolCalls.single.arguments, <String, Object?>{
        'period': 'today',
      });
    });

    test('sends Gemini Interactions requests and parses tool calls', () async {
      late http.Request captured;
      final transport = _transport((request) async {
        captured = request;
        return _jsonResponse(<String, Object?>{
          'status': 'completed',
          'steps': <Object?>[
            <String, Object?>{'type': 'text', 'text': 'Gemini answer.'},
            <String, Object?>{
              'type': 'function_call',
              'name': 'sales_summary',
              'arguments': <String, Object?>{'period': 'today'},
            },
          ],
        });
      });
      addTearDown(transport.close);

      final result = await transport.complete(
        provider: AssistantProvider.gemini,
        model: 'gemini-2.5-flash',
        apiKey: 'gemini-test-key',
        systemPrompt: 'Use read-only reports.',
        messages: const <AssistantConversationMessage>[
          AssistantConversationMessage.user('Summarize today.'),
        ],
        tools: const <AssistantJsonMap>[_tool],
        thinkingLevel: AssistantThinkingLevel.balanced,
      );

      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      final generation = body['generation_config'] as Map<String, dynamic>;
      expect(captured.url.host, 'generativelanguage.googleapis.com');
      expect(captured.url.path, '/v1beta/interactions');
      expect(captured.headers['x-goog-api-key'], 'gemini-test-key');
      expect(body['system_instruction'], 'Use read-only reports.');
      expect(generation['max_output_tokens'], 4096);
      expect(generation['thinking_level'], 'medium');
      expect(result.text, 'Gemini answer.');
      expect(result.toolCalls.single.id, 'gemini_tool_0');
      expect(result.toolCalls.single.arguments['period'], 'today');
    });

    for (final providerCase in <({
      AssistantProvider provider,
      String host,
      String path,
      String tokenField,
      Object tokenLimit,
      bool preserveMessage,
    })>[
      (
        provider: AssistantProvider.groq,
        host: 'api.groq.com',
        path: '/openai/v1/chat/completions',
        tokenField: 'max_completion_tokens',
        tokenLimit: 4096,
        preserveMessage: false,
      ),
      (
        provider: AssistantProvider.kimi,
        host: 'api.moonshot.ai',
        path: '/v1/chat/completions',
        tokenField: 'max_completion_tokens',
        tokenLimit: 4096,
        preserveMessage: true,
      ),
      (
        provider: AssistantProvider.deepSeek,
        host: 'api.deepseek.com',
        path: '/chat/completions',
        tokenField: 'max_tokens',
        tokenLimit: 4096,
        preserveMessage: true,
      ),
    ]) {
      test('${providerCase.provider.label} chat completion request round trip',
          () async {
        late http.Request captured;
        final transport = _transport((request) async {
          captured = request;
          return _jsonResponse(<String, Object?>{
            'choices': <Object?>[
              <String, Object?>{
                'finish_reason': 'stop',
                'message': <String, Object?>{
                  'role': 'assistant',
                  'content': '  Provider answer. ',
                  'tool_calls': <Object?>[
                    <String, Object?>{
                      'id': 'call-chat',
                      'type': 'function',
                      'function': <String, Object?>{
                        'name': 'sales_summary',
                        'arguments': '{"period":"today"}',
                      },
                    },
                  ],
                },
              },
            ],
          });
        });
        addTearDown(transport.close);

        final result = await transport.complete(
          provider: providerCase.provider,
          model: providerCase.provider == AssistantProvider.groq
              ? 'deepseek-r1-distill-qwen-32b'
              : '${providerCase.provider.storageId}-reasoner',
          apiKey: 'provider-test-key',
          systemPrompt: 'Read-only assistant.',
          messages: const <AssistantConversationMessage>[
            AssistantConversationMessage.user('Summarize today.'),
          ],
          tools: const <AssistantJsonMap>[_tool],
          thinkingLevel: AssistantThinkingLevel.deep,
        );

        final body = jsonDecode(captured.body) as Map<String, dynamic>;
        final messages = body['messages'] as List<dynamic>;
        expect(captured.url.host, providerCase.host);
        expect(captured.url.path, providerCase.path);
        expect(captured.headers['authorization'], 'Bearer provider-test-key');
        expect(body[providerCase.tokenField], providerCase.tokenLimit);
        expect(messages.first['role'], 'system');
        expect(messages.first['content'], 'Read-only assistant.');
        expect(body['tool_choice'], 'auto');
        expect(result.text, 'Provider answer.');
        expect(result.toolCalls.single.arguments['period'], 'today');
        expect(result.providerPayload != null, providerCase.preserveMessage);
        if (providerCase.provider != AssistantProvider.groq) {
          expect(body['reasoning_effort'], 'max');
        }
      });
    }

    test('lists only supported Gemini text models in stable order', () async {
      late http.Request captured;
      final transport = _transport((request) async {
        captured = request;
        return _jsonResponse(<String, Object?>{
          'models': <Object?>[
            <String, Object?>{'baseModelId': 'gemini-2.5-pro'},
            <String, Object?>{'baseModelId': 'gemini-2.5-flash'},
            <String, Object?>{'baseModelId': 'text-embedding-004'},
            <String, Object?>{'baseModelId': 'gemini-2.5-pro'},
          ],
        });
      });
      addTearDown(transport.close);

      final models = await transport.listModels(
        provider: AssistantProvider.gemini,
        apiKey: 'gemini-test-key',
      );

      expect(captured.url.path, '/v1beta/models');
      expect(captured.headers['x-goog-api-key'], 'gemini-test-key');
      expect(models, <String>['gemini-2.5-flash', 'gemini-2.5-pro']);
    });

    test('redacts provider API keys from safe error diagnostics', () async {
      const apiKey = 'sk-secret-provider-token-123456789';
      final transport = _transport((_) async => _jsonResponse(
            <String, Object?>{
              'error': <String, Object?>{
                'message': 'Invalid key $apiKey. Please rotate it.',
              },
            },
            statusCode: 401,
          ));
      addTearDown(transport.close);

      await expectLater(
        transport.complete(
          provider: AssistantProvider.openAi,
          model: 'gpt-4.1-mini',
          apiKey: apiKey,
          systemPrompt: 'system',
          messages: const <AssistantConversationMessage>[
            AssistantConversationMessage.user('question'),
          ],
          tools: const <AssistantJsonMap>[],
        ),
        throwsA(isA<AssistantConversationException>().having(
          (error) => error.diagnostic,
          'diagnostic',
          allOf(contains('[redacted]'), isNot(contains(apiKey))),
        )),
      );
    });

    test('rejects provider responses that are incomplete or malformed',
        () async {
      final transport = _transport((_) async => _jsonResponse(
            <String, Object?>{'status': 'incomplete', 'steps': <Object?>[]},
          ));
      addTearDown(transport.close);

      await expectLater(
        transport.complete(
          provider: AssistantProvider.gemini,
          model: 'gemini-2.5-flash',
          apiKey: 'gemini-test-key',
          systemPrompt: 'system',
          messages: const <AssistantConversationMessage>[
            AssistantConversationMessage.user('question'),
          ],
          tools: const <AssistantJsonMap>[],
        ),
        throwsA(isA<AssistantConversationException>().having(
          (error) => error.code,
          'code',
          'provider_output_limited',
        )),
      );
    });
  });
}
