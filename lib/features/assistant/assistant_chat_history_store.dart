import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../../data/app_store.dart';
import '../../core/storage/sqlite/sqlite_migration_manager.dart';
import '../../core/storage/sqlite/ventio_drift_database.dart';
import 'assistant_provider.dart';

class AssistantSavedConversation {
  const AssistantSavedConversation({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.turnCount,
  });

  final String id;
  final String title;
  final String updatedAt;
  final int turnCount;
}

class AssistantSavedExchange {
  const AssistantSavedExchange({
    required this.id,
    required this.userContent,
    required this.assistantContent,
    required this.assistantStatus,
    required this.attachmentName,
    required this.reports,
  });

  final String id;
  final String userContent;
  final String assistantContent;
  final String assistantStatus;
  final String attachmentName;
  final List<AssistantJsonMap> reports;
}

class AssistantPendingExchange {
  const AssistantPendingExchange({
    required this.conversationId,
    required this.conversationTitle,
    required this.exchangeId,
  });

  final String conversationId;
  final String conversationTitle;
  final String exchangeId;
}

/// Stores chat history locally, scoped to the signed-in Ventio user and store.
/// Provider keys and attached file contents are deliberately never persisted.
class AssistantChatHistoryStore {
  static final Random _random = Random.secure();

  VentioDriftDatabase get _database {
    final database = SqliteMigrationManager.database;
    if (database == null) {
      throw StateError('Ventio local database is not available.');
    }
    return database;
  }

  Future<List<AssistantSavedConversation>> listConversations(
    AppStore store,
  ) async {
    final scopeHash = _scopeHash(store);
    final rows = await _database.customSelect(
      '''
      SELECT c.id, c.title, c.updated_at AS updatedAt,
             COUNT(t.id) AS turnCount
      FROM assistant_conversations c
      LEFT JOIN assistant_chat_turns t ON t.conversation_id = c.id
      WHERE c.scope_hash = ?
      GROUP BY c.id
      HAVING COUNT(t.id) > 0
      ORDER BY c.updated_at DESC, c.created_at DESC
      ''',
      variables: <Variable<Object>>[Variable<String>(scopeHash)],
    ).get();
    return rows
        .map((row) => AssistantSavedConversation(
              id: row.read<String>('id'),
              title: row.read<String>('title'),
              updatedAt: row.read<String>('updatedAt'),
              turnCount: row.read<int>('turnCount'),
            ))
        .toList(growable: false);
  }

  Future<List<AssistantSavedExchange>> loadConversation(
    AppStore store, {
    required String conversationId,
  }) async {
    final scopeHash = _scopeHash(store);
    final db = _database;
    final conversation = await db.customSelect(
      'SELECT id FROM assistant_conversations WHERE id = ? AND scope_hash = ? LIMIT 1',
      variables: <Variable<Object>>[
        Variable<String>(conversationId),
        Variable<String>(scopeHash),
      ],
    ).get();
    if (conversation.isEmpty) return const <AssistantSavedExchange>[];

    final now = DateTime.now().toUtc().toIso8601String();
    await db.customUpdate(
      '''
      UPDATE assistant_chat_turns
      SET assistant_status = 'interrupted', updated_at = ?
      WHERE conversation_id = ? AND scope_hash = ?
        AND assistant_status = 'pending'
      ''',
      variables: <Variable<Object>>[
        Variable<String>(now),
        Variable<String>(conversationId),
        Variable<String>(scopeHash),
      ],
    );
    final rows = await db.customSelect(
      '''
      SELECT id, user_content AS userContent,
             assistant_content AS assistantContent,
             assistant_status AS assistantStatus,
             attachment_name AS attachmentName,
             reports_json AS reportsJson
      FROM assistant_chat_turns
      WHERE conversation_id = ? AND scope_hash = ?
      ORDER BY created_at ASC, rowid ASC
      ''',
      variables: <Variable<Object>>[
        Variable<String>(conversationId),
        Variable<String>(scopeHash),
      ],
    ).get();
    return rows.map(_exchangeFromRow).toList(growable: false);
  }

