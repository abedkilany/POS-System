part of 'accounting_service_impl.dart';

Future<void> createManualJournalEntry({
  required DateTime entryDate,
  required String description,
  required List<JournalLineDraft> lines,
  String createdBy = '',
  String storeId = '',
  String branchId = '',
}) async {
  if (!isAvailable) return;
  await createPostedEntry(JournalEntryDraft(
    entryDate: entryDate,
    referenceType: 'manual_journal',
    referenceId: _newId('manual'),
    referenceNo: 'يدوي',
    description:
        description.trim().isEmpty ? 'قيد يومية يدوي' : description.trim(),
    source: 'manual',
    createdBy: createdBy,
    storeId: storeId,
    branchId: branchId,
    lines: lines,
  ));
  _notifyMutation();
}

/// Safely edits an already-posted manual journal. System-generated journal
/// entries are intentionally excluded: they must be edited from their
/// owning business document so operational and accounting state stay aligned.
///
/// Manual journals do not have a separate document table/version column, so
/// the currently-active journal entry id is the optimistic concurrency token.
/// Each successful edit reverses the active family member and posts a new
/// append-only member using `<base>:manual_edit:vN`.
Future<String> editManualJournalEntry({
  required String activeEntryId,
  required DateTime entryDate,
  required String description,
  required List<JournalLineDraft> lines,
  String createdBy = '',
  String branchId = '',
}) async {
  if (!isAvailable) return '';
  final normalizedEntryId = activeEntryId.trim();
  if (normalizedEntryId.isEmpty) {
    throw ArgumentError.value(activeEntryId, 'activeEntryId');
  }
  _validateBalancedDraft(JournalEntryDraft(
    entryDate: entryDate,
    description: description,
    lines: lines,
  ));

  final db = _db;
  var nextReferenceId = '';
  var createdEntryId = '';
  var selectedStoreId = '';

  Future<JournalEntryDetailsReport> loadSelected() async {
    final entryRow = await db.customSelect(
      '''
        SELECT je.id, je.entry_no, je.entry_date, je.reference_type,
               je.reference_id, je.reference_no, je.description, je.status,
               je.source, je.created_by, je.store_id, je.branch_id, je.reversed_entry_id,
               je.reversed_by_entry_id, je.reversal_reason, je.posted_at,
               je.reversed_at, je.reversed_by
        FROM journal_entries je
        WHERE je.id = ? AND je.deleted_at = ''
        LIMIT 1
        ''',
      variables: <Variable<Object>>[Variable<String>(normalizedEntryId)],
    ).getSingleOrNull();
    if (entryRow == null) {
      throw StateError('Manual journal entry was not found.');
    }
    final data = entryRow.data;
    selectedStoreId = data['store_id']?.toString() ?? '';
    final lineRows = await db.customSelect(
      '''
        SELECT line_no, account_id, account_code, account_name, debit, credit,
               memo, party_type, party_id, party_name, cost_center_id
        FROM journal_lines
        WHERE entry_id = ?
        ORDER BY line_no
        ''',
      variables: <Variable<Object>>[Variable<String>(normalizedEntryId)],
    ).get();
    return JournalEntryDetailsReport(
      id: normalizedEntryId,
      entryNo: data['entry_no']?.toString() ?? '',
      entryDate: _parseDate(data['entry_date']),
      referenceType: data['reference_type']?.toString() ?? '',
      referenceId: data['reference_id']?.toString() ?? '',
      referenceNo: data['reference_no']?.toString() ?? '',
      description: data['description']?.toString() ?? '',
      status: data['status']?.toString() ?? '',
      source: data['source']?.toString() ?? '',
      createdBy: data['created_by']?.toString() ?? '',
      branchId: data['branch_id']?.toString() ?? '',
      reversedEntryId: data['reversed_entry_id']?.toString() ?? '',
      reversedByEntryId: data['reversed_by_entry_id']?.toString() ?? '',
      reversalReason: data['reversal_reason']?.toString() ?? '',
      postedAt: DateTime.tryParse(data['posted_at']?.toString() ?? ''),
      reversedAt: DateTime.tryParse(data['reversed_at']?.toString() ?? ''),
      reversedBy: data['reversed_by']?.toString() ?? '',
      lines: lineRows
          .map((row) => JournalEntryDetailLineReport.fromRow(row.data))
          .toList(growable: false),
    );
  }

  String baseReference(String referenceId) {
    return referenceId.trim().replaceFirst(
          RegExp(r':manual_edit:v\d+$'),
          '',
        );
  }

  final selected = await db.transaction(() async {
    return PostedDocumentEditPipeline<JournalEntryDetailsReport>(
      loadAuthoritative: loadSelected,
      validatePermission: (current) async {
        if (current.referenceType != 'manual_journal' ||
            current.source != 'manual') {
          throw StateError(
            'Only manual journal entries can be edited directly. Edit system journals from their source document.',
          );
        }
        if (current.status != 'posted' ||
            current.reversedByEntryId.isNotEmpty) {
          throw StateError(
              'Only an active posted manual journal can be edited.');
        }
      },
      validateVersion: (current) async {
        final base = baseReference(current.referenceId);
        if (base.isEmpty) {
          throw StateError('Manual journal reference is invalid.');
        }
        final active = await db.customSelect(
          '''
            SELECT je.id, je.reference_id
            FROM journal_entries je
            WHERE je.reference_type = 'manual_journal'
              AND (je.reference_id = ? OR instr(je.reference_id, ?) = 1)
              AND je.deleted_at = '' AND je.status = 'posted'
              AND NOT EXISTS (
                SELECT 1 FROM journal_entries rev
                WHERE rev.reversed_entry_id = je.id
                  AND rev.deleted_at = '' AND rev.status = 'posted'
              )
            ORDER BY datetime(je.created_at) DESC, datetime(je.entry_date) DESC
            LIMIT 1
            ''',
          variables: <Variable<Object>>[
            Variable<String>(base),
            Variable<String>('$base:manual_edit:'),
          ],
        ).getSingleOrNull();
        if (active == null ||
            active.data['id']?.toString() != normalizedEntryId) {
          throw StateError(
            'Manual journal changed after it was opened. Reload it before editing.',
          );
        }

        final familyRows = await db.customSelect(
          '''
            SELECT reference_id
            FROM journal_entries
            WHERE reference_type = 'manual_journal'
              AND (reference_id = ? OR instr(reference_id, ?) = 1)
              AND deleted_at = ''
            ''',
          variables: <Variable<Object>>[
            Variable<String>(base),
            Variable<String>('$base:manual_edit:'),
          ],
        ).get();
        var maxVersion = 1;
        final matcher = RegExp(r':manual_edit:v(\d+)$');
        for (final row in familyRows) {
          final reference = row.data['reference_id']?.toString() ?? '';
          final match = matcher.firstMatch(reference);
          final version = int.tryParse(match?.group(1) ?? '') ?? 1;
          if (version > maxVersion) maxVersion = version;
        }
        nextReferenceId = '$base:manual_edit:v${maxVersion + 1}';
      },
      validateDependencies: (current) async {
        if (lines.length < 2) {
          throw StateError('Manual journal must contain at least two lines.');
        }
        await _assertDateNotInClosedPeriod(
          entryDate,
          branchId.trim().isNotEmpty ? branchId.trim() : current.branchId,
          database: db,
        );
      },
      reverseOperationalEffects: (current) async {},
      reverseAccountingEffects: (current) async {
        await reverseEntryForReference(
          referenceType: 'manual_journal',
          referenceId: baseReference(current.referenceId),
          reason: 'Manual journal edit',
          createdBy: createdBy,
          adjustCashLocationBalance: false,
          notifyChange: false,
          withinExistingTransaction: true,
        );
        final reversed = await db.customSelect(
          'SELECT status, reversed_by_entry_id FROM journal_entries WHERE id = ? LIMIT 1',
          variables: <Variable<Object>>[Variable<String>(current.id)],
        ).getSingleOrNull();
        if (reversed?.data['status']?.toString() != 'reversed' ||
            (reversed?.data['reversed_by_entry_id']?.toString() ?? '')
                .isEmpty) {
          throw StateError('Previous manual journal version was not reversed.');
        }
      },
      applyChanges: (current) async => current,
      rebuildOperationalEffects: (current) async => current,
      buildPostedSnapshot: (current) async => current,
      repostAccounting: (current) async {
        createdEntryId = await createPostedEntry(
          JournalEntryDraft(
            entryDate: entryDate,
            referenceType: 'manual_journal',
            referenceId: nextReferenceId,
            referenceNo: current.referenceNo.trim().isEmpty
                ? 'يدوي'
                : current.referenceNo,
            description: description.trim().isEmpty
                ? 'قيد يومية يدوي'
                : description.trim(),
            source: 'manual',
            createdBy: createdBy.trim().isNotEmpty
                ? createdBy.trim()
                : current.createdBy,
            storeId: selectedStoreId,
            branchId:
                branchId.trim().isNotEmpty ? branchId.trim() : current.branchId,
            lines: lines,
          ),
          database: db,
          withinExistingTransaction: true,
        );
        if (createdEntryId.isEmpty) {
          throw StateError('Edited manual journal was not posted.');
        }
      },
      rebuildDerivedState: (current) async {},
      verifyIntegrity: (current) async {
        final row = await db.customSelect(
          '''
            SELECT je.status, je.reference_id, COUNT(jl.id) AS line_count,
                   COALESCE(SUM(jl.debit), 0) AS total_debit,
                   COALESCE(SUM(jl.credit), 0) AS total_credit
            FROM journal_entries je
            LEFT JOIN journal_lines jl ON jl.entry_id = je.id
            WHERE je.id = ? AND je.deleted_at = ''
            GROUP BY je.id, je.status, je.reference_id
            ''',
          variables: <Variable<Object>>[Variable<String>(createdEntryId)],
        ).getSingleOrNull();
        if (row == null ||
            row.data['status']?.toString() != 'posted' ||
            row.data['reference_id']?.toString() != nextReferenceId ||
            ((row.data['line_count'] as num?)?.toInt() ?? 0) != lines.length ||
            (_num(row.data['total_debit']) - _num(row.data['total_credit']))
                    .abs() >
                0.005) {
          throw StateError(
              'Edited manual journal failed integrity verification.');
        }
      },
    ).execute();
  });

  if (selected.id.isNotEmpty && createdEntryId.isNotEmpty) {
    _notifyMutation();
  }
  return createdEntryId;
}
