import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'assistant_provider.dart';

/// Direct, ephemeral HTTP adapters for supported model providers.
/// Request and response bodies are never logged or persisted by this class.
class AssistantProviderTransport {
  AssistantProviderTransport({http.Client? client})
      : _client = client ?? http.Client();

  static const Duration _requestTimeout = Duration(seconds: 60);
  static const Duration _reasoningProviderRequestTimeout =
      Duration(seconds: 120);
  static const int _maxOutputTokens = 4096;
  final http.Client _client;

  Future<AssistantProviderResponse> complete({
    required AssistantProvider provider,
    required String model,
    required String apiKey,
    required String systemPrompt,
    required List<AssistantConversationMessage> messages,
    required List<AssistantJsonMap> tools,
    AssistantThinkingLevel thinkingLevel = AssistantThinkingLevel.automatic,
  }) async {
    if (kIsWeb) {
      throw const AssistantConversationException(
        'web_provider_setup_unavailable',
        'AI provider requests are not enabled in Ventio Web until a secure provider gateway is configured.',
      );
    }
    final normalizedModel = model.trim();
    if (normalizedModel.isEmpty || normalizedModel.length > 120) {
      throw const AssistantConversationException(
        'invalid_model',
        'Choose a valid model name for this provider.',
      );
    }
    if (apiKey.trim().isEmpty) {
      throw const AssistantConversationException(
        'api_key_missing',
        'Connect an API key for the selected AI provider.',
      );
    }

    return switch (provider) {
      AssistantProvider.openAi => _completeOpenAi(
          model: normalizedModel,
          apiKey: apiKey,
          systemPrompt: systemPrompt,
          messages: messages,
          tools: tools,
          thinkingLevel: thinkingLevel,
        ),
      AssistantProvider.gemini => _completeGemini(
          model: normalizedModel,
          apiKey: apiKey,
          systemPrompt: systemPrompt,
          messages: messages,
          tools: tools,
          thinkingLevel: thinkingLevel,
        ),
      AssistantProvider.groq => _completeGroq(
          model: normalizedModel,
          apiKey: apiKey,
          systemPrompt: systemPrompt,
          messages: messages,
          tools: tools,
          thinkingLevel: thinkingLevel,
        ),
      AssistantProvider.kimi => _completeKimi(
          model: normalizedModel,
          apiKey: apiKey,
          systemPrompt: systemPrompt,
          messages: messages,
          tools: tools,
          thinkingLevel: thinkingLevel,
        ),
      AssistantProvider.deepSeek => _completeDeepSeek(
          model: normalizedModel,
          apiKey: apiKey,
          systemPrompt: systemPrompt,
          messages: messages,
          tools: tools,
          thinkingLevel: thinkingLevel,
        ),
    };
  }