  Future<AssistantPendingExchange> beginExchange(
    AppStore store, {
    String? conversationId,
    required String userContent,
    String? attachmentName,
  }) async {
    final scopeHash = _scopeHash(store);
    final db = _database;
    final now = DateTime.now().toUtc().toIso8601String();
    var resolvedConversationId = conversationId?.trim() ?? '';
    var title = '';
    if (resolvedConversationId.isNotEmpty) {
      final existing = await db.customSelect(
        'SELECT title FROM assistant_conversations WHERE id = ? AND scope_hash = ? LIMIT 1',
        variables: <Variable<Object>>[
          Variable<String>(resolvedConversationId),
          Variable<String>(scopeHash),
        ],
      ).get();
      if (existing.isEmpty) resolvedConversationId = '';
      if (existing.isNotEmpty) title = existing.first.read<String>('title');
    }

    if (resolvedConversationId.isEmpty) {
      resolvedConversationId = _newId('conversation');
      title = _titleFromQuestion(userContent);
      await db.customInsert(
        '''
        INSERT INTO assistant_conversations
          (id, scope_hash, title, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?)
        ''',
        variables: <Variable<Object>>[
          Variable<String>(resolvedConversationId),
          Variable<String>(scopeHash),
          Variable<String>(title),
          Variable<String>(now),
          Variable<String>(now),
        ],
      );
    }

    final exchangeId = _newId('turn');
    await db.customInsert(
      '''
      INSERT INTO assistant_chat_turns
        (id, conversation_id, scope_hash, user_content, assistant_content,
         assistant_status, attachment_name, reports_json, created_at, updated_at)
      VALUES (?, ?, ?, ?, '', 'pending', ?, '[]', ?, ?)
      ''',
      variables: <Variable<Object>>[
        Variable<String>(exchangeId),
        Variable<String>(resolvedConversationId),
        Variable<String>(scopeHash),
        Variable<String>(userContent),
        Variable<String>(attachmentName ?? ''),
        Variable<String>(now),
        Variable<String>(now),
      ],
    );
    await db.customUpdate(
      'UPDATE assistant_conversations SET updated_at = ? WHERE id = ? AND scope_hash = ?',
      variables: <Variable<Object>>[
        Variable<String>(now),
        Variable<String>(resolvedConversationId),
        Variable<String>(scopeHash),
      ],
    );
    return AssistantPendingExchange(
      conversationId: resolvedConversationId,
      conversationTitle: title,
      exchangeId: exchangeId,
    );
  }

  Future<AssistantPendingExchange?> retryExchange(
    AppStore store, {
    required String exchangeId,
  }) async {
    final scopeHash = _scopeHash(store);
    final db = _database;
    final rows = await db.customSelect(
      '''
      SELECT t.conversation_id AS conversationId,
             c.title AS conversationTitle
      FROM assistant_chat_turns t
      JOIN assistant_conversations c ON c.id = t.conversation_id
      WHERE t.id = ? AND t.scope_hash = ? AND c.scope_hash = ?
      LIMIT 1
      ''',
      variables: <Variable<Object>>[
        Variable<String>(exchangeId),
        Variable<String>(scopeHash),
        Variable<String>(scopeHash),
      ],
    ).get();
    if (rows.isEmpty) return null;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.customUpdate(
      '''
      UPDATE assistant_chat_turns
      SET assistant_content = '', assistant_status = 'pending',
          reports_json = '[]', updated_at = ?
      WHERE id = ? AND scope_hash = ?
      ''',
      variables: <Variable<Object>>[
        Variable<String>(now),
        Variable<String>(exchangeId),
        Variable<String>(scopeHash),
      ],
    );
    final conversationId = rows.first.read<String>('conversationId');
    await db.customUpdate(
      'UPDATE assistant_conversations SET updated_at = ? WHERE id = ? AND scope_hash = ?',
      variables: <Variable<Object>>[
        Variable<String>(now),
        Variable<String>(conversationId),
        Variable<String>(scopeHash),
      ],
    );
    return AssistantPendingExchange(
      conversationId: conversationId,
      conversationTitle: rows.first.read<String>('conversationTitle'),
      exchangeId: exchangeId,
    );
  }

  Future<void> completeExchange(
    AppStore store, {
    required String exchangeId,
    required String assistantContent,
    required List<AssistantJsonMap> reports,
  }) async {
    final scopeHash = _scopeHash(store);
    final now = DateTime.now().toUtc().toIso8601String();
    final reportsJson = jsonEncode(reports);
    await _database.customUpdate(
      '''
      UPDATE assistant_chat_turns
      SET assistant_content = ?, assistant_status = 'complete',
          reports_json = ?, updated_at = ?
      WHERE id = ? AND scope_hash = ?
      ''',
      variables: <Variable<Object>>[
        Variable<String>(assistantContent),
        Variable<String>(reportsJson),
        Variable<String>(now),
        Variable<String>(exchangeId),
        Variable<String>(scopeHash),
      ],
    );
    await _touchConversation(store, exchangeId, now);
  }

