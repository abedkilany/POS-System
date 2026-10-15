part of 'accounting_service_impl.dart';

Future<List<AdvancedAccountingItem>> listPaymentAccounts() async {
  if (!isAvailable) return const <AdvancedAccountingItem>[];
  final rows = await _db.customSelect(
    '''
      SELECT pa.id, pa.name, pa.type, pa.account_id, a.code AS account_code,
             a.name AS account_name, pa.is_default, pa.is_active, pa.notes
      FROM payment_accounts pa
      LEFT JOIN accounts a ON a.id = pa.account_id
      WHERE pa.deleted_at = ''
      ORDER BY pa.type, pa.name
      ''',
  ).get();
  return rows.map((row) => AdvancedAccountingItem.fromRow(row.data)).toList();
}

Future<List<AdvancedAccountingItem>> listActiveCashLocations({
  bool includeBank = true,
}) async {
  if (!isAvailable) return const <AdvancedAccountingItem>[];
  final typeFilter = includeBank ? '' : "AND cl.type <> 'bank'";
  final rows = await _db.customSelect(
    '''
      SELECT cl.id, cl.name, cl.type, cl.is_default, cl.is_active, cl.current_balance AS balance,
             cl.notes, a.code AS account_code, a.name AS account_name,
             parent.name AS status, cl.device_id AS reference_id
      FROM cash_locations cl
      LEFT JOIN accounts a ON a.id = cl.account_id
      LEFT JOIN cash_locations parent ON parent.id = cl.parent_id
      WHERE cl.deleted_at = '' AND cl.is_active = 1 $typeFilter
      ORDER BY cl.type, cl.code, cl.name
      ''',
  ).get();
  return rows.map((row) => AdvancedAccountingItem.fromRow(row.data)).toList();
}

Future<bool> hasOpenCashDrawerForDevice(
    {required String deviceId, String branchId = ''}) async {
  if (!isAvailable) return true;
  final drawer = await _openCashDrawerLocationForDevice(
      deviceId: deviceId, branchId: branchId);
  return drawer != null;
}

/// Returns the cash drawer assigned to [deviceId] regardless of whether a
/// drawer session is currently open. Session state is queried separately.
///
/// This distinction is important after closing a shift: the physical drawer
/// remains assigned to the device and must still be available to open the
/// next shift.
Future<AdvancedAccountingItem?> currentCashDrawerForDevice({
  required String deviceId,
  String branchId = '',
}) async {
  if (!isAvailable) return null;
  final cleanDeviceId = deviceId.trim();
  if (cleanDeviceId.isEmpty) return null;
  final branchFilter = branchId.trim().isEmpty
      ? ''
      : "AND (cl.branch_id = ? OR cl.branch_id = '')";
  final row = await _db.customSelect(
    '''
      SELECT cl.id, cl.name, cl.type, cl.is_default, cl.is_active,
             cl.current_balance AS balance, cl.notes,
             a.code AS account_code, a.name AS account_name,
             parent.name AS status, cl.device_id AS reference_id
      FROM cash_locations cl
      LEFT JOIN accounts a ON a.id = cl.account_id
      LEFT JOIN cash_locations parent ON parent.id = cl.parent_id
      WHERE cl.deleted_at = ''
        AND cl.is_active = 1
        AND cl.type = 'cash_drawer'
        AND cl.device_id = ?
        $branchFilter
      ORDER BY cl.is_default DESC, cl.code, cl.name
      LIMIT 1
      ''',
    variables: <Variable<Object>>[
      Variable<String>(cleanDeviceId),
      if (branchId.trim().isNotEmpty) Variable<String>(branchId.trim()),
    ],
  ).getSingleOrNull();
  return row == null ? null : AdvancedAccountingItem.fromRow(row.data);
}

Future<bool> hasOpenCashDrawer(
    {String branchId = '', String cashLocationId = ''}) async {
  if (!isAvailable) return false;
  final locationFilter =
      cashLocationId.trim().isEmpty ? '' : 'AND cash_location_id = ?';
  final branchFilter = branchId.trim().isEmpty ? '' : 'AND branch_id = ?';
  final row = await _db.customSelect(
    '''
      SELECT id
      FROM cash_drawer_sessions
      WHERE status = 'open' $locationFilter $branchFilter
      ORDER BY opened_at DESC
      LIMIT 1
      ''',
    variables: <Variable<Object>>[
      if (cashLocationId.trim().isNotEmpty)
        Variable<String>(cashLocationId.trim()),
      if (branchId.trim().isNotEmpty) Variable<String>(branchId.trim()),
    ],
  ).getSingleOrNull();
  return row != null;
}

