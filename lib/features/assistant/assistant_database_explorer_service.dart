import 'package:drift/drift.dart';

import '../../core/storage/sqlite/sqlite_migration_manager.dart';
import '../../core/storage/sqlite/ventio_drift_database.dart';
import '../../data/app_store.dart';
import 'assistant_provider.dart';

part 'assistant_database_explorer_specs_01.dart';
part 'assistant_database_explorer_specs_02.dart';
part 'assistant_database_explorer_specs_03.dart';
part 'assistant_database_explorer_specs_04.dart';

/// Read-only, permission-scoped access to the business schema.
///
/// The assistant receives a schema catalog and can request bounded aggregate
/// queries over the explicitly described tables below. SQL sources,
/// expressions, and scope predicates are fixed here; model-supplied values are
/// always bound parameters.
class AssistantDatabaseExplorerService {
  AssistantDatabaseExplorerService._();

  static const int _maximumGroups = 50;
  static const int _maximumSearchCharacters = 120;

  static const Map<String, _TableSpec> _specs = <String, _TableSpec>{
    ..._assistantDatabaseExplorerSpecsPart01,
    ..._assistantDatabaseExplorerSpecsPart02,
    ..._assistantDatabaseExplorerSpecsPart03,
    ..._assistantDatabaseExplorerSpecsPart04,
  };

  static List<_TableSpec> _availableSpecs(AppStore store) => _specs.values
      .where((spec) => _hasDomainPermission(store, spec.domain))
      .toList(growable: false);

