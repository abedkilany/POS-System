typedef AssistantJsonMap = Map<String, Object?>;

enum AssistantProvider {
  openAi('openai', 'OpenAI'),
  gemini('gemini', 'Google Gemini'),
  groq('groq', 'Groq'),
  kimi('kimi', 'Kimi (Moonshot AI)'),
  deepSeek('deepseek', 'DeepSeek');

  const AssistantProvider(this.storageId, this.label);

  final String storageId;
  final String label;
}

enum AssistantThinkingLevel {
  automatic('auto'),
  quick('low'),
  balanced('medium'),
  deep('high');

  const AssistantThinkingLevel(this.storageId);

  final String storageId;

  static AssistantThinkingLevel fromStorage(String? value) =>
      AssistantThinkingLevel.values.firstWhere(
        (level) => level.storageId == value,
        orElse: () => AssistantThinkingLevel.automatic,
      );
}

enum AssistantChatRole { user, assistant }

enum AssistantMessageRole { user, assistant, tool }

class AssistantChatTurn {
  const AssistantChatTurn({
    required this.role,
    required this.content,
    this.reports = const <AssistantJsonMap>[],
    this.errorDiagnostic,
    this.isError = false,
    this.attachedFileName,
    this.retryPayload,
    this.retryUserText,
    this.retryExchangeId,
  });

  const AssistantChatTurn.user(String content)
      : this(role: AssistantChatRole.user, content: content);

  const AssistantChatTurn.assistant(
    String content, {
    List<AssistantJsonMap> reports = const <AssistantJsonMap>[],
    String? errorDiagnostic,
    bool isError = false,
    String? retryPayload,
    String? retryUserText,
    String? retryExchangeId,
  }) : this(
          role: AssistantChatRole.assistant,
          content: content,
          reports: reports,
          errorDiagnostic: errorDiagnostic,
          isError: isError,
          retryPayload: retryPayload,
          retryUserText: retryUserText,
          retryExchangeId: retryExchangeId,
        );

  final AssistantChatRole role;
  final String content;
  final List<AssistantJsonMap> reports;
  final String? errorDiagnostic;
  final bool isError;
  final String? attachedFileName;
  final String? retryPayload;
  final String? retryUserText;
  final String? retryExchangeId;
}

class AssistantConversationResult {
  const AssistantConversationResult({
    required this.answer,
    this.reports = const <AssistantJsonMap>[],
  });

  final String answer;
  final List<AssistantJsonMap> reports;
}

class AssistantProviderToolCall {
  const AssistantProviderToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  final String id;
  final String name;
  final AssistantJsonMap arguments;
}

class AssistantProviderResponse {
  const AssistantProviderResponse({
    required this.text,
    this.toolCalls = const <AssistantProviderToolCall>[],
    this.providerPayload,
  });

  final String text;
  final List<AssistantProviderToolCall> toolCalls;

  /// Raw provider response items needed to continue a tool call round trip.
  /// These values live only for the current request and are never persisted.
  final Object? providerPayload;
}

class AssistantConversationMessage {
  const AssistantConversationMessage({
    required this.role,
    required this.content,
    this.toolCalls = const <AssistantProviderToolCall>[],
    this.toolCallId,
    this.toolName,
    this.providerPayload,
  });

  const AssistantConversationMessage.user(String content)
      : this(role: AssistantMessageRole.user, content: content);

  const AssistantConversationMessage.assistant(
    String content, {
    List<AssistantProviderToolCall> toolCalls =
        const <AssistantProviderToolCall>[],
    Object? providerPayload,
  }) : this(
          role: AssistantMessageRole.assistant,
          content: content,
          toolCalls: toolCalls,
          providerPayload: providerPayload,
        );

  const AssistantConversationMessage.tool({
    required String content,
    required String callId,
    required String name,
  }) : this(
          role: AssistantMessageRole.tool,
          content: content,
          toolCallId: callId,
          toolName: name,
        );

  final AssistantMessageRole role;
  final String content;
  final List<AssistantProviderToolCall> toolCalls;
  final String? toolCallId;
  final String? toolName;
  final Object? providerPayload;
}

class AssistantConversationException implements Exception {
  const AssistantConversationException(
    this.code,
    this.message, {
    this.diagnostic,
  });

  final String code;
  final String message;
  final String? diagnostic;

  @override
  String toString() => message;
}
