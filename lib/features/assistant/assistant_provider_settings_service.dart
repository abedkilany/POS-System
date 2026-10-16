import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ventio/core/contracts/application_session.dart';
import 'assistant_provider.dart';

/// Device-local provider credentials and explicit business-data consent.
///
/// Credentials use platform secure storage. Consent is a local preference and
/// is scoped to the signed-in Ventio user, store, and provider.
class AssistantProviderSettingsService {
  AssistantProviderSettingsService._();

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static String _consentRevision(AssistantProvider provider) =>
      switch (provider) {
        AssistantProvider.openAi => 'openai-business-data-v3',
        AssistantProvider.gemini => 'gemini-business-data-v3',
        AssistantProvider.groq => 'groq-business-data-v3',
        AssistantProvider.kimi => 'kimi-business-data-v1',
        AssistantProvider.deepSeek => 'deepseek-business-data-v1',
      };

  static Future<void> saveApiKey({
    required ApplicationSession store,
    required AssistantProvider provider,
    required String apiKey,
  }) async {
    _requireSupportedClient();
    final normalized = apiKey.trim();
    if (normalized.isEmpty || normalized.length > 4096) {
      throw const AssistantConversationException(
        'invalid_api_key',
        'Enter a provider API key no longer than 4096 characters.',
      );
    }
    await _secureStorage.write(
      key: _credentialKey(store, provider),
      value: normalized,
    );
  }

  static Future<String?> readApiKey({
    required ApplicationSession store,
    required AssistantProvider provider,
  }) async {
    _requireSupportedClient();
    final value = await _secureStorage.read(
      key: _credentialKey(store, provider),
    );
    if (value == null || value.trim().isEmpty) return null;
    return value;
  }

  static Future<bool> hasApiKey({
    required ApplicationSession store,
    required AssistantProvider provider,
  }) async =>
      (await readApiKey(store: store, provider: provider)) != null;

  static Future<void> deleteApiKey({
    required ApplicationSession store,
    required AssistantProvider provider,
  }) async {
    _requireSupportedClient();
    await _secureStorage.delete(key: _credentialKey(store, provider));
  }

  static Future<void> savePreferredProvider({
    required ApplicationSession store,
    required AssistantProvider provider,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _providerPreferenceKey(store),
      provider.storageId,
    );
  }

  static Future<AssistantProvider?> readPreferredProvider({
    required ApplicationSession store,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final storageId = preferences.getString(_providerPreferenceKey(store));
    for (final provider in AssistantProvider.values) {
      if (provider.storageId == storageId) return provider;
    }
    return null;
  }

  static Future<void> saveSelectedModel({
    required ApplicationSession store,
    required AssistantProvider provider,
    required String model,
  }) async {
    final normalized = model.trim();
    if (normalized.isEmpty ||
        normalized.length > 120 ||
        normalized.contains(RegExp(r'[\x00-\x1F\x7F]'))) {
      throw const AssistantConversationException(
        'invalid_model',
        'Enter a valid model name of up to 120 characters.',
      );
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
        _modelPreferenceKey(store, provider), normalized);
  }

  static Future<String?> readSelectedModel({
    required ApplicationSession store,
    required AssistantProvider provider,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_modelPreferenceKey(store, provider));
  }

  static Future<void> saveThinkingLevel({
    required ApplicationSession store,
    required AssistantProvider provider,
    required AssistantThinkingLevel level,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _thinkingPreferenceKey(store, provider),
      level.storageId,
    );
  }

  static Future<AssistantThinkingLevel> readThinkingLevel({
    required ApplicationSession store,
    required AssistantProvider provider,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    return AssistantThinkingLevel.fromStorage(
      preferences.getString(_thinkingPreferenceKey(store, provider)),
    );
  }

  static Future<bool> hasBusinessDataConsent({
    required ApplicationSession store,
    required AssistantProvider provider,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_consentKey(store, provider)) ==
        _consentRevision(provider);
  }

  /// Call with [granted] only after showing the provider's data-use disclosure.
  static Future<void> setBusinessDataConsent({
    required ApplicationSession store,
    required AssistantProvider provider,
    required bool granted,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final key = _consentKey(store, provider);
    if (granted) {
      await preferences.setString(key, _consentRevision(provider));
    } else {
      await preferences.remove(key);
    }
  }

  static String dataUseDisclosure(AssistantProvider provider) =>
      'If you enable business-data sharing, Ventio sends your question, recent '
      'messages in the active chat, any text files you attach, and only the read-only report results '
      'needed to answer it directly to '
      '${provider.label}. Review that provider\'s terms and data controls. '
      'Depending on the provider, plan, and account settings, requests may be '
      'retained or used to improve services, and API usage may be billed under '
      'your provider account. Your ${provider.label} API key is '
      'sent directly to that provider for authentication. Ventio does not send '
      'the database file or Ventio login credentials.';

  static void _requireSupportedClient() {
    if (kIsWeb) {
      throw const AssistantConversationException(
        'web_provider_setup_unavailable',
        'AI provider keys are not enabled in Ventio Web until a secure provider gateway is configured.',
      );
    }
  }

  static String _credentialKey(ApplicationSession store, AssistantProvider provider) =>
      'ventio_assistant_${provider.storageId}_${_scopeHash(store)}';

  static String _consentKey(ApplicationSession store, AssistantProvider provider) =>
      'ventio_assistant_consent_${provider.storageId}_${_scopeHash(store)}';

  static String _providerPreferenceKey(ApplicationSession store) =>
      'ventio_assistant_provider_${_scopeHash(store)}';

  static String _modelPreferenceKey(
    ApplicationSession store,
    AssistantProvider provider,
  ) =>
      'ventio_assistant_model_${provider.storageId}_${_scopeHash(store)}';

  static String _thinkingPreferenceKey(
    ApplicationSession store,
    AssistantProvider provider,
  ) =>
      'ventio_assistant_thinking_${provider.storageId}_${_scopeHash(store)}';

  static String _scopeHash(ApplicationSession store) {
    final user = store.security.activeUser;
    final userId = user?.id.trim() ?? '';
    final storeId = store.runtime.identity.storeId.trim();
    if (user == null || !user.isActive || userId.isEmpty || storeId.isEmpty) {
      throw const AssistantConversationException(
        'active_user_required',
        'Sign in to Ventio and select a store before configuring an AI provider.',
      );
    }
    return sha256.convert(utf8.encode('$storeId\u001f$userId')).toString();
  }
}