Future<String> currentOpenCashDrawerSessionId(
    {String branchId = '', String cashLocationId = ''}) async {
  if (!isAvailable) return '';
  final locationFilter =
      cashLocationId.trim().isEmpty ? '' : 'AND cash_location_id = ?';
  final branchFilter = branchId.trim().isEmpty ? '' : 'AND branch_id = ?';
  final row = await _db.customSelect(
    '''
      SELECT id
      FROM cash_drawer_sessions
      WHERE status = 'open' $locationFilter $branchFilter
      ORDER BY opened_at DESC
      LIMIT 1
      ''',
    variables: <Variable<Object>>[
      if (cashLocationId.trim().isNotEmpty)
        Variable<String>(cashLocationId.trim()),
      if (branchId.trim().isNotEmpty) Variable<String>(branchId.trim()),
    ],
  ).getSingleOrNull();
  return row?.data['id']?.toString() ?? '';
}

Future<List<AdvancedAccountingItem>> listCashLocations() async {
  if (!isAvailable) return const <AdvancedAccountingItem>[];
  final rows = await _db.customSelect(
    '''
      SELECT cl.id, cl.name, cl.type, cl.is_default, cl.is_active, cl.current_balance AS balance,
             cl.notes, a.code AS account_code, a.name AS account_name,
             parent.name AS status, cl.device_id AS reference_id
      FROM cash_locations cl
      LEFT JOIN accounts a ON a.id = cl.account_id
      LEFT JOIN cash_locations parent ON parent.id = cl.parent_id
      WHERE cl.deleted_at = ''
      ORDER BY cl.type, cl.code, cl.name
      ''',
  ).get();
  return rows.map((row) => AdvancedAccountingItem.fromRow(row.data)).toList();
}

Future<List<AdvancedAccountingItem>> listCashTransfers() async {
  if (!isAvailable) return const <AdvancedAccountingItem>[];
  final rows = await _db.customSelect(
    '''
      SELECT ct.id, ct.transfer_no AS name, ct.status AS type, ct.status,
             from_loc.name AS account_code, to_loc.name AS account_name,
             ct.amount AS balance, ct.notes
      FROM cash_transfers ct
      LEFT JOIN cash_locations from_loc ON from_loc.id = ct.from_location_id
      LEFT JOIN cash_locations to_loc ON to_loc.id = ct.to_location_id
      WHERE ct.deleted_at = ''
      ORDER BY ct.transfer_date DESC
      LIMIT 50
      ''',
  ).get();
  return rows.map((row) => AdvancedAccountingItem.fromRow(row.data)).toList();
}

Future<List<CashShiftReportSession>> listClosedCashDrawerSessions(
    {int limit = 200}) async {
  if (!isAvailable) return const <CashShiftReportSession>[];
  final rows = await _db.customSelect(
    '''
      SELECT cds.id, cds.drawer_no, cds.cash_location_id,
             COALESCE(cl.name, '') AS cash_location_name,
             cds.opened_at, cds.closed_at, cds.opening_balance,
             cds.expected_cash, cds.counted_cash, cds.difference,
             cds.notes, cds.opened_by, cds.closed_by, cds.branch_id
      FROM cash_drawer_sessions cds
      LEFT JOIN cash_locations cl ON cl.id = cds.cash_location_id
      WHERE cds.status = 'closed'
      ORDER BY cds.closed_at DESC, cds.opened_at DESC
      LIMIT ?
      ''',
    variables: <Variable<Object>>[Variable<int>(limit.clamp(1, 1000).toInt())],
  ).get();
  return rows
      .map((row) => CashShiftReportSession.fromRow(row.data))
      .toList(growable: false);
}

