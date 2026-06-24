import '../storage/sqlite/sqlite_migration_manager.dart';

class SqlEditorResult {
  const SqlEditorResult({
    required this.statement,
    required this.isQuery,
    required this.rows,
    required this.message,
  });

  final String statement;
  final bool isQuery;
  final List<Map<String, Object?>> rows;
  final String message;
}

class DatabaseSqlEditorService {
  DatabaseSqlEditorService._();

  static const int defaultLimit = 200;
  static const int maxResultRows = 500;

  static const List<String> blockedKeywords = <String>[
    'drop',
    'alter',
    'attach',
    'detach',
    'vacuum',
    'reindex',
    'pragma writable_schema',
    'pragma journal_mode',
    'pragma synchronous',
  ];

  static bool get isAvailable => SqliteMigrationManager.database != null;

  static List<String> splitStatements(String script) {
    final statements = <String>[];
    final buffer = StringBuffer();
    var inSingleQuote = false;
    var inDoubleQuote = false;
    var inLineComment = false;
    var inBlockComment = false;

    for (var i = 0; i < script.length; i++) {
      final char = script[i];
      final next = i + 1 < script.length ? script[i + 1] : '';

      if (inLineComment) {
        buffer.write(char);
        if (char == '\n') inLineComment = false;
        continue;
      }
      if (inBlockComment) {
        buffer.write(char);
        if (char == '*' && next == '/') {
          buffer.write(next);
          i++;
          inBlockComment = false;
        }
        continue;
      }

      if (!inSingleQuote && !inDoubleQuote && char == '-' && next == '-') {
        buffer.write(char);
        buffer.write(next);
        i++;
        inLineComment = true;
        continue;
      }
      if (!inSingleQuote && !inDoubleQuote && char == '/' && next == '*') {
        buffer.write(char);
        buffer.write(next);
        i++;
        inBlockComment = true;
        continue;
      }

      if (char == "'" && !inDoubleQuote) {
        buffer.write(char);
        if (inSingleQuote && next == "'") {
          buffer.write(next);
          i++;
        } else {
          inSingleQuote = !inSingleQuote;
        }
        continue;
      }
      if (char == '"' && !inSingleQuote) {
        buffer.write(char);
        inDoubleQuote = !inDoubleQuote;
        continue;
      }

      if (char == ';' && !inSingleQuote && !inDoubleQuote) {
        final statement = buffer.toString().trim();
        if (statement.isNotEmpty) statements.add(statement);
        buffer.clear();
        continue;
      }
      buffer.write(char);
    }

    final tail = buffer.toString().trim();
    if (tail.isNotEmpty) statements.add(tail);
    return statements;
  }

  static String? validateStatement(String statement, {required bool allowWrites}) {
    final normalized = _normalizedSql(statement);
    if (normalized.isEmpty) return 'SQL statement is empty.';

    for (final keyword in blockedKeywords) {
      if (_containsKeyword(normalized, keyword)) {
        return 'Blocked command: $keyword';
      }
    }

    final first = normalized.split(' ').first;
    final readOnly = _isReadOnlyFirstKeyword(first);
    if (!allowWrites && !readOnly) {
      return 'Write statements require Execute mode.';
    }

    const allowedWrites = <String>{'insert', 'update', 'delete', 'replace'};
    if (!readOnly && !allowedWrites.contains(first)) {
      return 'Only SELECT, WITH, EXPLAIN, INSERT, UPDATE, DELETE, and REPLACE are allowed.';
    }

    return null;
  }

  static Future<List<SqlEditorResult>> runScript(String script, {required bool allowWrites}) async {
    final db = SqliteMigrationManager.database;
    if (db == null) {
      throw StateError('SQLite database is not available.');
    }

    final statements = splitStatements(script);
    if (statements.isEmpty) {
      throw ArgumentError('SQL statement is empty.');
    }

    final results = <SqlEditorResult>[];
    await db.transaction(() async {
      for (final statement in statements) {
        final validationError = validateStatement(statement, allowWrites: allowWrites);
        if (validationError != null) throw ArgumentError(validationError);
        final isQuery = isQueryStatement(statement);
        if (isQuery) {
          final rows = await db.customSelect(_withPreviewLimit(statement)).get();
          results.add(SqlEditorResult(
            statement: statement,
            isQuery: true,
            rows: rows.map((row) => Map<String, Object?>.from(row.data)).toList(growable: false),
            message: '${rows.length} row(s)',
          ));
        } else {
          await db.customStatement(statement);
          results.add(SqlEditorResult(
            statement: statement,
            isQuery: false,
            rows: const <Map<String, Object?>>[],
            message: 'Statement executed successfully.',
          ));
        }
      }
    });
    return results;
  }

  static bool isQueryStatement(String statement) {
    final first = _normalizedSql(statement).split(' ').first;
    return _isReadOnlyFirstKeyword(first);
  }

  static bool _isReadOnlyFirstKeyword(String first) => first == 'select' || first == 'with' || first == 'explain';

  static String _withPreviewLimit(String statement) {
    final normalized = _normalizedSql(statement);
    if (RegExp(r'\blimit\s+\d+', caseSensitive: false).hasMatch(normalized)) return statement;
    if (normalized.startsWith('explain')) return statement;
    return '$statement LIMIT $defaultLimit';
  }

  static String _normalizedSql(String sql) => sql
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), ' ')
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('--'))
      .join(' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .toLowerCase();

  static bool _containsKeyword(String normalizedSql, String keyword) {
    if (keyword.contains(' ')) return normalizedSql.contains(keyword);
    return RegExp(r'(^|\s)' + RegExp.escape(keyword) + r'(\s|$|\()').hasMatch(normalizedSql);
  }
}