  static List<AssistantJsonMap> definitionsFor(AppStore store) {
    final specs = _availableSpecs(store);
    if (specs.isEmpty) return const <AssistantJsonMap>[];
    final tableNames = specs.map((spec) => spec.baseTable).toList();
    return <AssistantJsonMap>[
      <String, Object?>{
        'name': 'business_schema_catalog',
        'description':
            'List business tables available to the signed-in user and what each table is for. Pass one table name to see its full columns, supported dimensions and measures, search fields, date field, and relationships. This returns schema metadata only, no business records.',
        'parameters': <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'table': <String, Object?>{
              'type': 'string',
              'enum': tableNames,
              'description': 'Optional table to inspect in detail.',
            },
          },
          'additionalProperties': false,
        },
      },
      <String, Object?>{
        'name': 'business_table_analysis',
        'description':
            'Run a bounded read-only aggregate query over one permitted business table. Use business_schema_catalog first when unsure about columns or relationships. It returns grouped aggregates only, never raw rows or arbitrary SQL. Dates are inclusive. Different currencies are grouped separately; quantities are grouped by product.',
        'parameters': <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'table': <String, Object?>{
              'type': 'string',
              'enum': tableNames,
              'description': 'A business table allowed for the active user.',
            },
            'group_by': <String, Object?>{
              'type': 'string',
              'description':
                  'Optional dimension column from the selected table. Use "none" for an overall aggregate.',
            },
            'measure': <String, Object?>{
              'type': 'string',
              'description':
                  'Aggregate to calculate; choose one listed for the table in the schema catalog. Defaults to the table row count.',
            },
            'from': <String, Object?>{
              'type': 'string',
              'format': 'date',
              'description':
                  'Inclusive start date when the table supports dates.',
            },
            'to': <String, Object?>{
              'type': 'string',
              'format': 'date',
              'description':
                  'Inclusive end date when the table supports dates.',
            },
            'search': <String, Object?>{
              'type': 'string',
              'maxLength': _maximumSearchCharacters,
              'description':
                  'Optional partial match in the table search fields listed in the catalog.',
            },
            'filter_by': <String, Object?>{
              'type': 'string',
              'description':
                  'Optional exact filter dimension from the catalog.',
            },
            'filter_value': <String, Object?>{
              'type': 'string',
              'maxLength': _maximumSearchCharacters,
              'description': 'Required with filter_by.',
            },
            'filter_match': <String, Object?>{
              'type': 'string',
              'enum': <String>['equals', 'contains'],
              'description': 'Filter matching mode; defaults to equals.',
            },
            'limit': <String, Object?>{
              'type': 'integer',
              'description': 'Maximum groups from 1 to 50; defaults to 30.',
            },
          },
          'required': <String>['table'],
          'additionalProperties': false,
        },
      },
    ];
  }

  static bool canUse(AppStore store) => _availableSpecs(store).isNotEmpty;

  static Future<AssistantJsonMap> executeCatalog({
    required AppStore store,
    required Map<String, Object?> arguments,
  }) async {
    _requireOnlyArguments(arguments, const <String>{'table'});
    final db = _requireDatabase();
    final specs = _availableSpecs(store);
    if (specs.isEmpty) _permissionDenied();
    final requestedTable = _stringArgument(arguments, 'table');
    final selectedSpecs = requestedTable.isEmpty
        ? specs
        : specs.where((spec) => spec.baseTable == requestedTable).toList();
    if (selectedSpecs.isEmpty) _permissionDenied();
    final tables = <AssistantJsonMap>[];
    for (final spec in selectedSpecs) {
      if (requestedTable.isEmpty) {
        tables.add(<String, Object?>{
          'table': spec.baseTable,
          'title': spec.title,
          'description': spec.description,
        });
        continue;
      }
      final columns = await db
          .customSelect(
            'PRAGMA table_info("${spec.baseTable}")',
          )
          .get();
      if (columns.isEmpty) continue;
      final documentedColumns = <String, _ColumnDoc>{
        for (final column in spec.documentedColumns) column.name: column,
      };
      tables.add(<String, Object?>{
        'table': spec.baseTable,
        'title': spec.title,
        'description': spec.description,
        if (requestedTable.isNotEmpty)
          'columns': columns.map((row) {
            final name = row.data['name']?.toString() ?? '';
            final documented = documentedColumns[name];
            return <String, Object?>{
              'name': name,
              'type': row.data['type']?.toString() ?? '',
              'description': documented?.description ??
                  'Stored source field; use the documented analysis dimensions and measures.',
              'usableAsDimension': spec.dimensions.containsKey(name),
            };
          }).toList(growable: false),
        'dimensions': spec.dimensions.entries
            .map((entry) => <String, Object?>{
                  'name': entry.key,
                  'description': entry.value.description,
                  'type': entry.value.type,
                })
            .toList(growable: false),
        'measures': spec.measures.entries
            .map((entry) => <String, Object?>{
                  'name': entry.key,
                  'description': entry.value.description,
                  'unit': entry.value.unit,
                  if (entry.value.currencyLabel != null)
                    'currencyBasis': entry.value.currencyLabel,
                  if (entry.value.currencyExpression != null)
                    'currencyColumn':
                        entry.value.currencyExpression!.split('.').last,
                  if (entry.value.contextLabel != null)
                    'groupedByContext': entry.value.contextLabel,
                  if (entry.value.additionalContextLabel != null)
                    'additionalGroupingContext':
                        entry.value.additionalContextLabel,
                  if (entry.value.tertiaryContextLabel != null)
                    'tertiaryGroupingContext': entry.value.tertiaryContextLabel,
                })
            .toList(growable: false),
        'searchColumns': spec.searchExpressions
            .map((expression) => expression.split('.').last)
            .toList(growable: false),
        'dateColumn': spec.dateExpression?.split('.').last,
        'relationships': spec.relationships,
      });
    }
    return <String, Object?>{
      'scope':
          'Active store only; table access also follows the signed-in user permissions.',
      'rowDataIncluded': false,
      'tables': tables,
      'tableCount': tables.length,
      'detailForTable': requestedTable.isEmpty ? null : requestedTable,
      'omittedSchema':
          'Authentication credentials, user permission records, sync payloads, audit logs, app logs, migrations, assistant history, internal configuration, and helper tables without a safe store-scoped analysis definition are not offered for data analysis.',
    };
  }

  static Future<AssistantJsonMap> executeAnalysis({
    required AppStore store,
    required Map<String, Object?> arguments,
  }) async {
    _requireOnlyArguments(arguments);
    final tableName = _stringArgument(arguments, 'table', required: true);
    final spec = _specs[tableName];
    if (spec == null || !_hasDomainPermission(store, spec.domain)) {
      _permissionDenied();
    }
    final groupBy = _stringArgument(arguments, 'group_by', fallback: 'none');
    final measureName = _stringArgument(
      arguments,
      'measure',
      fallback: spec.measures.keys.first,
    );
    final measure = spec.measures[measureName];
    if (measure == null) {
      throw const AssistantDatabaseExplorerException(
        'invalid_measure',
        'Choose a measure listed for this table in the schema catalog.',
      );
    }
    final dimension = groupBy == 'none' ? null : spec.dimensions[groupBy];
    if (groupBy != 'none' && dimension == null) {
      throw const AssistantDatabaseExplorerException(
        'invalid_dimension',
        'Choose a dimension listed for this table in the schema catalog.',
      );
    }
    final from = _parseDate(arguments, 'from');
    final to = _parseDate(arguments, 'to');
    if ((from == null) != (to == null)) {
      throw const AssistantDatabaseExplorerException(
        'invalid_date_range',
        'Provide both start and end dates, or omit both.',
      );
    }
    if (from != null && from.isAfter(to!)) {
      throw const AssistantDatabaseExplorerException(
        'invalid_date_range',
        'The start date must be on or before the end date.',
      );
    }
    if (from != null && spec.dateExpression == null) {
      throw const AssistantDatabaseExplorerException(
        'unsupported_date_filter',
        'This table does not have a supported date column.',
      );
    }
    final search = _stringArgument(
      arguments,
      'search',
      maxLength: _maximumSearchCharacters,
    );
    final filterBy = _stringArgument(arguments, 'filter_by');
    final filterValue = _stringArgument(
      arguments,
      'filter_value',
      maxLength: _maximumSearchCharacters,
    );
    final filterMatch = _stringArgument(
      arguments,
      'filter_match',
      fallback: 'equals',
    );
    if (filterMatch != 'equals' && filterMatch != 'contains') {
      throw const AssistantDatabaseExplorerException(
        'invalid_filter',
        'Choose equals or contains for filter_match.',
      );
    }
    if ((filterBy.isEmpty) != (filterValue.isEmpty)) {
      throw const AssistantDatabaseExplorerException(
        'invalid_filter',
        'Provide both filter_by and filter_value, or omit both.',
      );
    }
    final filterDimension = filterBy.isEmpty ? null : spec.dimensions[filterBy];
    if (filterBy.isNotEmpty && filterDimension == null) {
      throw const AssistantDatabaseExplorerException(
        'invalid_filter',
        'Choose a filter dimension listed in the schema catalog.',
      );
    }
    final limit = _integerArgument(arguments, 'limit', fallback: 30);
    if (limit < 1 || limit > _maximumGroups) {
      throw const AssistantDatabaseExplorerException(
        'invalid_limit',
        'Choose a result limit from 1 to 50.',
      );
    }
    final storeId = store.runtime.identity.storeId.trim();
    if (storeId.isEmpty) {
      throw const AssistantDatabaseExplorerException(
        'active_store_required',
        'Sign in to Ventio and select a store before analyzing business data.',
      );
    }

    final where = <String>[spec.scope];
    final variables = <Variable<Object>>[Variable<String>(storeId)];
    if (spec.softDelete != null) where.add(spec.softDelete!);
    if (spec.defaultFilter != null) where.add(spec.defaultFilter!);
    if (from != null && spec.dateExpression != null) {
      where.add("date(${spec.dateExpression}) >= date(?)");
      variables.add(Variable<String>(_dateLabel(from)));
      where.add("date(${spec.dateExpression}) <= date(?)");
      variables.add(Variable<String>(_dateLabel(to!)));
    }
    if (search.isNotEmpty && spec.searchExpressions.isNotEmpty) {
      where.add(
          '(${spec.searchExpressions.map((expr) => 'lower($expr) LIKE ?').join(' OR ')})');
      final pattern =
          '%${search.toLowerCase().replaceAll('%', r'\%').replaceAll('_', r'\_')}%';
      for (var i = 0; i < spec.searchExpressions.length; i++) {
        variables.add(Variable<String>(pattern));
      }
    } else if (search.isNotEmpty) {
      throw const AssistantDatabaseExplorerException(
        'unsupported_search',
        'This table does not expose searchable text fields.',
      );
    }
    if (filterDimension != null) {
      final expression = filterDimension.expression;
      if (filterMatch == 'contains') {
        where.add('lower(CAST($expression AS TEXT)) LIKE ?');
        variables.add(Variable<String>('%${filterValue.toLowerCase()}%'));
      } else {
        where.add('lower(CAST($expression AS TEXT)) = lower(?)');
        variables.add(Variable<String>(filterValue));
      }
    }

    final groupExpressions = <String>[];
    final selectExpressions = <String>[];
    if (dimension != null) {
      groupExpressions.add(dimension.expression);
      selectExpressions.add('${dimension.expression} AS group_value');
    } else {
      selectExpressions.add("'All records' AS group_value");
    }
    if (measure.currencyExpression != null) {
      groupExpressions.add(measure.currencyExpression!);
      selectExpressions.add('${measure.currencyExpression} AS currency');
    }
    final contexts = <String, String>{
      if (measure.contextExpression != null)
        measure.contextLabel ?? 'context': measure.contextExpression!,
      if (measure.additionalContextExpression != null)
        measure.additionalContextLabel ?? 'additional_context':
            measure.additionalContextExpression!,
      if (measure.tertiaryContextExpression != null)
        measure.tertiaryContextLabel ?? 'tertiary_context':
            measure.tertiaryContextExpression!,
    };
    final contextEntries = contexts.entries.toList(growable: false);
    for (var index = 0; index < contextEntries.length; index++) {
      final entry = contextEntries[index];
      final expression = entry.value;
      if (!groupExpressions.contains(expression)) {
        groupExpressions.add(expression);
      }
      selectExpressions.add('$expression AS context_$index');
    }
    selectExpressions.add('${measure.expression} AS measure_value');
    final groupBySql = groupExpressions.isEmpty
        ? ''
        : 'GROUP BY ${groupExpressions.join(', ')}';
    final rows = await _requireDatabase().customSelect('''
      SELECT ${selectExpressions.join(', ')}
      FROM ${spec.source}
      WHERE ${where.join(' AND ')}
      $groupBySql
      ORDER BY measure_value DESC
      LIMIT ?
    ''', variables: <Variable<Object>>[
      ...variables,
      Variable<int>(limit + 1),
    ]).get();
    final visibleRows = rows.take(limit).map((row) {
      final data = <String, Object?>{
        'group': row.data['group_value'],
        'value': row.data['measure_value'],
      };
      if (row.data.containsKey('currency')) {
        data['currency'] = row.data['currency'];
      } else if (measure.currencyLabel != null) {
        data['currencyBasis'] = measure.currencyLabel;
      }
      for (var index = 0; index < contextEntries.length; index++) {
        data[contextEntries[index].key] = row.data['context_$index'];
      }
      return data;
    }).toList(growable: false);
    return <String, Object?>{
      'table': spec.baseTable,
      'tableTitle': spec.title,
      'tableMeaning': spec.description,
      'groupedBy': groupBy,
      'measure': measureName,
      'measureMeaning': measure.description,
      'measureUnit': measure.unit,
      'period': from == null
          ? 'all available history'
          : <String, String>{'from': _dateLabel(from), 'to': _dateLabel(to!)},
      'search': search.isEmpty ? null : search,
      'filter': filterDimension == null
          ? null
          : <String, String>{
              'dimension': filterBy,
              'match': filterMatch,
              'value': filterValue,
            },
      'groups': visibleRows,
      'groupLimit': limit,
      'groupsTruncated': rows.length > limit,
      'scope': 'active store only',
      'aggregationOnly': true,
      'notes': <String>[
        if (measure.currencyExpression != null)
          'Money is split by currency; do not combine different currency rows.',
        if (measure.currencyExpression == null && measure.currencyLabel != null)
          measure.currencyLabel!,
        if (contexts.isNotEmpty)
          'The measure is also split by ${contexts.keys.join(' and ')} to preserve its comparison context.',
        if (spec.defaultFilter != null)
          spec.defaultFilterDescription ??
              'A table-specific status or reversal filter is applied.',
      ],
    };
  }

  static bool _hasDomainPermission(AppStore store, _Domain domain) =>
      switch (domain) {
        _Domain.sales => store.security.canViewSales,
        _Domain.purchases => store.security.canViewPurchases,
        _Domain.customers => store.security.canViewCustomers || store.security.canViewSales,
        _Domain.suppliers => store.security.canViewSuppliers || store.security.canViewPurchases,
        _Domain.inventory => store.security.canViewInventory || store.security.canViewAccounting,
        _Domain.expenses => store.security.canViewExpenses,
        _Domain.accounting => store.security.canViewAccounting,
        _Domain.cash => store.security.canViewCashBox,
        _Domain.manufacturing =>
          store.security.canViewInventory || store.security.canViewAccounting,
      };

  static VentioDriftDatabase _requireDatabase() {
    final db = SqliteMigrationManager.database;
    if (db == null) {
      throw const AssistantDatabaseExplorerException(
        'business_database_unavailable',
        'Ventio business data is not available for a local read right now.',
      );
    }
    return db;
  }

  static void _requireOnlyArguments(
    Map<String, Object?> arguments, [
    Set<String> allowed = const <String>{
      'table',
      'group_by',
      'measure',
      'from',
      'to',
      'search',
      'filter_by',
      'filter_value',
      'filter_match',
      'limit',
    },
  ]) {
    if (arguments.keys.any((key) => !allowed.contains(key))) {
      throw const AssistantDatabaseExplorerException(
        'invalid_arguments',
        'The table analysis contains unsupported arguments.',
      );
    }
  }

  static String _stringArgument(
    Map<String, Object?> arguments,
    String key, {
    bool required = false,
    String fallback = '',
    int? maxLength,
  }) {
    final value = arguments[key];
    if (value == null) {
      if (required) {
        throw AssistantDatabaseExplorerException(
          'invalid_arguments',
          'The $key argument is required.',
        );
      }
      return fallback;
    }
    if (value is! String || (maxLength != null && value.length > maxLength)) {
      throw AssistantDatabaseExplorerException(
        'invalid_arguments',
        'The $key argument must be text${maxLength == null ? '' : ' up to $maxLength characters'}.',
      );
    }
    return value.trim();
  }

  static int _integerArgument(
    Map<String, Object?> arguments,
    String key, {
    required int fallback,
  }) {
    final value = arguments[key];
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num && value.isFinite && value == value.roundToDouble()) {
      return value.toInt();
    }
    throw AssistantDatabaseExplorerException(
      'invalid_arguments',
      'The $key argument must be a whole number.',
    );
  }

  static DateTime? _parseDate(Map<String, Object?> arguments, String key) {
    final raw = arguments[key];
    if (raw == null) return null;
    if (raw is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) {
      throw AssistantDatabaseExplorerException(
        'invalid_date',
        'Use YYYY-MM-DD for $key.',
      );
    }
    final parsed = DateTime.tryParse(raw);
    if (parsed == null || _dateLabel(parsed) != raw) {
      throw AssistantDatabaseExplorerException(
        'invalid_date',
        'The $key date is not a valid calendar date.',
      );
    }
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  static String _dateLabel(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static Never _permissionDenied() =>
      throw const AssistantDatabaseExplorerException(
        'permission_denied',
        'Your Ventio account does not have permission to analyze this business data.',
      );
}

class AssistantDatabaseExplorerException implements Exception {
  const AssistantDatabaseExplorerException(this.code, this.message);

  final String code;
  final String message;
}

enum _Domain {
  sales,
  purchases,
  customers,
  suppliers,
  inventory,
  expenses,
  accounting,
  cash,
  manufacturing,
}

class _DimensionSpec {
  const _DimensionSpec(this.expression, this.description, this.type);

  final String expression;
  final String description;
  final String type;
}

class _MeasureSpec {
  const _MeasureSpec(
    this.expression,
    this.description,
    this.unit, {
    this.currencyExpression,
    this.currencyLabel,
    this.contextExpression,
    this.contextLabel,
    this.additionalContextExpression,
    this.additionalContextLabel,
    this.tertiaryContextExpression,
    this.tertiaryContextLabel,
  });

  final String expression;
  final String description;
  final String unit;
  final String? currencyExpression;
  final String? currencyLabel;
  final String? contextExpression;
  final String? contextLabel;
  final String? additionalContextExpression;
  final String? additionalContextLabel;
  final String? tertiaryContextExpression;
  final String? tertiaryContextLabel;
}

class _ColumnDoc {
  const _ColumnDoc(this.name, this.type, this.description);

  final String name;
  final String type;
  final String description;
}

class _TableSpec {
  const _TableSpec({
    required this.domain,
    required this.title,
    required this.description,
    required this.baseTable,
    required this.source,
    required this.scope,
    required this.dimensions,
    required this.measures,
    this.softDelete,
    this.dateExpression,
    this.searchExpressions = const <String>[],
    this.defaultFilter,
    this.defaultFilterDescription,
    this.relationships = const <String>[],
  });

  final _Domain domain;
  final String title;
  final String description;
  final String baseTable;
  final String source;
  final String scope;
  final String? softDelete;
  final String? dateExpression;
  final List<String> searchExpressions;
  final String? defaultFilter;
  final String? defaultFilterDescription;
  final Map<String, _DimensionSpec> dimensions;
  final Map<String, _MeasureSpec> measures;
  final List<String> relationships;

  List<_ColumnDoc> get documentedColumns => <_ColumnDoc>[
        const _ColumnDoc('id', 'text', 'Unique record identifier.'),
        const _ColumnDoc('store_id', 'text', 'Owning Ventio store.'),
        const _ColumnDoc('branch_id', 'text', 'Associated branch identifier.'),
        const _ColumnDoc(
            'deleted_at', 'text', 'Soft-delete marker; blank means active.'),
        ...dimensions.entries.map((entry) {
          final name = entry.key;
          final type = entry.value.type;
          return _ColumnDoc(name, type, entry.value.description);
        }),
      ]
          .fold(<String, _ColumnDoc>{}, (map, column) {
            map[column.name] = column;
            return map;
          })
          .values
          .toList(growable: false);
}