  Future<List<String>> listModels({
    required AssistantProvider provider,
    required String apiKey,
  }) async {
    if (kIsWeb) {
      throw const AssistantConversationException(
        'web_provider_setup_unavailable',
        'AI provider requests are not enabled in Ventio Web until a secure provider gateway is configured.',
      );
    }
    if (apiKey.trim().isEmpty) {
      throw const AssistantConversationException(
        'api_key_missing',
        'Connect an API key for the selected AI provider.',
      );
    }
    final (uri, headers) = switch (provider) {
      AssistantProvider.openAi => (
          Uri.https('api.openai.com', '/v1/models'),
          <String, String>{'Authorization': 'Bearer $apiKey'},
        ),
      AssistantProvider.gemini => (
          Uri.https('generativelanguage.googleapis.com', '/v1beta/models'),
          <String, String>{'x-goog-api-key': apiKey},
        ),
      AssistantProvider.groq => (
          Uri.https('api.groq.com', '/openai/v1/models'),
          <String, String>{'Authorization': 'Bearer $apiKey'},
        ),
      AssistantProvider.kimi => (
          Uri.https('api.moonshot.ai', '/v1/models'),
          <String, String>{'Authorization': 'Bearer $apiKey'},
        ),
      AssistantProvider.deepSeek => (
          Uri.https('api.deepseek.com', '/models'),
          <String, String>{'Authorization': 'Bearer $apiKey'},
        ),
    };
    final response = await _getJson(
      uri,
      headers: headers,
      provider: provider,
      apiKey: apiKey,
    );
    final raw = provider == AssistantProvider.gemini
        ? response['models']
        : response['data'];
    if (raw is! List) {
      throw const AssistantConversationException(
        'provider_response_invalid',
        'The provider did not return a model list.',
      );
    }
    final models = <String>{};
    for (final item in raw) {
      if (item is! Map) continue;
      final model = provider == AssistantProvider.gemini
          ? (item['baseModelId']?.toString() ?? item['name']?.toString() ?? '')
          : (item['id']?.toString() ?? '');
      final normalized = model.replaceFirst(RegExp(r'^models/'), '').trim();
      if (normalized.isEmpty || normalized.length > 120) continue;
      final lower = normalized.toLowerCase();
      if (provider == AssistantProvider.gemini && !lower.contains('gemini')) {
        continue;
      }
      if (provider == AssistantProvider.groq && item['active'] == false) {
        continue;
      }
      if (provider == AssistantProvider.kimi && !lower.startsWith('kimi-')) {
        continue;
      }
      if (provider == AssistantProvider.deepSeek &&
          !lower.startsWith('deepseek-')) {
        continue;
      }
      if (RegExp(
              r'(embedding|whisper|tts|transcri|moderation|dall-e|gpt-image|imagegen|realtime|audio)')
          .hasMatch(lower)) {
        continue;
      }
      models.add(normalized);
    }
    final result = models.toList()..sort();
    if (result.isEmpty) {
      throw const AssistantConversationException(
        'provider_models_empty',
        'No text generation models were found for this provider account.',
      );
    }
    return List<String>.unmodifiable(result);
  }

  void close() => _client.close();

  Future<AssistantProviderResponse> _completeOpenAi({
    required String model,
    required String apiKey,
    required String systemPrompt,
    required List<AssistantConversationMessage> messages,
    required List<AssistantJsonMap> tools,
    required AssistantThinkingLevel thinkingLevel,
  }) async {
    final body = <String, Object?>{
      'model': model,
      'store': false,
      'instructions': systemPrompt,
      'input': _openAiInput(messages),
      'max_output_tokens': _maxOutputTokens,
    };
    if (tools.isNotEmpty) {
      body['tools'] = tools.map(_openAiTool).toList(growable: false);
      body['tool_choice'] = 'auto';
    }
    if (thinkingLevel != AssistantThinkingLevel.automatic &&
        _supportsOpenAiReasoning(model)) {
      body['reasoning'] = <String, Object?>{
        'effort': thinkingLevel.storageId,
      };
    }
    final response = await _postJson(
      Uri.https('api.openai.com', '/v1/responses'),
      headers: <String, String>{'Authorization': 'Bearer $apiKey'},
      body: body,
      provider: AssistantProvider.openAi,
      apiKey: apiKey,
    );
    if (response['status'] == 'incomplete') {
      throw const AssistantConversationException(
        'provider_output_limited',
        'The AI response was cut off. Ask a narrower question or choose a model with a larger response limit.',
      );
    }
    final rawOutput = response['output'];
    final outputItems = rawOutput is List ? rawOutput : const <Object?>[];
    final toolCalls = <AssistantProviderToolCall>[];
    final textParts = <String>[];
    for (final item in outputItems) {
      if (item is! Map) continue;
      final outputItem = Map<String, Object?>.from(item);
      if (outputItem['type'] == 'function_call') {
        toolCalls.add(_parseOpenAiToolCall(outputItem));
      } else if (outputItem['type'] == 'message') {
        final content = outputItem['content'];
        if (content is List) {
          for (final part in content) {
            if (part is Map && part['type'] == 'output_text') {
              final text = part['text']?.toString().trim() ?? '';
              if (text.isNotEmpty) textParts.add(text);
            }
          }
        }
      }
    }
    final topLevelText = response['output_text']?.toString().trim() ?? '';
    final text = topLevelText.isNotEmpty ? topLevelText : textParts.join('\n');
    return AssistantProviderResponse(
      text: text,
      toolCalls: List<AssistantProviderToolCall>.unmodifiable(toolCalls),
      providerPayload: outputItems,
    );
  }

