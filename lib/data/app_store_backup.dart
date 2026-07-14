part of 'app_store.dart';

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

const List<String> _requiredBackupSections = <String>[
  'products',
  'customers',
  'sales',
  'suppliers',
  'expenses',
];

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

extension AppStoreBackupExtensions on AppStore {
  BackupSummary get currentBackupSummary => BackupSummary(
        version: 11,
        generatedAt: DateTime.now(),
        productsCount: products.length,
        customersCount: customers.length,
        salesCount: sales.length,
        suppliersCount: suppliers.length,
        expensesCount: expenses.length,
        storeName: _storeProfile.name,
      );

  Future<String> exportEncryptedBackupJson(String password) async {
    requirePermission(AppPermission.backupExport);
    final cleaned = password.trim();
    if (cleaned.length < 8) {
      throw ArgumentError('Backup password must be at least 8 characters.');
    }
    final plain = utf8.encode(await exportBackupJson());
    final salt = _generateSalt();
    final nonce = _generateNonce();
    final key = _deriveBackupKey(cleaned, salt);
    final encrypted = _aesGcmEncrypt(plain, key, base64Url.decode(nonce));
    final payload = {
      'format': 'store_manager_pro_encrypted_backup',
      'version': 3,
      'kdf': 'pbkdf2-hmac-sha256-200000',
      'cipher': 'aes-256-gcm',
      'salt': salt,
      'nonce': nonce,
      'data': base64UrlEncode(encrypted),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  BackupImportPlan inspectBackupJson(String rawJson) {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map) {
      throw const FormatException('Backup content must be a JSON object.');
    }
    final map = Map<String, dynamic>.from(decoded);

    int listCount(String key) =>
        (map[key] is List) ? (map[key] as List<dynamic>).length : 0;
    bool hasList(String key) => map[key] is List;
    bool hasMap(String key) => map[key] is Map;
    bool hasValue(String key) => map.containsKey(key) && map[key] != null;

    final generatedAtRaw = map['generatedAt'];
    DateTime? generatedAt;
    if (generatedAtRaw is String && generatedAtRaw.trim().isNotEmpty) {
      generatedAt = DateTime.tryParse(generatedAtRaw);
    }
    final storeProfileMap = map['storeProfile'] is Map
        ? Map<String, dynamic>.from(map['storeProfile'] as Map)
        : <String, dynamic>{};
    final storeName = (storeProfileMap['name'] as String?)?.trim();
    final summary = BackupSummary(
      version: (map['version'] as num?)?.toInt() ?? 0,
      generatedAt: generatedAt,
      productsCount: listCount('products'),
      customersCount: listCount('customers'),
      salesCount: listCount('sales'),
      suppliersCount: listCount('suppliers'),
      expensesCount: listCount('expenses'),
      storeName:
          (storeName == null || storeName.isEmpty) ? 'My Store' : storeName,
    );

    BackupImportSection business(
      String id,
      String label,
      bool available, {
      int? count,
    }) =>
        BackupImportSection(
          id: id,
          label: label,
          group: 'Business data',
          available: available,
          selectedByDefault: available,
          count: count,
        );

    BackupImportSection system(
      String id,
      String label,
      bool available, {
      int? count,
      String? warning,
    }) =>
        BackupImportSection(
          id: id,
          label: label,
          group: 'System data',
          available: available,
          selectedByDefault: false,
          count: count,
          warning: warning,
        );

    final hasQuotation = hasList('saleQuotations') || hasList('quotations');
    final quotationCount = hasList('saleQuotations')
        ? listCount('saleQuotations')
        : listCount('quotations');
    final restoreFullDeviceBackup =
        map['backupType']?.toString() == 'full_device_backup';

    return BackupImportPlan(
      summary: summary,
      sections: [
        business('products', 'Products', hasList('products'),
            count: listCount('products')),
        business('categories', 'Categories', hasList('categories'),
            count: listCount('categories')),
        business('brands', 'Brands', hasList('brands'),
            count: listCount('brands')),
        business('units', 'Units', hasList('units'), count: listCount('units')),
        business('customers', 'Customers', hasList('customers'),
            count: listCount('customers')),
        business('suppliers', 'Suppliers', hasList('suppliers'),
            count: listCount('suppliers')),
        business('supplierProductPrices', 'Supplier product prices',
            hasList('supplierProductPrices'),
            count: listCount('supplierProductPrices')),
        business('sales', 'Sales', hasList('sales'), count: listCount('sales')),
        business('saleQuotations', 'Sale quotations', hasQuotation,
            count: quotationCount),
        business('deliveryNotes', 'Delivery notes', hasList('deliveryNotes'),
            count: listCount('deliveryNotes')),
        business('purchases', 'Purchases', hasList('purchases'),
            count: listCount('purchases')),
        business('stockMovements', 'Stock movements', hasList('stockMovements'),
            count: listCount('stockMovements')),
        business(
            'inventoryCounts', 'Inventory counts', hasList('inventoryCounts'),
            count: listCount('inventoryCounts')),
        business('warehouses', 'Warehouses', hasList('warehouses'),
            count: listCount('warehouses')),
        business('expenses', 'Expenses', hasList('expenses'),
            count: listCount('expenses')),
        business('accountTransactions', 'Account transactions',
            hasList('accountTransactions'),
            count: listCount('accountTransactions')),
        business('manufacturing', 'Manufacturing',
            hasList('billsOfMaterials') || hasList('manufacturingOrders'),
            count: listCount('billsOfMaterials') +
                listCount('manufacturingOrders')),
        business('usersAndRoles', 'Users and roles',
            hasList('users') || hasList('roles'),
            count: listCount('users') + listCount('roles')),
        business('storeProfile', 'Store settings', hasMap('storeProfile')),
        business('counters', 'Invoice and purchase counters',
            hasValue('invoiceCounter') || hasValue('purchaseCounter')),
        system('themeMode', 'Theme mode', hasValue('themeMode')),
        system(
            'appIdentity',
            'App identity / Store ID',
            hasMap('appIdentity') ||
                hasValue('storeId') ||
                hasValue('branchId'),
            warning: 'May change the current device/store identity.'),
        system('deviceId', 'Device ID', hasValue('deviceId'),
            warning: 'May conflict with the current device identity.'),
        system('syncChanges', 'Sync changes log',
            restoreFullDeviceBackup && hasList('syncChanges'),
            count: listCount('syncChanges'),
            warning: 'May affect sync/rebuild behavior.'),
        system('syncQueue', 'Sync queue',
            restoreFullDeviceBackup && hasList('syncQueue'),
            count: listCount('syncQueue'),
            warning: 'May replay old pending sync work.'),
        system('localDatabaseEntries', 'Raw local database entries',
            restoreFullDeviceBackup && hasMap('localDatabaseEntries'),
            count: hasMap('localDatabaseEntries')
                ? (map['localDatabaseEntries'] as Map).length
                : null,
            warning:
                'Advanced option. It may override local settings and connection state.'),
      ],
    );
  }

  BackupValidationResult validateBackupJson(String rawJson) {
    try {
      final plan = inspectBackupJson(rawJson);
      final hasAnyAvailableSection =
          plan.sections.any((section) => section.available);
      final hasRequiredSections = _requiredBackupSections.every((sectionId) {
        final match = plan.sections.where((section) => section.id == sectionId);
        return match.isNotEmpty && match.first.available;
      });
      if (!hasRequiredSections) {
        return const BackupValidationResult(
          isValid: false,
          summary: null,
          errorMessage:
              'Missing required backup sections: products, customers, sales, suppliers, and expenses.',
        );
      }
      if (!hasAnyAvailableSection) {
        return const BackupValidationResult(
          isValid: false,
          summary: null,
          errorMessage: 'Backup does not contain any importable sections.',
        );
      }
      return BackupValidationResult(isValid: true, summary: plan.summary);
    } catch (_) {
      return const BackupValidationResult(
        isValid: false,
        summary: null,
        errorMessage: 'Invalid or corrupted backup JSON.',
      );
    }
  }

  bool isEncryptedBackupJson(String rawJson) {
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map) return false;
      return decoded['format'] == 'store_manager_pro_encrypted_backup';
    } catch (_) {
      return false;
    }
  }

  String extractBackupJsonFromLocalBackupArchiveBytes(List<int> bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      if (archive.files.isEmpty) {
        throw const FormatException('Local backup archive is empty.');
      }
      ArchiveFile? backupFile;
      for (final file in archive.files) {
        final name = file.name.toLowerCase();
        if (name == 'backup.json' || name.endsWith('/backup.json')) {
          backupFile = file;
          break;
        }
      }
      if (backupFile == null) {
        throw const FormatException(
          'Local backup archive does not contain backup.json.',
        );
      }
      final data = backupFile.content as List<int>;
      return utf8.decode(data, allowMalformed: true).trim();
    } catch (error) {
      throw FormatException('Invalid local backup archive.', error);
    }
  }

  String decryptBackupJson(String encryptedBackup, String password) {
    final decoded = jsonDecode(encryptedBackup) as Map<String, dynamic>;
    if (decoded['format'] != 'store_manager_pro_encrypted_backup') {
      return encryptedBackup;
    }
    final salt = decoded['salt'] as String? ?? '';
    final data = decoded['data'] as String? ?? '';
    if (salt.isEmpty || data.isEmpty) {
      throw ArgumentError('Invalid encrypted backup.');
    }

    // Backward compatibility with older backups created by the previous XOR-v1
    // format. New exports use an authenticated stream with a nonce and MAC.
    if ((decoded['version'] as num? ?? 1).toInt() < 2) {
      final key = _deriveBackupKeyV1(password.trim(), salt);
      final encrypted = base64Url.decode(data);
      final plain = List<int>.generate(
        encrypted.length,
        (index) => encrypted[index] ^ key[index % key.length],
      );
      return utf8.decode(plain);
    }

    final nonce = decoded['nonce'] as String? ?? '';
    if (nonce.isEmpty) throw ArgumentError('Invalid encrypted backup.');
    final encrypted = base64Url.decode(data);

    if ((decoded['version'] as num? ?? 2).toInt() == 2) {
      // Backward compatibility with backups exported by the authenticated
      // SHA-256 stream format. New exports use AES-256-GCM below.
      final macText = decoded['mac'] as String? ?? '';
      if (macText.isEmpty) throw ArgumentError('Invalid encrypted backup.');
      final legacyKey = _deriveBackupKeyV2(password.trim(), salt);
      final expectedMac = Hmac(
        sha256,
        legacyKey,
      ).convert([...utf8.encode(nonce), ...encrypted]).bytes;
      final actualMac = base64Url.decode(macText);
      if (!_constantTimeEquals(expectedMac, actualMac)) {
        throw ArgumentError(
          'Invalid backup password or corrupted encrypted backup.',
        );
      }
      final plain = _xorWithSha256Stream(encrypted, legacyKey, nonce);
      return utf8.decode(plain);
    }

    final key = _deriveBackupKey(password.trim(), salt);
    try {
      return utf8.decode(
        _aesGcmDecrypt(encrypted, key, base64Url.decode(nonce)),
      );
    } catch (_) {
      throw ArgumentError(
        'Invalid backup password or corrupted encrypted backup.',
      );
    }
  }
}
