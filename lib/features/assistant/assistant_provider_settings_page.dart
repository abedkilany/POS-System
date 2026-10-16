import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/utils/responsive.dart';
import 'package:ventio/core/contracts/application_session.dart';
import 'assistant_provider.dart';
import 'assistant_provider_settings_service.dart';
import 'assistant_provider_transport.dart';

/// Provider configuration embedded in Ventio settings.
///
/// Browser key entry is intentionally unavailable until Ventio has a trusted
/// provider gateway. Native clients store the user's key in platform secure
/// storage and send requests directly to the selected provider.
class AssistantProviderSettingsPage extends StatefulWidget {
  const AssistantProviderSettingsPage({super.key, required this.store});

  final ApplicationSession store;

  @override
  State<AssistantProviderSettingsPage> createState() =>
      _AssistantProviderSettingsPageState();
}

class _AssistantProviderSettingsPageState
    extends State<AssistantProviderSettingsPage> {
  final TextEditingController _modelController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  AssistantProvider _provider = AssistantProvider.gemini;
  bool _loading = true;
  bool _busy = false;
  bool _hasApiKey = false;
  bool _shareBusinessData = false;
  bool _loadingModels = false;
  List<String> _availableModels = const <String>[];
  AssistantThinkingLevel _thinkingLevel = AssistantThinkingLevel.automatic;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void didUpdateWidget(covariant AssistantProviderSettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) _loadSettings();
  }

  @override
  void dispose() {
    _modelController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _loading = true);
    try {
      final selected =
          await AssistantProviderSettingsService.readPreferredProvider(
                  store: widget.store) ??
              AssistantProvider.gemini;
      final model = await AssistantProviderSettingsService.readSelectedModel(
        store: widget.store,
        provider: selected,
      );
      final hasKey = kIsWeb
          ? false
          : await AssistantProviderSettingsService.hasApiKey(
              store: widget.store,
              provider: selected,
            );
      final consent =
          await AssistantProviderSettingsService.hasBusinessDataConsent(
        store: widget.store,
        provider: selected,
      );
      final thinkingLevel =
          await AssistantProviderSettingsService.readThinkingLevel(
        store: widget.store,
        provider: selected,
      );
      if (!mounted) return;
      setState(() {
        _provider = selected;
        _modelController.text = model ?? '';
        _hasApiKey = hasKey;
        _shareBusinessData = consent;
        _thinkingLevel = thinkingLevel;
        _availableModels = const <String>[];
        _loading = false;
      });
      if (hasKey) _refreshModels();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showMessage(_friendlyError(error));
    }
  }

  Future<void> _selectProvider(AssistantProvider? provider) async {
    if (provider == null || provider == _provider || _busy || _loadingModels) {
      return;
    }
    setState(() {
      _provider = provider;
      _modelController.clear();
      _apiKeyController.clear();
      _hasApiKey = false;
      _shareBusinessData = false;
      _busy = true;
    });
    try {
      final model = await AssistantProviderSettingsService.readSelectedModel(
        store: widget.store,
        provider: provider,
      );
      final hasKey = await AssistantProviderSettingsService.hasApiKey(
        store: widget.store,
        provider: provider,
      );
      final consent =
          await AssistantProviderSettingsService.hasBusinessDataConsent(
        store: widget.store,
        provider: provider,
      );
      final thinkingLevel =
          await AssistantProviderSettingsService.readThinkingLevel(
        store: widget.store,
        provider: provider,
      );
      await AssistantProviderSettingsService.savePreferredProvider(
        store: widget.store,
        provider: provider,
      );
      if (!mounted) return;
      setState(() {
        _modelController.text = model ?? '';
        _hasApiKey = hasKey;
        _shareBusinessData = consent;
        _thinkingLevel = thinkingLevel;
        _availableModels = const <String>[];
        _busy = false;
      });
      if (hasKey) _refreshModels();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showMessage(_friendlyError(error));
    }
  }

  Future<void> _save() async {
    final tr = AppLocalizations.of(context);
    final model = _modelController.text.trim();
    final apiKey = _apiKeyController.text.trim();
    if (model.isEmpty) {
      _showMessage(tr.text('assistant_missing_model'));
      return;
    }
    if (apiKey.isEmpty && !_hasApiKey) {
      _showMessage(tr.text('assistant_missing_api_key'));
      return;
    }
    setState(() => _busy = true);
    try {
      await AssistantProviderSettingsService.saveSelectedModel(
        store: widget.store,
        provider: _provider,
        model: model,
      );
      await AssistantProviderSettingsService.saveThinkingLevel(
        store: widget.store,
        provider: _provider,
        level: _thinkingLevel,
      );
      if (apiKey.isNotEmpty) {
        await AssistantProviderSettingsService.saveApiKey(
          store: widget.store,
          provider: _provider,
          apiKey: apiKey,
        );
      }
      await AssistantProviderSettingsService.savePreferredProvider(
        store: widget.store,
        provider: _provider,
      );
      if (!mounted) return;
      setState(() {
        _hasApiKey = _hasApiKey || apiKey.isNotEmpty;
        _apiKeyController.clear();
        _busy = false;
      });
      _showMessage(tr.text('assistant_saved'));
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showMessage(_friendlyError(error));
    }
  }

  Future<void> _refreshModels() async {
    if (_loadingModels || _busy) return;
    final requestedProvider = _provider;
    final typedKey = _apiKeyController.text.trim();
    setState(() => _loadingModels = true);
    AssistantProviderTransport? transport;
    try {
      final key = typedKey.isNotEmpty
          ? typedKey
          : await AssistantProviderSettingsService.readApiKey(
              store: widget.store,
              provider: _provider,
            );
      if (key == null || key.isEmpty) {
        throw const AssistantConversationException(
          'api_key_missing',
          'Connect an API key for the selected AI provider.',
        );
      }
      transport = AssistantProviderTransport();
      final models = await transport.listModels(
        provider: requestedProvider,
        apiKey: key,
      );
      if (!mounted) return;
      if (_provider != requestedProvider) return;
      setState(() {
        _availableModels = models;
        if (_modelController.text.trim().isEmpty) {
          _modelController.text = switch (_provider) {
            AssistantProvider.kimi when models.contains('kimi-k3') => 'kimi-k3',
            AssistantProvider.deepSeek when models.contains('deepseek-flash') =>
              'deepseek-flash',
            _ => models.first,
          };
        }
        _loadingModels = false;
      });
      _showMessage(AppLocalizations.of(context).format(
        'assistant_models_loaded',
        {'count': models.length},
      ));
    } on Object catch (error) {
      if (!mounted) return;
      if (_provider != requestedProvider) return;
      setState(() => _loadingModels = false);
      _showMessage(_friendlyError(error));
    } finally {
      transport?.close();
    }
  }

  Future<void> _removeApiKey() async {
    setState(() => _busy = true);
    try {
      await AssistantProviderSettingsService.deleteApiKey(
        store: widget.store,
        provider: _provider,
      );
      if (!mounted) return;
      setState(() {
        _hasApiKey = false;
        _apiKeyController.clear();
        _busy = false;
      });
      _showMessage(AppLocalizations.of(context).text('assistant_key_removed'));
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showMessage(_friendlyError(error));
    }
  }

  Future<void> _setConsent(bool value) async {
    setState(() => _shareBusinessData = value);
    try {
      await AssistantProviderSettingsService.setBusinessDataConsent(
        store: widget.store,
        provider: _provider,
        granted: value,
      );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _shareBusinessData = !value);
      _showMessage(_friendlyError(error));
    }
  }

  String _friendlyError(Object error) {
    final tr = AppLocalizations.of(context);
    if (error is AssistantConversationException) {
      return switch (error.code) {
        'active_user_required' => tr.text('assistant_sign_in_required'),
        'web_provider_setup_unavailable' => tr.text('assistant_web_block_body'),
        'api_key_missing' => tr.text('assistant_missing_api_key'),
        'provider_authentication_failed' =>
          tr.text('assistant_error_invalid_key'),
        'provider_access_denied' => tr.text('assistant_error_access_denied'),
        'provider_rate_limited' =>
          error.diagnostic?.toLowerCase().contains('credit') == true ||
                  error.diagnostic?.toLowerCase().contains('quota') == true
              ? tr.text('assistant_error_no_credits')
              : tr.text('assistant_error_rate_limited'),
        'provider_unavailable' =>
          tr.text('assistant_error_provider_unavailable'),
        'provider_timeout' => tr.text('assistant_error_timeout'),
        'provider_connection_failed' => tr.text('assistant_error_connection'),
        'provider_models_empty' => tr.text('assistant_models_empty'),
        'provider_request_rejected' ||
        'invalid_model' =>
          tr.text('assistant_error_model_rejected'),
        _ => tr.text('assistant_action_failed'),
      };
    }
    return tr.text('assistant_action_failed');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (kIsWeb) {
      return ListView(
        padding: VentioResponsive.pageInsets(context),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.lock_outline),
              title: Text(tr.text('assistant_web_block_title')),
              subtitle: Text(tr.text('assistant_web_block_body')),
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: VentioResponsive.pageInsets(context),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<AssistantProvider>(
                  initialValue: _provider,
                  decoration: InputDecoration(
                    labelText: tr.text('assistant_provider'),
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    for (final provider in AssistantProvider.values)
                      DropdownMenuItem(
                        value: provider,
                        child: Text(provider.label),
                      ),
                  ],
                  onChanged: _busy || _loadingModels ? null : _selectProvider,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _modelController,
                  enabled: !_busy && !_loadingModels,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    labelText: tr.text('assistant_model'),
                    hintText: tr.text('assistant_model_hint'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        tr.text('assistant_models_helper'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed:
                          _busy || _loadingModels ? null : _refreshModels,
                      icon: _loadingModels
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                      label: Text(tr.text('assistant_models_refresh')),
                    ),
                  ],
                ),
                if (_availableModels.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _availableModels.contains(_modelController.text)
                        ? _modelController.text
                        : null,
                    decoration: InputDecoration(
                      labelText: tr.text('assistant_available_models'),
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      for (final model in _availableModels)
                        DropdownMenuItem(value: model, child: Text(model)),
                    ],
                    onChanged: _busy
                        ? null
                        : (model) {
                            if (model != null) {
                              setState(() => _modelController.text = model);
                            }
                          },
                  ),
                ],
                const SizedBox(height: 16),
                DropdownButtonFormField<AssistantThinkingLevel>(
                  initialValue: _thinkingLevel,
                  decoration: InputDecoration(
                    labelText: tr.text('assistant_thinking_level'),
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    for (final level in AssistantThinkingLevel.values)
                      DropdownMenuItem(
                        value: level,
                        child: Text(
                            tr.text('assistant_thinking_${level.storageId}')),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (level) {
                          if (level != null) {
                            setState(() => _thinkingLevel = level);
                          }
                        },
                ),
                const SizedBox(height: 6),
                Text(
                  tr.text('assistant_thinking_note'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _apiKeyController,
                  enabled: !_busy && !_loadingModels,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    labelText: tr.text('assistant_api_key'),
                    hintText: _hasApiKey
                        ? tr.text('assistant_key_connected')
                        : tr.text('assistant_api_key_hint'),
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _refreshModels(),
                ),
                const SizedBox(height: 8),
                Text(
                  tr.text('assistant_local_key_storage'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy || _loadingModels ? null : _save,
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(tr.text('assistant_save_provider')),
                ),
                if (_hasApiKey) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _busy || _loadingModels ? null : _removeApiKey,
                    icon: const Icon(Icons.delete_outline),
                    label: Text(tr.text('assistant_remove_key')),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.privacy_tip_outlined),
                title: Text(tr.text('assistant_data_disclosure_title')),
                subtitle: Text(tr.text('assistant_data_disclosure_body')),
              ),
              SwitchListTile.adaptive(
                value: _shareBusinessData,
                onChanged: _busy ? null : _setConsent,
                title: Text(tr.text('assistant_data_sharing')),
                subtitle: Text(
                  tr.format('assistant_data_sharing_provider',
                      {'provider': _provider.label}),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