Future<List<AdvancedAccountingItem>> listCashDrawers() async {
  if (!isAvailable) return const <AdvancedAccountingItem>[];
  final rows = await _db.customSelect(
    '''
      SELECT cds.id, cds.drawer_no AS name, cds.status AS type, cds.status,
             COALESCE(cl.name, cds.opened_at) AS account_name,
             cds.cash_location_id AS reference_id,
             opening_balance AS debit, expected_cash AS credit,
             difference AS balance,
             (CASE WHEN cds.opened_by <> '' THEN 'فتحها: ' || cds.opened_by ELSE '' END ||
              CASE WHEN cds.closed_by <> '' THEN CASE WHEN cds.opened_by <> '' THEN ' • ' ELSE '' END || 'أغلقها: ' || cds.closed_by ELSE '' END ||
              CASE WHEN cds.notes <> '' THEN CASE WHEN cds.opened_by <> '' OR cds.closed_by <> '' THEN ' • ' ELSE '' END || cds.notes ELSE '' END) AS notes
      FROM cash_drawer_sessions cds
      LEFT JOIN cash_locations cl ON cl.id = cds.cash_location_id
      ORDER BY opened_at DESC
      LIMIT 50
      ''',
  ).get();
  return rows.map((row) => AdvancedAccountingItem.fromRow(row.data)).toList();
}

Future<List<AdvancedAccountingItem>> listCashBalancesReport() async {
  if (!isAvailable) return const <AdvancedAccountingItem>[];
  final rows = await _db.customSelect(
    '''
      SELECT cl.id, cl.name, cl.type, cl.is_default, cl.is_active,
             cl.current_balance AS balance,
             a.code AS account_code, a.name AS account_name,
             parent.name AS status,
             ('الكود: ' || cl.code ||
              CASE WHEN cl.branch_id <> '' THEN ' • الفرع: ' || cl.branch_id ELSE '' END ||
              CASE WHEN parent.name IS NOT NULL THEN ' • تابع لـ: ' || parent.name ELSE '' END ||
              CASE WHEN cl.notes <> '' THEN ' • ' || cl.notes ELSE '' END) AS notes
      FROM cash_locations cl
      LEFT JOIN accounts a ON a.id = cl.account_id
      LEFT JOIN cash_locations parent ON parent.id = cl.parent_id
      WHERE cl.deleted_at = ''
      ORDER BY cl.type, cl.code, cl.name
      ''',
  ).get();
  return rows.map((row) => AdvancedAccountingItem.fromRow(row.data)).toList();
}

Future<List<AdvancedAccountingItem>> listOpenCashDrawersReport() async {
  if (!isAvailable) return const <AdvancedAccountingItem>[];
  final rows = await _db.customSelect(
    '''
      SELECT cds.id,
             cds.drawer_no AS name,
             'open' AS type,
             cds.status,
             cl.name AS account_name,
             cds.cash_location_id AS reference_id,
             cds.opening_balance AS debit,
             ROUND(
               cds.opening_balance + COALESCE((
                 SELECT SUM(CASE WHEN clt.direction = 'in' THEN clt.amount ELSE -clt.amount END)
                 FROM cash_ledger_transactions clt
                 WHERE clt.cash_drawer_session_id = cds.id AND clt.deleted_at = ''
               ), 0),
               2
             ) AS credit,
             COALESCE(cl.current_balance, cds.expected_cash) AS balance,
             ('افتتحت: ' || cds.opened_at ||
              CASE WHEN cds.opened_by <> '' THEN ' • بواسطة: ' || cds.opened_by ELSE '' END ||
              CASE WHEN cds.opened_by_user_id <> '' THEN ' • معرف المستخدم: ' || cds.opened_by_user_id ELSE '' END ||
              CASE WHEN cds.branch_id <> '' THEN ' • الفرع: ' || cds.branch_id ELSE '' END ||
              CASE WHEN cds.notes <> '' THEN ' • ' || cds.notes ELSE '' END) AS notes
      FROM cash_drawer_sessions cds
      LEFT JOIN cash_locations cl ON cl.id = cds.cash_location_id
      WHERE cds.status = 'open'
      ORDER BY cds.opened_at DESC
      ''',
  ).get();
  return rows.map((row) => AdvancedAccountingItem.fromRow(row.data)).toList();
}

