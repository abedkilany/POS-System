import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';
import 'package:ventio/core/contracts/application_session.dart';
import 'assistant_chat_history_store.dart';

class AssistantChatHistoryDialog extends StatefulWidget {
  const AssistantChatHistoryDialog({
    super.key,
    required this.store,
    required this.historyStore,
  });

  final ApplicationSession store;
  final AssistantChatHistoryStore historyStore;

  static Future<String?> show(
    BuildContext context, {
    required ApplicationSession store,
    required AssistantChatHistoryStore historyStore,
  }) =>
      showDialog<String>(
        context: context,
        builder: (_) => AssistantChatHistoryDialog(
          store: store,
          historyStore: historyStore,
        ),
      );

  @override
  State<AssistantChatHistoryDialog> createState() =>
      _AssistantChatHistoryDialogState();
}

class _AssistantChatHistoryDialogState
    extends State<AssistantChatHistoryDialog> {
  List<AssistantSavedConversation> _conversations =
      const <AssistantSavedConversation>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final conversations =
          await widget.historyStore.listConversations(widget.store);
      if (!mounted) return;
      setState(() {
        _conversations = conversations;
        _loading = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = AppLocalizations.of(context).text('assistant_history_failed');
      });
    }
  }

  Future<void> _rename(AssistantSavedConversation conversation) async {
    final tr = AppLocalizations.of(context);
    final controller = TextEditingController(text: conversation.title);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr.text('assistant_history_rename')),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 100,
          textInputAction: TextInputAction.done,
          onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
          decoration: InputDecoration(
            labelText: tr.text('assistant_history_name_field'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(tr.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(tr.text('save')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title == null || title.trim().isEmpty || !mounted) return;
    try {
      await widget.historyStore.renameConversation(
        widget.store,
        conversationId: conversation.id,
        title: title,
      );
      await _reload();
    } on Object {
      if (!mounted) return;
      setState(() => _error = tr.text('assistant_history_failed'));
    }
  }

  Future<void> _delete(AssistantSavedConversation conversation) async {
    final tr = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr.text('assistant_history_delete')),
        content: Text(tr.text('assistant_history_delete_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr.text('delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.historyStore.deleteConversation(
        widget.store,
        conversationId: conversation.id,
      );
      await _reload();
    } on Object {
      if (!mounted) return;
      setState(() => _error = tr.text('assistant_history_failed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(tr.text('assistant_history_title')),
      content: SizedBox(
        width: 560,
        height: 440,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!, textAlign: TextAlign.center))
                : _conversations.isEmpty
                    ? Center(
                        child: Text(
                          tr.text('assistant_history_empty'),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.separated(
                        itemCount: _conversations.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final conversation = _conversations[index];
                          return ListTile(
                            leading: const Icon(Icons.forum_outlined),
                            title: Text(
                              conversation.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(tr.format(
                              'assistant_history_turn_count',
                              {'count': conversation.turnCount.toString()},
                            )),
                            onTap: () =>
                                Navigator.of(context).pop(conversation.id),
                            trailing: PopupMenuButton<String>(
                              tooltip: tr.text('assistant_history_options'),
                              onSelected: (action) {
                                if (action == 'rename') {
                                  _rename(conversation);
                                } else if (action == 'delete') {
                                  _delete(conversation);
                                }
                              },
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: 'rename',
                                  child:
                                      Text(tr.text('assistant_history_rename')),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text(tr.text('delete')),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr.text('close')),
        ),
      ],
    );
  }
}