  Future<void> failExchange(
    AppStore store, {
    required String exchangeId,
    required String friendlyMessage,
  }) async {
    final scopeHash = _scopeHash(store);
    final now = DateTime.now().toUtc().toIso8601String();
    await _database.customUpdate(
      '''
      UPDATE assistant_chat_turns
      SET assistant_content = ?, assistant_status = 'failed',
          reports_json = '[]', updated_at = ?
      WHERE id = ? AND scope_hash = ?
      ''',
      variables: <Variable<Object>>[
        Variable<String>(friendlyMessage),
        Variable<String>(now),
        Variable<String>(exchangeId),
        Variable<String>(scopeHash),
      ],
    );
    await _touchConversation(store, exchangeId, now);
  }

  Future<void> renameConversation(
    AppStore store, {
    required String conversationId,
    required String title,
  }) async {
    final normalized = title.trim();
    if (normalized.isEmpty || normalized.length > 100) {
      throw ArgumentError(
          'Conversation title must contain 1 to 100 characters.');
    }
    final now = DateTime.now().toUtc().toIso8601String();
    await _database.customUpdate(
      'UPDATE assistant_conversations SET title = ?, updated_at = ? WHERE id = ? AND scope_hash = ?',
      variables: <Variable<Object>>[
        Variable<String>(normalized),
        Variable<String>(now),
        Variable<String>(conversationId),
        Variable<String>(_scopeHash(store)),
      ],
    );
  }

  Future<void> deleteConversation(
    AppStore store, {
    required String conversationId,
  }) async {
    await _database.customUpdate(
      'DELETE FROM assistant_conversations WHERE id = ? AND scope_hash = ?',
      variables: <Variable<Object>>[
        Variable<String>(conversationId),
        Variable<String>(_scopeHash(store)),
      ],
    );
  }

  Future<String?> conversationTitle(
    AppStore store, {
    required String conversationId,
  }) async {
    final rows = await _database.customSelect(
      'SELECT title FROM assistant_conversations WHERE id = ? AND scope_hash = ? LIMIT 1',
      variables: <Variable<Object>>[
        Variable<String>(conversationId),
        Variable<String>(_scopeHash(store)),
      ],
    ).get();
    return rows.isEmpty ? null : rows.first.read<String>('title');
  }

  Future<void> _touchConversation(
    AppStore store,
    String exchangeId,
    String updatedAt,
  ) async {
    final scopeHash = _scopeHash(store);
    final rows = await _database.customSelect(
      'SELECT conversation_id AS conversationId FROM assistant_chat_turns WHERE id = ? AND scope_hash = ? LIMIT 1',
      variables: <Variable<Object>>[
        Variable<String>(exchangeId),
        Variable<String>(scopeHash),
      ],
    ).get();
    if (rows.isEmpty) return;
    await _database.customUpdate(
      'UPDATE assistant_conversations SET updated_at = ? WHERE id = ? AND scope_hash = ?',
      variables: <Variable<Object>>[
        Variable<String>(updatedAt),
        Variable<String>(rows.first.read<String>('conversationId')),
        Variable<String>(scopeHash),
      ],
    );
  }

  static AssistantSavedExchange _exchangeFromRow(QueryRow row) {
    final reports = <AssistantJsonMap>[];
    try {
      final decoded = jsonDecode(row.read<String>('reportsJson'));
      if (decoded is List) {
        for (final value in decoded) {
          if (value is Map) {
            reports.add(Map<String, Object?>.from(value));
          }
        }
      }
    } on Object {
      // Keep the visible conversation available even if an old report payload
      // cannot be decoded by a newer build.
    }
    return AssistantSavedExchange(
      id: row.read<String>('id'),
      userContent: row.read<String>('userContent'),
      assistantContent: row.read<String>('assistantContent'),
      assistantStatus: row.read<String>('assistantStatus'),
      attachmentName: row.read<String>('attachmentName'),
      reports: List<AssistantJsonMap>.unmodifiable(reports),
    );
  }

  static String _scopeHash(AppStore store) {
    final user = store.security.activeUser;
    final userId = user?.id.trim() ?? '';
    final storeId = store.runtime.identity.storeId.trim();
    if (user == null || !user.isActive || userId.isEmpty || storeId.isEmpty) {
      throw StateError('Sign in to Ventio and select a store first.');
    }
    return sha256.convert(utf8.encode('$storeId\u001f$userId')).toString();
  }

  static String _titleFromQuestion(String question) {
    final normalized = question.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= 72) return normalized;
    return '${normalized.substring(0, 69).trimRight()}…';
  }

  static String _newId(String prefix) =>
      'assistant_${prefix}_${DateTime.now().microsecondsSinceEpoch}_${_random.nextInt(1 << 32)}';
}