Future<List<AdvancedAccountingItem>> listCashDrawerVarianceReport(
    {int limit = 100}) async {
  if (!isAvailable) return const <AdvancedAccountingItem>[];
  final rows = await _db.customSelect(
    '''
      SELECT cds.id,
             cds.drawer_no AS name,
             CASE
               WHEN ROUND(cds.difference, 2) > 0 THEN 'overage'
               WHEN ROUND(cds.difference, 2) < 0 THEN 'shortage'
               ELSE 'balanced'
             END AS type,
             cds.status,
             cl.name AS account_name,
             cds.expected_cash AS debit,
             cds.counted_cash AS credit,
             cds.difference AS balance,
             ('افتتحت: ' || cds.opened_at ||
              CASE WHEN cds.closed_at <> '' THEN ' • أغلقت: ' || cds.closed_at ELSE '' END ||
              CASE WHEN cds.opened_by <> '' THEN ' • فتحها: ' || cds.opened_by ELSE '' END ||
              CASE WHEN cds.closed_by <> '' THEN ' • أغلقها: ' || cds.closed_by ELSE '' END ||
              CASE WHEN cds.opened_by_user_id <> '' THEN ' • مستخدم الفتح: ' || cds.opened_by_user_id ELSE '' END ||
              CASE WHEN cds.closed_by_user_id <> '' THEN ' • مستخدم الإغلاق: ' || cds.closed_by_user_id ELSE '' END ||
              CASE WHEN cds.notes <> '' THEN ' • ' || cds.notes ELSE '' END) AS notes
      FROM cash_drawer_sessions cds
      LEFT JOIN cash_locations cl ON cl.id = cds.cash_location_id
      WHERE cds.status = 'closed'
      ORDER BY ABS(cds.difference) DESC, cds.closed_at DESC
      LIMIT ?
      ''',
    variables: <Variable<Object>>[Variable<int>(limit)],
  ).get();
  return rows.map((row) => AdvancedAccountingItem.fromRow(row.data)).toList();
}

Future<List<AdvancedAccountingItem>> listCashTransferAuditReport(
    {int limit = 100}) async {
  if (!isAvailable) return const <AdvancedAccountingItem>[];
  final rows = await _db.customSelect(
    '''
      SELECT ct.id,
             ct.transfer_no AS name,
             ct.status AS type,
             ct.status,
             from_loc.name AS account_code,
             to_loc.name AS account_name,
             ct.amount AS balance,
             ct.journal_entry_id AS reference_id,
             ('التاريخ: ' || ct.transfer_date ||
              CASE WHEN ct.created_by <> '' THEN ' • أنشأها: ' || ct.created_by ELSE '' END ||
              CASE WHEN ct.approved_by <> '' THEN ' • اعتمدها: ' || ct.approved_by ELSE '' END ||
              CASE WHEN ct.journal_entry_id <> '' THEN ' • قيد: ' || ct.journal_entry_id ELSE '' END ||
              CASE WHEN ct.notes <> '' THEN ' • ' || ct.notes ELSE '' END) AS notes
      FROM cash_transfers ct
      LEFT JOIN cash_locations from_loc ON from_loc.id = ct.from_location_id
      LEFT JOIN cash_locations to_loc ON to_loc.id = ct.to_location_id
      WHERE ct.deleted_at = ''
      ORDER BY ct.transfer_date DESC
      LIMIT ?
      ''',
    variables: <Variable<Object>>[Variable<int>(limit)],
  ).get();
  return rows.map((row) => AdvancedAccountingItem.fromRow(row.data)).toList();
}

Future<double> calculateCashDrawerExpectedCash(String sessionId) async {
  if (!isAvailable) return 0.0;
  final row = await _db.customSelect(
    """
      SELECT opening_balance
      FROM cash_drawer_sessions
      WHERE id = ? AND status = 'open'
      LIMIT 1
      """,
    variables: <Variable<Object>>[Variable<String>(sessionId)],
  ).getSingleOrNull();
  if (row == null) return 0;
  final openingBalance = _roundMoney(_num(row.data['opening_balance']));
  final movement =
      await CashLedgerService(_db).movementTotalForSession(sessionId);
  return _roundMoney(openingBalance + movement);
}

Future<List<AdvancedAccountingItem>> listCheques() async {
  if (!isAvailable) return const <AdvancedAccountingItem>[];
  final rows = await _db.customSelect(
    '''
      SELECT id, cheque_no AS name, direction AS type, party_name AS account_name,
             amount AS balance, status, due_date AS notes
      FROM cheques
      ORDER BY due_date ASC, created_at DESC
      LIMIT 100
      ''',
  ).get();
  return rows.map((row) => AdvancedAccountingItem.fromRow(row.data)).toList();
}

