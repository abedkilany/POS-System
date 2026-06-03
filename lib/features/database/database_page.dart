import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';
import '../../data/app_store.dart';

class DatabasePage extends StatefulWidget {
  const DatabasePage({super.key, required this.store});

  final AppStore store;

  @override
  State<DatabasePage> createState() => _DatabasePageState();
}

class _DatabasePageState extends State<DatabasePage> {
  String _entity = AppStore.databaseEditableEntities.first;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final rows = widget.store.databaseRows(_entity);
    final filteredRows = rows.where((row) {
      final text = jsonEncode(row).toLowerCase();
      return text.contains(_query.trim().toLowerCase());
    }).toList(growable: false);

    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _entity,
                      decoration: InputDecoration(labelText: tr.text('database_collection')),
                      items: AppStore.databaseEditableEntities
                          .map((entity) => DropdownMenuItem(value: entity, child: Text(tr.text('database_$entity'))))
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _entity = value);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: () => _openEditor(),
                    icon: const Icon(Icons.add),
                    label: Text(tr.text('database_add_row')),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: InputDecoration(
                  labelText: tr.text('search'),
                  prefixIcon: const Icon(Icons.search),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded),
                      const SizedBox(width: 10),
                      Expanded(child: Text(tr.text('database_warning'))),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: filteredRows.isEmpty
                    ? Center(child: Text(tr.text('database_empty')))
                    : ListView.separated(
                        itemCount: filteredRows.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final row = filteredRows[index];
                          final id = row['id']?.toString() ?? '';
                          final title = _rowTitle(row);
                          return ListTile(
                            title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(id, maxLines: 1, overflow: TextOverflow.ellipsis),
                            trailing: Wrap(
                              spacing: 4,
                              children: [
                                IconButton(
                                  tooltip: tr.text('edit'),
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () => _openEditor(row: row),
                                ),
                                IconButton(
                                  tooltip: tr.text('delete'),
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: id.isEmpty ? null : () => _confirmDelete(id),
                                ),
                              ],
                            ),
                            onTap: () => _openEditor(row: row),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _rowTitle(Map<String, dynamic> row) {
    for (final key in ['name', 'nameEn', 'title', 'code', 'phone']) {
      final value = row[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return row['id']?.toString() ?? 'Record';
  }

  Map<String, dynamic> _emptyRow() {
    final now = DateTime.now().toIso8601String();
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    switch (_entity) {
      case 'products':
        return {'id': id, 'name': '', 'code': '', 'price': 0, 'cost': 0, 'stock': 0, 'category': 'General', 'barcode': '', 'unit': 'pcs', 'createdAt': now, 'updatedAt': now};
      case 'customers':
        return {'id': id, 'name': '', 'phone': '', 'address': '', 'createdAt': now, 'updatedAt': now};
      case 'suppliers':
        return {'id': id, 'name': '', 'phone': '', 'address': '', 'createdAt': now, 'updatedAt': now};
      case 'expenses':
        return {'id': id, 'title': '', 'category': '', 'amount': 0, 'date': now, 'notes': '', 'createdAt': now, 'updatedAt': now};
      default:
        return {'id': id, 'nameEn': '', 'nameAr': '', 'code': '', 'createdAt': now, 'updatedAt': now};
    }
  }

  Future<void> _openEditor({Map<String, dynamic>? row}) async {
    final tr = AppLocalizations.of(context);
    final controller = TextEditingController(
      text: const JsonEncoder.withIndent('  ').convert(row ?? _emptyRow()),
    );
    controller.selection = const TextSelection.collapsed(offset: 0);

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(row == null ? tr.text('database_add_row') : tr.text('database_edit_row')),
        content: SizedBox(
          width: 760,
          child: TextField(
            controller: controller,
            minLines: 18,
            maxLines: 24,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr.text('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr.text('save'))),
        ],
      ),
    );

    if (saved != true) return;
    try {
      final decoded = jsonDecode(controller.text);
      if (decoded is! Map<String, dynamic>) throw const FormatException('JSON must be an object.');
      await widget.store.saveDatabaseRow(_entity, decoded);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.text('database_saved'))));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${tr.text('database_error')}: $error')));
    }
  }

  Future<void> _confirmDelete(String id) async {
    final tr = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr.text('delete')),
        content: Text(tr.text('database_delete_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr.text('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr.text('delete'))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.store.deleteDatabaseRow(_entity, id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.text('database_deleted'))));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${tr.text('database_error')}: $error')));
    }
  }
}
