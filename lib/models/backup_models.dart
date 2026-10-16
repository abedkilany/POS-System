class BackupSummary {
  const BackupSummary({
    required this.version,
    required this.generatedAt,
    required this.productsCount,
    required this.customersCount,
    required this.salesCount,
    required this.suppliersCount,
    required this.expensesCount,
    required this.storeName,
  });

  final int version;
  final DateTime? generatedAt;
  final int productsCount;
  final int customersCount;
  final int salesCount;
  final int suppliersCount;
  final int expensesCount;
  final String storeName;
}

class BackupImportSection {
  const BackupImportSection({
    required this.id,
    required this.label,
    required this.group,
    required this.available,
    required this.selectedByDefault,
    this.count,
    this.warning,
  });

  final String id;
  final String label;
  final String group;
  final bool available;
  final bool selectedByDefault;
  final int? count;
  final String? warning;
}

class BackupImportPlan {
  const BackupImportPlan({
    required this.summary,
    required this.sections,
  });

  final BackupSummary summary;
  final List<BackupImportSection> sections;
}

class BackupValidationResult {
  const BackupValidationResult({
    required this.isValid,
    required this.summary,
    this.errorMessage,
  });

  final bool isValid;
  final BackupSummary? summary;
  final String? errorMessage;
}