Future<List<AdvancedAccountingItem>> listAccountingPeriods() async {
  if (!isAvailable) return const <AdvancedAccountingItem>[];
  final rows = await _db.customSelect(
    '''
      SELECT id, name, status AS type, start_date AS account_code,
             end_date AS account_name, notes
      FROM accounting_periods
      ORDER BY start_date DESC
      LIMIT 50
      ''',
  ).get();
  return rows.map((row) => AdvancedAccountingItem.fromRow(row.data)).toList();
}

Future<List<AdvancedAccountingItem>> listCostCenters() async {
  if (!isAvailable) return const <AdvancedAccountingItem>[];
  final rows = await _db.customSelect(
    '''
      SELECT id, name, code AS account_code, is_active, notes
      FROM cost_centers
      WHERE deleted_at = ''
      ORDER BY code
      ''',
  ).get();
  return rows.map((row) => AdvancedAccountingItem.fromRow(row.data)).toList();
}

Future<List<AdvancedAccountingItem>> listAccountingBranches() async {
  if (!isAvailable) return const <AdvancedAccountingItem>[];
  final rows = await _db.customSelect(
    '''
      SELECT id, name, code AS account_code, is_active, notes
      FROM accounting_branches
      WHERE deleted_at = ''
      ORDER BY code
      ''',
  ).get();
  return rows.map((row) => AdvancedAccountingItem.fromRow(row.data)).toList();
}

Future<List<AdvancedAccountingItem>> listGeneralLedgerBranches() async {
  if (!isAvailable) return const <AdvancedAccountingItem>[];
  final rows = await _db.customSelect(
    r'''
      SELECT DISTINCT
             je.branch_id AS id,
             COALESCE(
               (SELECT ab.name
                FROM accounting_branches ab
                WHERE ab.deleted_at = ''
                  AND (ab.id = je.branch_id OR UPPER(ab.code) = UPPER(je.branch_id))
                LIMIT 1),
               je.branch_id
             ) AS name,
             COALESCE(
               (SELECT ab.code
                FROM accounting_branches ab
                WHERE ab.deleted_at = ''
                  AND (ab.id = je.branch_id OR UPPER(ab.code) = UPPER(je.branch_id))
                LIMIT 1),
               je.branch_id
             ) AS account_code,
             1 AS is_active,
             '' AS notes
      FROM journal_entries je
      WHERE je.deleted_at = '' AND je.branch_id <> ''
      ORDER BY account_code
      ''',
  ).get();
  return rows.map((row) => AdvancedAccountingItem.fromRow(row.data)).toList();
}

Future<List<AdvancedAccountingItem>> listFixedAssets() async {
  if (!isAvailable) return const <AdvancedAccountingItem>[];
  final rows = await _db.customSelect(
    '''
      SELECT fa.id, fa.name, fa.category AS type, fa.status,
             fa.code AS account_code, a.name AS account_name,
             ROUND(fa.purchase_value - COALESCE(dep.accumulated, 0), 2) AS balance,
             ('التكلفة: ' || ROUND(fa.purchase_value, 2) ||
              ' • مجمع الإهلاك: ' || ROUND(COALESCE(dep.accumulated, 0), 2) ||
              ' • القيمة الدفترية: ' || ROUND(fa.purchase_value - COALESCE(dep.accumulated, 0), 2) ||
              ' • تاريخ الاقتناء: ' || fa.acquisition_date ||
              CASE WHEN fa.useful_life_months > 0 THEN ' • العمر الإنتاجي: ' || fa.useful_life_months || ' شهر' ELSE '' END ||
              CASE WHEN fa.useful_life_months > 0 THEN ' • الإهلاك الشهري: ' || ROUND(fa.purchase_value / fa.useful_life_months, 2) ELSE '' END ||
              CASE WHEN fa.notes <> '' THEN ' • ' || fa.notes ELSE '' END) AS notes
      FROM fixed_assets fa
      LEFT JOIN accounts a ON a.id = fa.asset_account_id
      LEFT JOIN (
        SELECT asset_id, SUM(amount) AS accumulated
        FROM fixed_asset_depreciation
        WHERE deleted_at = ''
        GROUP BY asset_id
      ) dep ON dep.asset_id = fa.id
      WHERE fa.deleted_at = ''
      ORDER BY fa.acquisition_date DESC, fa.code
      LIMIT 200
      ''',
  ).get();
  return rows.map((row) => AdvancedAccountingItem.fromRow(row.data)).toList();
}