  Future<AssistantProviderResponse> _completeGemini({
    required String model,
    required String apiKey,
    required String systemPrompt,
    required List<AssistantConversationMessage> messages,
    required List<AssistantJsonMap> tools,
    required AssistantThinkingLevel thinkingLevel,
  }) async {
    final body = <String, Object?>{
      'model': model,
      'store': false,
      'system_instruction': systemPrompt,
      'input': _geminiInput(messages),
      'generation_config': <String, Object?>{
        'max_output_tokens': _maxOutputTokens,
      },
    };
    if (thinkingLevel != AssistantThinkingLevel.automatic &&
        _supportsGeminiThinking(model)) {
      (body['generation_config'] as Map<String, Object?>)['thinking_level'] =
          thinkingLevel.storageId;
    }
    if (tools.isNotEmpty) {
      body['tools'] = tools.map(_geminiTool).toList(growable: false);
    }
    final response = await _postJson(
      Uri.https('generativelanguage.googleapis.com', '/v1beta/interactions'),
      headers: <String, String>{'x-goog-api-key': apiKey},
      body: body,
      provider: AssistantProvider.gemini,
      apiKey: apiKey,
    );
    if (response['status'] == 'incomplete') {
      throw const AssistantConversationException(
        'provider_output_limited',
        'The AI response was cut off. Ask a narrower question or choose a model with a larger response limit.',
      );
    }
    final rawSteps = response['steps'];
    if (rawSteps is! List) {
      throw const AssistantConversationException(
        'provider_response_invalid',
        'The AI provider returned an unreadable response.',
      );
    }
    final toolCalls = <AssistantProviderToolCall>[];
    final textParts = <String>[];
    for (final rawStep in rawSteps) {
      if (rawStep is! Map) continue;
      final step = Map<String, Object?>.from(rawStep);
      if (step['type'] == 'function_call') {
        toolCalls.add(_parseGeminiToolCall(step, toolCalls.length));
      } else if (step['type'] == 'text' || step['type'] == 'model_output') {
        final text = _geminiText(step['text'] ?? step['content']);
        if (text.isNotEmpty) textParts.add(text);
      }
    }
    final topLevelText = _geminiText(response['output_text']);
    return AssistantProviderResponse(
      text: topLevelText.isNotEmpty ? topLevelText : textParts.join('\n'),
      toolCalls: List<AssistantProviderToolCall>.unmodifiable(toolCalls),
      providerPayload: rawSteps,
    );
  }

  static String _geminiText(Object? value) {
    if (value is String) return value.trim();
    if (value is List) {
      return value
          .map(_geminiText)
          .where((text) => text.isNotEmpty)
          .join('\n');
    }
    if (value is Map) {
      final content = Map<String, Object?>.from(value);
      final text = content['text'];
      if (text is String && text.trim().isNotEmpty) return text.trim();
      return _geminiText(content['content'] ?? content['parts']);
    }
    return '';
  }

  Future<AssistantProviderResponse> _completeGroq({
    required String model,
    required String apiKey,
    required String systemPrompt,
    required List<AssistantConversationMessage> messages,
    required List<AssistantJsonMap> tools,
    required AssistantThinkingLevel thinkingLevel,
  }) async {
    final body = <String, Object?>{
      'model': model,
      'messages': <AssistantJsonMap>[
        <String, Object?>{'role': 'system', 'content': systemPrompt},
        ..._chatCompletionMessages(messages),
      ],
      'max_completion_tokens': _maxOutputTokens,
    };
    if (tools.isNotEmpty) {
      body['tools'] = tools.map(_chatCompletionTool).toList(growable: false);
      body['tool_choice'] = 'auto';
    }
    if (thinkingLevel != AssistantThinkingLevel.automatic &&
        _supportsGroqReasoning(model)) {
      body['reasoning_effort'] = thinkingLevel.storageId;
    }
    final response = await _postJson(
      Uri.https('api.groq.com', '/openai/v1/chat/completions'),
      headers: <String, String>{'Authorization': 'Bearer $apiKey'},
      body: body,
      provider: AssistantProvider.groq,
      apiKey: apiKey,
    );
    return _parseChatCompletion(response);
  }

