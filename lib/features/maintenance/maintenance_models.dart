enum MaintenanceSeverity { ok, info, warning, critical }

enum MaintenanceRepairAction { refreshOnly, repairMissingCloudQueue }

class MaintenanceIssue {
  const MaintenanceIssue({
    required this.id,
    required this.title,
    required this.message,
    required this.severity,
    this.repairAction,
    this.details = const <String, dynamic>{},
  });

  final String id;
  final String title;
  final String message;
  final MaintenanceSeverity severity;
  final MaintenanceRepairAction? repairAction;
  final Map<String, dynamic> details;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'message': message,
        'severity': severity.name,
        'repairAction': repairAction?.name,
        'details': details,
      };
}

class MaintenanceSummary {
  const MaintenanceSummary({
    required this.generatedAt,
    required this.platformLabel,
    required this.databaseDirectoryPath,
    required this.databaseFilePath,
    required this.databaseExists,
    required this.databaseSizeBytes,
    required this.counts,
    required this.issues,
    this.databaseEngine = 'sqlite',
    this.databaseDetails = const <String, dynamic>{},
    this.migrationMeta = const <String, String>{},
  });

  final DateTime generatedAt;
  final String platformLabel;
  final String databaseDirectoryPath;
  final String databaseFilePath;
  final bool databaseExists;
  final int databaseSizeBytes;
  final Map<String, int> counts;
  final List<MaintenanceIssue> issues;
  final String databaseEngine;
  final Map<String, dynamic> databaseDetails;
  final Map<String, String> migrationMeta;

  int get criticalCount => issues.where((item) => item.severity == MaintenanceSeverity.critical).length;
  int get warningCount => issues.where((item) => item.severity == MaintenanceSeverity.warning).length;
  int get infoCount => issues.where((item) => item.severity == MaintenanceSeverity.info).length;
  int get actionCount => criticalCount + warningCount;
  bool get isHealthy => actionCount == 0;

  int get healthScore {
    var score = 100;
    score -= criticalCount * 30;
    score -= warningCount * 12;
    score -= infoCount * 3;
    if (!databaseExists) score -= 20;
    return score.clamp(0, 100);
  }

  String get healthStatusLabel {
    if (criticalCount > 0) return 'Critical attention needed';
    if (warningCount > 0) return 'Needs maintenance';
    if (infoCount > 0) return 'Healthy with notes';
    return 'Healthy';
  }

  List<String> get recommendations {
    final items = <String>[];
    if (!databaseExists) {
      items.add('Run the app once, then run the health check again to confirm the SQLite database file is created.');
    }
    if ((counts['products'] ?? 0) == 0) {
      items.add('Add products to start inventory tracking.');
    }
    if ((counts['sales'] ?? 0) == 0) {
      items.add('Create a first sale invoice to validate the sales workflow.');
    }
    if ((counts['pendingSyncChanges'] ?? 0) > 0 || (counts['pendingSyncQueue'] ?? 0) > 0) {
      items.add('Open sync tools and complete pending synchronization when the network is available.');
    }
    if ((counts['dataConflicts'] ?? 0) > 0) {
      items.add('Review data conflicts before creating more invoices.');
    }
    if (items.isEmpty) {
      items.add('Create a fresh backup before major updates or device changes.');
    } else {
      items.add('Create a backup after fixing any maintenance warnings.');
    }
    return items;
  }

  Map<String, dynamic> toJson() => {
        'generatedAt': generatedAt.toIso8601String(),
        'platform': platformLabel,
        'database': {
          'engine': databaseEngine,
          'directoryPath': databaseDirectoryPath,
          'filePath': databaseFilePath,
          'exists': databaseExists,
          'sizeBytes': databaseSizeBytes,
          ...databaseDetails,
        },
        'migrationMeta': migrationMeta,
        'counts': counts,
        'issues': issues.map((item) => item.toJson()).toList(),
      };
}

class MaintenanceRepairResult {
  const MaintenanceRepairResult({
    required this.title,
    required this.message,
    this.changedRecords = 0,
  });

  final String title;
  final String message;
  final int changedRecords;
}
