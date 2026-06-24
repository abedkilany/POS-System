class JournalLineDraft {
  const JournalLineDraft({
    required this.accountId,
    required this.debit,
    required this.credit,
    this.memo = '',
    this.partyType = '',
    this.partyId = '',
    this.partyName = '',
    this.costCenterId = '',
  });

  final String accountId;
  final double debit;
  final double credit;
  final String memo;
  final String partyType;
  final String partyId;
  final String partyName;
  final String costCenterId;
}

class JournalEntryDraft {
  const JournalEntryDraft({
    required this.entryDate,
    required this.description,
    required this.lines,
    this.referenceType = '',
    this.referenceId = '',
    this.referenceNo = '',
    this.source = 'system',
    this.createdBy = '',
    this.storeId = '',
    this.branchId = '',
  });

  final DateTime entryDate;
  final String description;
  final List<JournalLineDraft> lines;
  final String referenceType;
  final String referenceId;
  final String referenceNo;
  final String source;
  final String createdBy;
  final String storeId;
  final String branchId;
}