  Future<AssistantProviderResponse> _completeKimi({
    required String model,
    required String apiKey,
    required String systemPrompt,
    required List<AssistantConversationMessage> messages,
    required List<AssistantJsonMap> tools,
    required AssistantThinkingLevel thinkingLevel,
  }) async {
    final body = <String, Object?>{
      'model': model,
      'messages': <AssistantJsonMap>[
        <String, Object?>{'role': 'system', 'content': systemPrompt},
        ..._chatCompletionMessages(messages),
      ],
      'max_completion_tokens': 4096,
    };
    if (tools.isNotEmpty) {
      body['tools'] = tools.map(_chatCompletionTool).toList(growable: false);
      body['tool_choice'] = 'auto';
    }
    final reasoningEffort = switch (thinkingLevel) {
      AssistantThinkingLevel.automatic => null,
      AssistantThinkingLevel.quick => 'low',
      AssistantThinkingLevel.balanced => 'high',
      AssistantThinkingLevel.deep => 'max',
    };
    if (reasoningEffort != null) {
      body['reasoning_effort'] = reasoningEffort;
    }
    final response = await _postJson(
      Uri.https('api.moonshot.ai', '/v1/chat/completions'),
      headers: <String, String>{'Authorization': 'Bearer $apiKey'},
      body: body,
      provider: AssistantProvider.kimi,
      apiKey: apiKey,
    );
    return _parseChatCompletion(response, preserveAssistantMessage: true);
  }

  Future<AssistantProviderResponse> _completeDeepSeek({
    required String model,
    required String apiKey,
    required String systemPrompt,
    required List<AssistantConversationMessage> messages,
    required List<AssistantJsonMap> tools,
    required AssistantThinkingLevel thinkingLevel,
  }) async {
    final body = <String, Object?>{
      'model': model,
      'messages': <AssistantJsonMap>[
        <String, Object?>{'role': 'system', 'content': systemPrompt},
        ..._chatCompletionMessages(messages),
      ],
      'max_tokens': 4096,
    };
    if (tools.isNotEmpty) {
      body['tools'] = tools.map(_chatCompletionTool).toList(growable: false);
      body['tool_choice'] = 'auto';
    }
    final reasoningEffort = switch (thinkingLevel) {
      AssistantThinkingLevel.automatic => null,
      AssistantThinkingLevel.quick => 'low',
      AssistantThinkingLevel.balanced => 'high',
      AssistantThinkingLevel.deep => 'max',
    };
    if (reasoningEffort != null) {
      body['reasoning_effort'] = reasoningEffort;
    }
    final response = await _postJson(
      Uri.https('api.deepseek.com', '/chat/completions'),
      headers: <String, String>{'Authorization': 'Bearer $apiKey'},
      body: body,
      provider: AssistantProvider.deepSeek,
      apiKey: apiKey,
    );
    return _parseChatCompletion(response, preserveAssistantMessage: true);
  }

