class AgingBucket {
  const AgingBucket({required this.label, required this.amount});

  final String label;
  final double amount;
}

class AgingReportRow {
  const AgingReportRow({
    required this.partyId,
    required this.partyName,
    required this.current,
    required this.days1To30,
    required this.days31To60,
    required this.days61To90,
    required this.over90,
    required this.total,
  });

  final String partyId;
  final String partyName;
  final double current;
  final double days1To30;
  final double days31To60;
  final double days61To90;
  final double over90;
  final double total;

  List<AgingBucket> get buckets => <AgingBucket>[
        AgingBucket(label: 'current', amount: current),
        AgingBucket(label: '0_30', amount: days1To30),
        AgingBucket(label: '31_60', amount: days31To60),
        AgingBucket(label: '61_90', amount: days61To90),
        AgingBucket(label: '90_plus', amount: over90),
      ];

  double amountForBucket(String label) {
    switch (label) {
      case 'current':
        return current;
      case '0_30':
        return days1To30;
      case '31_60':
        return days31To60;
      case '61_90':
        return days61To90;
      case '90_plus':
        return over90;
      default:
        return 0;
    }
  }
}

class AgingOpenDocument {
  const AgingOpenDocument({
    required this.id,
    required this.number,
    required this.partyId,
    required this.partyName,
    required this.date,
    required this.originalAmount,
    required this.openAmount,
    required this.bucketLabel,
    required this.ageDays,
  });

  final String id;
  final String number;
  final String partyId;
  final String partyName;
  final DateTime date;
  final double originalAmount;
  final double openAmount;
  final String bucketLabel;
  final int ageDays;
}

class AgingReportResult {
  const AgingReportResult({
    required this.asOfDate,
    required this.rows,
    required this.openDocuments,
  });

  final DateTime asOfDate;
  final List<AgingReportRow> rows;
  final List<AgingOpenDocument> openDocuments;

  double get total => rows.fold<double>(0, (sum, row) => sum + row.total);
  double get current => rows.fold<double>(0, (sum, row) => sum + row.current);
  double get days1To30 => rows.fold<double>(0, (sum, row) => sum + row.days1To30);
  double get days31To60 => rows.fold<double>(0, (sum, row) => sum + row.days31To60);
  double get days61To90 => rows.fold<double>(0, (sum, row) => sum + row.days61To90);
  double get over90 => rows.fold<double>(0, (sum, row) => sum + row.over90);
}