  Future<AssistantJsonMap> _postJson(
    Uri uri, {
    required Map<String, String> headers,
    required AssistantJsonMap body,
    required AssistantProvider provider,
    required String apiKey,
  }) async {
    http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: <String, String>{
              'Content-Type': 'application/json',
              ...headers,
            },
            body: jsonEncode(body),
          )
          .timeout(provider == AssistantProvider.kimi ||
                  provider == AssistantProvider.deepSeek
              ? _reasoningProviderRequestTimeout
              : _requestTimeout);
    } on TimeoutException {
      throw const AssistantConversationException(
        'provider_timeout',
        'The AI provider took too long to respond. Try again.',
      );
    } on http.ClientException {
      throw const AssistantConversationException(
        'provider_connection_failed',
        'Ventio could not connect to the selected AI provider.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _httpError(
        provider,
        response.statusCode,
        response.body,
        apiKey: apiKey,
      );
    }
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) return Map<String, Object?>.from(decoded);
    } on FormatException {
      // A safe provider error is returned below; response contents aren't logged.
    }
    throw const AssistantConversationException(
      'provider_response_invalid',
      'The AI provider returned an unreadable response.',
    );
  }

  Future<AssistantJsonMap> _getJson(
    Uri uri, {
    required Map<String, String> headers,
    required AssistantProvider provider,
    required String apiKey,
  }) async {
    http.Response response;
    try {
      response =
          await _client.get(uri, headers: headers).timeout(_requestTimeout);
    } on TimeoutException {
      throw const AssistantConversationException(
        'provider_timeout',
        'The AI provider took too long to respond. Try again.',
      );
    } on http.ClientException {
      throw const AssistantConversationException(
        'provider_connection_failed',
        'Ventio could not connect to the selected AI provider.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _httpError(
        provider,
        response.statusCode,
        response.body,
        apiKey: apiKey,
      );
    }
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) return Map<String, Object?>.from(decoded);
    } on FormatException {
      // Provider response content is never logged.
    }
    throw const AssistantConversationException(
      'provider_response_invalid',
      'The AI provider returned an unreadable response.',
    );
  }

  static bool _supportsOpenAiReasoning(String model) {
    final id = model.toLowerCase();
    return id.startsWith('o1') ||
        id.startsWith('o3') ||
        id.startsWith('o4') ||
        id.startsWith('gpt-5');
  }

  static bool _supportsGeminiThinking(String model) {
    final id = model.toLowerCase();
    return id.contains('gemini-2.5') || id.contains('gemini-3');
  }

  static bool _supportsGroqReasoning(String model) {
    final id = model.toLowerCase();
    return id.contains('qwen3') ||
        id.contains('gpt-oss') ||
        id.contains('deepseek-r1') ||
        id.contains('qwq');
  }

  AssistantConversationException _httpError(
    AssistantProvider provider,
    int statusCode,
    String responseBody, {
    required String apiKey,
  }) {
    final diagnostic = _safeProviderDiagnostic(
      statusCode,
      responseBody,
      apiKey: apiKey,
    );
    if (statusCode == 401) {
      return AssistantConversationException(
        'provider_authentication_failed',
        'The ${provider.label} API key was rejected. Check the key and try again.',
        diagnostic: diagnostic,
      );
    }
    if (statusCode == 403) {
      return AssistantConversationException(
        'provider_access_denied',
        '${provider.label} denied this request. Check the account and model access.',
        diagnostic: diagnostic,
      );
    }
    if (statusCode == 429) {
      return AssistantConversationException(
        'provider_rate_limited',
        '${provider.label} is temporarily rate limiting requests. Try again later.',
        diagnostic: diagnostic,
      );
    }
    if (statusCode >= 500) {
      return AssistantConversationException(
        'provider_unavailable',
        '${provider.label} is temporarily unavailable. Try again later.',
        diagnostic: diagnostic,
      );
    }
    return AssistantConversationException(
      'provider_request_rejected',
      '${provider.label} rejected the request. Check the selected model and settings.',
      diagnostic: diagnostic,
    );
  }

  static String _safeProviderDiagnostic(
    int statusCode,
    String responseBody, {
    required String apiKey,
  }) {
    var providerMessage = '';
    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is Map && decoded['error'] is Map) {
        final error = Map<String, Object?>.from(decoded['error'] as Map);
        providerMessage = error['message']?.toString().trim() ?? '';
      }
    } on FormatException {
      // Keep only the HTTP status when a provider returns an unreadable body.
    }

    if (providerMessage.isEmpty) return 'HTTP $statusCode';
    if (apiKey.isNotEmpty) {
      providerMessage = providerMessage.replaceAll(apiKey, '[redacted]');
    }
    providerMessage = providerMessage
        .replaceAll(
          RegExp(r'AIza[0-9A-Za-z_-]{20,}'),
          '[redacted]',
        )
        .replaceAll(
          RegExp(r'(?:sk-|gsk_)[A-Za-z0-9_-]{12,}'),
          '[redacted]',
        )
        .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (providerMessage.length > 400) {
      providerMessage = '${providerMessage.substring(0, 400)}…';
    }
    return 'HTTP $statusCode: $providerMessage';
  }

  static List<AssistantJsonMap> _openAiInput(
    List<AssistantConversationMessage> messages,
  ) {
    final input = <AssistantJsonMap>[];
    for (final message in messages) {
      switch (message.role) {
        case AssistantMessageRole.user:
          input.add(<String, Object?>{
            'role': 'user',
            'content': message.content,
          });
        case AssistantMessageRole.assistant:
          final raw = message.providerPayload;
          if (raw is List) {
            for (final item in raw) {
              if (item is Map) input.add(Map<String, Object?>.from(item));
            }
          } else if (message.content.trim().isNotEmpty) {
            input.add(<String, Object?>{
              'role': 'assistant',
              'content': message.content,
            });
          }
        case AssistantMessageRole.tool:
          input.add(<String, Object?>{
            'type': 'function_call_output',
            'call_id': message.toolCallId,
            'output': message.content,
          });
      }
    }
    return input;
  }

  static AssistantJsonMap _openAiTool(AssistantJsonMap definition) =>
      <String, Object?>{
        'type': 'function',
        'name': definition['name'],
        'description': definition['description'],
        'parameters': definition['parameters'],
        'strict': false,
      };

  static AssistantProviderToolCall _parseOpenAiToolCall(
    AssistantJsonMap item,
  ) {
    final id = item['call_id']?.toString() ?? '';
    final name = item['name']?.toString() ?? '';
    final rawArguments = item['arguments'];
    if (id.isEmpty || name.isEmpty || rawArguments is! String) {
      throw const AssistantConversationException(
        'provider_response_invalid',
        'The AI provider returned an incomplete read request.',
      );
    }
    return AssistantProviderToolCall(
      id: id,
      name: name,
      arguments: _decodeArguments(rawArguments),
    );
  }

  static List<AssistantJsonMap> _chatCompletionMessages(
    List<AssistantConversationMessage> messages,
  ) {
    final result = <AssistantJsonMap>[];
    for (final message in messages) {
      switch (message.role) {
        case AssistantMessageRole.user:
          result.add(<String, Object?>{
            'role': 'user',
            'content': message.content,
          });
        case AssistantMessageRole.assistant:
          final raw = message.providerPayload;
          if (raw is Map) {
            result.add(Map<String, Object?>.from(raw));
            continue;
          }
          final row = <String, Object?>{'role': 'assistant'};
          if (message.content.trim().isNotEmpty) {
            row['content'] = message.content;
          }
          if (message.toolCalls.isNotEmpty) {
            row['tool_calls'] = message.toolCalls
                .map((call) => <String, Object?>{
                      'id': call.id,
                      'type': 'function',
                      'function': <String, Object?>{
                        'name': call.name,
                        'arguments': jsonEncode(call.arguments),
                      },
                    })
                .toList(growable: false);
          }
          result.add(row);
        case AssistantMessageRole.tool:
          result.add(<String, Object?>{
            'role': 'tool',
            'tool_call_id': message.toolCallId,
            if (message.toolName != null) 'name': message.toolName,
            'content': message.content,
          });
      }
    }
    return result;
  }

  static AssistantJsonMap _chatCompletionTool(AssistantJsonMap definition) =>
      <String, Object?>{
        'type': 'function',
        'function': <String, Object?>{
          'name': definition['name'],
          'description': definition['description'],
          'parameters': definition['parameters'],
        },
      };

  static AssistantProviderResponse _parseChatCompletion(
    AssistantJsonMap response, {
    bool preserveAssistantMessage = false,
  }) {
    final choices = response['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      throw const AssistantConversationException(
        'provider_response_invalid',
        'The AI provider returned an unreadable response.',
      );
    }
    final choice = Map<String, Object?>.from(choices.first as Map);
    if (choice['finish_reason'] == 'length') {
      throw const AssistantConversationException(
        'provider_output_limited',
        'The AI response was cut off. Ask a narrower question or choose a model with a larger response limit.',
      );
    }
    final message = choice['message'];
    if (message is! Map) {
      throw const AssistantConversationException(
        'provider_response_invalid',
        'The AI provider returned an unreadable response.',
      );
    }
    final assistantMessage = Map<String, Object?>.from(message);
    final rawContent = assistantMessage['content'];
    final text = rawContent is String
        ? rawContent.trim()
        : _chatTextFromParts(rawContent);
    final calls = <AssistantProviderToolCall>[];
    final rawCalls = assistantMessage['tool_calls'];
    if (rawCalls is List) {
      for (final rawCall in rawCalls) {
        if (rawCall is! Map) continue;
        final call = Map<String, Object?>.from(rawCall);
        final function = call['function'];
        if (function is! Map) continue;
        final functionData = Map<String, Object?>.from(function);
        final id = call['id']?.toString() ?? '';
        final name = functionData['name']?.toString() ?? '';
        final arguments = functionData['arguments'];
        if (id.isEmpty || name.isEmpty || arguments is! String) {
          throw const AssistantConversationException(
            'provider_response_invalid',
            'The AI provider returned an incomplete read request.',
          );
        }
        calls.add(AssistantProviderToolCall(
          id: id,
          name: name,
          arguments: _decodeArguments(arguments),
        ));
      }
    }
    return AssistantProviderResponse(
      text: text,
      toolCalls: List<AssistantProviderToolCall>.unmodifiable(calls),
      providerPayload: preserveAssistantMessage ? assistantMessage : null,
    );
  }

  static String _chatTextFromParts(Object? value) {
    if (value is! List) return '';
    return value
        .whereType<Map>()
        .map((part) => part['text']?.toString().trim() ?? '')
        .where((part) => part.isNotEmpty)
        .join('\n');
  }

  static AssistantJsonMap _geminiTool(AssistantJsonMap definition) {
    final rawParameters = definition['parameters'];
    return <String, Object?>{
      'type': 'function',
      'name': definition['name'],
      'description': definition['description'],
      'parameters': rawParameters is Map
          ? _geminiSchema(Map<String, Object?>.from(rawParameters))
          : <String, Object?>{'type': 'object'},
    };
  }

  static AssistantJsonMap _geminiSchema(AssistantJsonMap schema) {
    const supportedKeys = <String>{
      'type',
      'description',
      'properties',
      'required',
      'items',
      'enum',
      'nullable',
    };
    final result = <String, Object?>{};
    for (final entry in schema.entries) {
      if (!supportedKeys.contains(entry.key)) continue;
      final value = entry.value;
      if (entry.key == 'properties' && value is Map) {
        result[entry.key] = <String, Object?>{
          for (final property in value.entries)
            if (property.key is String && property.value is Map)
              property.key as String: _geminiSchema(
                Map<String, Object?>.from(property.value as Map),
              ),
        };
      } else if (entry.key == 'items' && value is Map) {
        result[entry.key] = _geminiSchema(Map<String, Object?>.from(value));
      } else {
        result[entry.key] = value;
      }
    }
    return result;
  }

  static List<AssistantJsonMap> _geminiInput(
    List<AssistantConversationMessage> messages,
  ) {
    final preamble = StringBuffer();
    final interactionSteps = <AssistantJsonMap>[];
    var modelHasResponded = false;
    for (final message in messages) {
      switch (message.role) {
        case AssistantMessageRole.user:
          if (!modelHasResponded) {
            preamble
              ..write('User: ')
              ..writeln(message.content);
          } else {
            interactionSteps.add(<String, Object?>{
              'type': 'user_input',
              'content': message.content,
            });
          }
        case AssistantMessageRole.assistant:
          final raw = message.providerPayload;
          if (raw is List) {
            modelHasResponded = true;
            for (final step in raw) {
              if (step is Map) {
                interactionSteps.add(Map<String, Object?>.from(step));
              }
            }
          } else if (message.content.trim().isNotEmpty ||
              message.toolCalls.isNotEmpty) {
            if (!modelHasResponded) {
              preamble
                ..write('Assistant: ')
                ..writeln(message.content);
            }
          }
        case AssistantMessageRole.tool:
          interactionSteps.add(<String, Object?>{
            'type': 'function_result',
            'name': message.toolName,
            'call_id': message.toolCallId,
            'result': <AssistantJsonMap>[
              <String, Object?>{'type': 'text', 'text': message.content},
            ],
          });
      }
    }
    final input = <AssistantJsonMap>[];
    if (preamble.isNotEmpty) {
      input.add(<String, Object?>{
        'type': 'user_input',
        'content': preamble.toString().trim(),
      });
    }
    input.addAll(interactionSteps);
    return input;
  }

  static AssistantProviderToolCall _parseGeminiToolCall(
    AssistantJsonMap functionCall,
    int index,
  ) {
    final name = functionCall['name']?.toString() ?? '';
    final args = functionCall['arguments'];
    if (name.isEmpty || (args != null && args is! Map)) {
      throw const AssistantConversationException(
        'provider_response_invalid',
        'The AI provider returned an incomplete read request.',
      );
    }
    return AssistantProviderToolCall(
      id: functionCall['id']?.toString() ?? 'gemini_tool_$index',
      name: name,
      arguments:
          args is Map ? Map<String, Object?>.from(args) : <String, Object?>{},
    );
  }

  static AssistantJsonMap _decodeArguments(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, Object?>.from(decoded);
    } on FormatException {
      // The caller receives a provider protocol error without raw model text.
    }
    throw const AssistantConversationException(
      'provider_response_invalid',
      'The AI provider returned invalid read arguments.',
    );
  }
}
