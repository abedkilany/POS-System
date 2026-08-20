import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/services/cash_ledger_service.dart';
import '../../core/services/cash_receipt_pdf_service.dart';
import '../../core/services/payment_voucher_service.dart';
import '../../core/services/cash_reversal_service.dart';
import '../../core/storage/sqlite/sqlite_migration_manager.dart';
import '../../core/utils/currency_utils.dart';
import '../../data/app_store.dart';
import '../../models/cash_ledger_transaction.dart';

class CashHistoryPanel extends StatefulWidget {
  const CashHistoryPanel({
    super.key,
    required this.store,
    required this.cashLocationId,
    required this.currentSessionId,
    required this.refreshKey,
  });

  final AppStore store;
  final String cashLocationId;
  final String currentSessionId;
  final int refreshKey;

  @override
  State<CashHistoryPanel> createState() => _CashHistoryPanelState();
}

class _CashHistoryPanelState extends State<CashHistoryPanel> {
  static const int _pageSize = 25;
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  int _page = 0;
  String _direction = '';
  String _type = '';
  late Future<_CashHistorySnapshot> _future;

  CashLedgerService get _ledger => CashLedgerService.current();

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant CashHistoryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshKey != widget.refreshKey ||
        oldWidget.cashLocationId != widget.cashLocationId ||
        oldWidget.currentSessionId != widget.currentSessionId) {
      _page = 0;
      _reload();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  String _l(AppLocalizations tr, String en, String ar) => tr.isArabic ? ar : en;

  Future<_CashHistorySnapshot> _load() async {
    if (widget.cashLocationId.trim().isEmpty) {
      return const _CashHistorySnapshot(
        rows: <CashLedgerTransaction>[],
        total: 0,
        summary: CashLedgerSummary(movementCount: 0, cashIn: 0, cashOut: 0),
      );
    }
    final database = SqliteMigrationManager.database;
    if (database != null) {
      // Phase 4 reads only Cash Ledger. Older vouchers can exist without a
      // matching ledger row, so materialize their immutable history first.
      // This never changes the stored cash balance and is idempotent.
      await PaymentVoucherService(database).backfillLegacyCashLedger();
    }
    final sessionId = widget.currentSessionId.trim();
    if (sessionId.isEmpty) {
      return const _CashHistorySnapshot(
        rows: <CashLedgerTransaction>[],
        total: 0,
        summary: CashLedgerSummary(movementCount: 0, cashIn: 0, cashOut: 0),
      );
    }
    // The cash history is intentionally locked to the open shift. The
    // cash_drawer_session_id is authoritative, so no date window is applied.
    // This also prevents legacy document dates from hiding movements that
    // belong to the current shift.
    DateTime? from;
    DateTime? to;
    final args = (
      cashLocationId: widget.cashLocationId,
      cashDrawerSessionId: sessionId,
      direction: _direction,
      type: _type,
      search: _searchController.text.trim(),
      from: from,
      to: to,
    );
    final rowsFuture = _ledger.list(
      cashLocationId: args.cashLocationId,
      cashDrawerSessionId: args.cashDrawerSessionId,
      direction: args.direction,
      type: args.type,
      search: args.search,
      from: args.from,
      to: args.to,
      limit: _pageSize,
      offset: _page * _pageSize,
    );
    final countFuture = _ledger.count(
      cashLocationId: args.cashLocationId,
      cashDrawerSessionId: args.cashDrawerSessionId,
      direction: args.direction,
      type: args.type,
      search: args.search,
      from: args.from,
      to: args.to,
    );
    final summaryFuture = _ledger.summary(
      cashLocationId: args.cashLocationId,
      cashDrawerSessionId: args.cashDrawerSessionId,
      direction: args.direction,
      type: args.type,
      search: args.search,
      from: args.from,
      to: args.to,
    );
    final rows = await rowsFuture;
    final total = await countFuture;
    final summary = await summaryFuture;
    return _CashHistorySnapshot(rows: rows, total: total, summary: summary);
  }

  void _reload() {
    if (!mounted) return;
    setState(() => _future = _load());
  }

  void _changeFilter(VoidCallback change) {
    setState(() {
      change();
      _page = 0;
      _future = _load();
    });
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _changeFilter(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                const Icon(Icons.history_rounded),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _l(tr, 'Cash history', 'سجل حركة الصندوق'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: _l(tr, 'Refresh', 'تحديث'),
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 270,
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search_rounded),
                      hintText: _l(tr, 'Invoice, party, user, note…', 'فاتورة، طرف، مستخدم، ملاحظة…'),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _searchController.clear();
                                _changeFilter(() {});
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                    ),
                  ),
                ),
                DropdownButton<String>(
                  value: _direction,
                  onChanged: (value) => _changeFilter(() => _direction = value ?? ''),
                  items: [
                    DropdownMenuItem(value: '', child: Text(_l(tr, 'All directions', 'كل الاتجاهات'))),
                    DropdownMenuItem(value: 'in', child: Text(_l(tr, 'Cash in', 'داخل'))),
                    DropdownMenuItem(value: 'out', child: Text(_l(tr, 'Cash out', 'خارج'))),
                  ],
                ),
                DropdownButton<String>(
                  value: _type,
                  onChanged: (value) => _changeFilter(() => _type = value ?? ''),
                  items: [
                    DropdownMenuItem(value: '', child: Text(_l(tr, 'All types', 'كل الأنواع'))),
                    DropdownMenuItem(value: 'receipt', child: Text(_l(tr, 'Receipt', 'قبض'))),
                    DropdownMenuItem(value: 'supplier_payment', child: Text(_l(tr, 'Supplier payment', 'دفع مورد'))),
                    DropdownMenuItem(value: 'cash_deposit', child: Text(_l(tr, 'Cash deposit', 'إيداع نقدي'))),
                    DropdownMenuItem(value: 'cash_withdrawal', child: Text(_l(tr, 'Cash withdrawal', 'سحب نقدي'))),
                    DropdownMenuItem(value: 'expense', child: Text(_l(tr, 'Expense', 'مصروف'))),
                    DropdownMenuItem(value: 'vault_transfer', child: Text(_l(tr, 'Vault transfer', 'تحويل خزنة'))),
                    DropdownMenuItem(value: 'shift_transfer', child: Text(_l(tr, 'Shift transfer', 'تحويل شيفت'))),
                    DropdownMenuItem(value: 'refund', child: Text(_l(tr, 'Refund', 'استرداد'))),
                    DropdownMenuItem(value: 'supplier_refund', child: Text(_l(tr, 'Supplier refund', 'استرداد من مورد'))),
                    DropdownMenuItem(value: 'shortage', child: Text(_l(tr, 'Cash shortage', 'عجز نقدي'))),
                    DropdownMenuItem(value: 'overage', child: Text(_l(tr, 'Cash overage', 'زيادة نقدية'))),
                    DropdownMenuItem(value: 'reversal', child: Text(_l(tr, 'Reversal', 'عكس حركة'))),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: FutureBuilder<_CashHistorySnapshot>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(localizeRuntimeMessage(snapshot.error.toString(), tr), textAlign: TextAlign.center),
                    ),
                  );
                }
                final data = snapshot.data ?? const _CashHistorySnapshot(
                  rows: <CashLedgerTransaction>[],
                  total: 0,
                  summary: CashLedgerSummary(movementCount: 0, cashIn: 0, cashOut: 0),
                );
                return Column(
                  children: [
                    _summaryBar(context, tr, data.summary),
                    const Divider(height: 1),
                    Expanded(
                      child: data.rows.isEmpty
                          ? Center(child: Text(_l(tr, 'No cash movements found.', 'لا توجد حركات صندوق مطابقة.')))
                          : ListView.separated(
                              itemCount: data.rows.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, index) => _movementTile(context, tr, data.rows[index]),
                            ),
                    ),
                    const Divider(height: 1),
                    _pager(context, tr, data.total),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryBar(BuildContext context, AppLocalizations tr, CashLedgerSummary value) {
    String money(double amount) => formatUsdReferenceAmount(amount, widget.store.storeProfile);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Wrap(
        spacing: 22,
        runSpacing: 8,
        children: [
          _summaryItem(context, _l(tr, 'Movements', 'الحركات'), '${value.movementCount}', Icons.receipt_long_outlined),
          _summaryItem(context, _l(tr, 'In', 'داخل'), money(value.cashIn), Icons.south_west_rounded),
          _summaryItem(context, _l(tr, 'Out', 'خارج'), money(value.cashOut), Icons.north_east_rounded),
          _summaryItem(context, _l(tr, 'Net', 'الصافي'), money(value.net), Icons.account_balance_wallet_outlined),
        ],
      ),
    );
  }

  Widget _summaryItem(BuildContext context, String label, String value, IconData icon) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 6),
        Text('$label: ', style: Theme.of(context).textTheme.bodySmall),
        Text(value, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800)),
      ],
    );
  }

  Widget _movementTile(BuildContext context, AppLocalizations tr, CashLedgerTransaction item) {
    final incoming = item.direction == 'in';
    final reference = item.referenceNumber.trim().isNotEmpty ? item.referenceNumber : item.referenceId;
    final subtitleParts = <String>[
      DateFormat('yyyy-MM-dd HH:mm:ss').format(item.occurredAt.toLocal()),
      if (reference.trim().isNotEmpty) reference,
      if (item.partyName.trim().isNotEmpty) item.partyName,
      if (item.createdBy.trim().isNotEmpty) item.createdBy,
    ];
    return ListTile(
      onTap: () => _showDetails(item),
      leading: CircleAvatar(
        child: Icon(incoming ? Icons.south_west_rounded : Icons.north_east_rounded),
      ),
      title: Text(_typeLabel(tr, item.type), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitleParts.join(' • '), maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Text(
        '${incoming ? '+' : '-'}${formatUsdReferenceAmount(item.amount, widget.store.storeProfile)}',
        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
      ),
    );
  }

  Widget _pager(BuildContext context, AppLocalizations tr, int total) {
    final pageCount = total == 0 ? 1 : ((total - 1) ~/ _pageSize) + 1;
    if (_page >= pageCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _changeFilter(() => _page = pageCount - 1);
      });
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: [
          Text(_l(tr, '$total movement(s)', '$total حركة')),
          const Spacer(),
          IconButton(
            tooltip: _l(tr, 'Previous', 'السابق'),
            onPressed: _page > 0 ? () => _changeFilter(() => _page--) : null,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Text('${_page + 1} / $pageCount'),
          IconButton(
            tooltip: _l(tr, 'Next', 'التالي'),
            onPressed: (_page + 1) * _pageSize < total ? () => _changeFilter(() => _page++) : null,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }

  Future<void> _showDetails(CashLedgerTransaction item) async {
    final tr = AppLocalizations.of(context);
    final future = _ledger.detailsFor(item);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_l(tr, 'Cash movement details', 'تفاصيل حركة الصندوق')),
        content: SizedBox(
          width: 560,
          child: FutureBuilder<CashLedgerDetails>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox(height: 180, child: Center(child: CircularProgressIndicator()));
              }
              final details = snapshot.data;
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _detailRow(tr, _l(tr, 'Transaction ID', 'رقم الحركة'), item.id),
                    _detailRow(tr, _l(tr, 'Type', 'النوع'), _typeLabel(tr, item.type)),
                    _detailRow(tr, _l(tr, 'Direction', 'الاتجاه'), item.direction == 'in' ? _l(tr, 'In', 'داخل') : _l(tr, 'Out', 'خارج')),
                    _detailRow(tr, _l(tr, 'Amount', 'المبلغ'), '${item.amount.toStringAsFixed(2)} ${item.currency}'),
                    _detailRow(tr, _l(tr, 'Occurred at', 'وقت الحركة'), DateFormat('yyyy-MM-dd HH:mm:ss').format(item.occurredAt.toLocal())),
                    _detailRow(tr, _l(tr, 'Cash drawer', 'الصندوق'), details == null ? item.cashLocationId : '${details.cashLocationName}${details.cashLocationCode.isEmpty ? '' : ' (${details.cashLocationCode})'}'),
                    _detailRow(tr, _l(tr, 'Shift', 'الوردية'), details?.sessionNumber.isNotEmpty == true ? '${details!.sessionNumber} • ${details.sessionStatus}' : item.cashDrawerSessionId),
                    _detailRow(tr, _l(tr, 'Party', 'الطرف'), item.partyName),
                    _detailRow(tr, _l(tr, 'Reference', 'المرجع'), [item.referenceType, item.referenceNumber, item.referenceId].where((e) => e.trim().isNotEmpty).join(' • ')),
                    _detailRow(tr, _l(tr, 'Payment method', 'وسيلة الدفع'), item.paymentMethod),
                    _detailRow(tr, _l(tr, 'User', 'المستخدم'), item.createdBy),
                    _detailRow(tr, _l(tr, 'Device', 'الجهاز'), item.deviceId),
                    _detailRow(tr, _l(tr, 'Branch', 'الفرع'), item.branchId),
                    _detailRow(tr, _l(tr, 'Notes', 'الملاحظات'), item.notes),
                    if (details?.allocationReferences.isNotEmpty == true)
                      _detailRow(
                        tr,
                        _l(tr, 'Allocated invoices', 'الفواتير المخصصة'),
                        details!.allocationReferences
                            .map((allocation) => '${allocation.referenceNumber.isNotEmpty ? allocation.referenceNumber : allocation.referenceId} • ${allocation.amount.toStringAsFixed(2)} ${allocation.currency}')
                            .join('\n'),
                      ),
                    _detailRow(tr, _l(tr, 'Journal entry', 'القيد المحاسبي'), details?.journalEntryNo.isNotEmpty == true ? '${details!.journalEntryNo} • ${details.journalStatus}' : _l(tr, 'Not linked', 'غير مرتبط')),
                    if (details?.journalDescription.isNotEmpty == true)
                      _detailRow(tr, _l(tr, 'Journal description', 'وصف القيد'), details!.journalDescription),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              try {
                await CashReceiptPdfService.printReceipt(
                  transaction: item,
                  profile: widget.store.storeProfile,
                  locale: Localizations.localeOf(context),
                );
              } catch (error) {
                if (!dialogContext.mounted) return;
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(content: Text(localizeRuntimeMessage(error.toString(), tr))),
                );
              }
            },
            icon: const Icon(Icons.print_outlined),
            label: Text(_l(tr, 'Print receipt', 'طباعة الإيصال')),
          ),
          if (widget.store.canManageAccounting &&
              item.reversalOfId.isEmpty &&
              item.type != 'reversal' &&
              (<String>{
                'cash_deposit',
                'cash_withdrawal',
                'cash_transfer',
                'receipt_voucher',
                'payment_voucher',
                'sale_refund',
                'purchase_refund',
              }.contains(item.referenceType) ||
                  (item.referenceType == 'expense' &&
                      item.referenceId.startsWith('cashop'))))
            TextButton.icon(
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: dialogContext,
                  builder: (confirmContext) => AlertDialog(
                    title: Text(_l(tr, 'Reverse cash movement', 'عكس حركة الصندوق')),
                    content: Text(_l(
                      tr,
                      'The original movement will remain in history and an opposite reversal will be posted.',
                      'ستبقى الحركة الأصلية في السجل وسيتم إنشاء حركة عكس مقابلة لها.',
                    )),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(confirmContext, false),
                        child: Text(_l(tr, 'Cancel', 'إلغاء')),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(confirmContext, true),
                        child: Text(_l(tr, 'Reverse', 'عكس')),
                      ),
                    ],
                  ),
                );
                if (confirmed != true) return;
                try {
                  final reversed = await CashReversalService.current().reverseReference(
                    referenceType: item.referenceType,
                    referenceId: item.referenceId,
                    reason: 'Cash history reversal',
                    createdBy: widget.store.currentUser?.fullName.trim().isNotEmpty == true
                        ? widget.store.currentUser!.fullName.trim()
                        : (widget.store.currentUser?.username ?? widget.store.currentRole),
                    createdByUserId: widget.store.currentUser?.id ?? '',
                    deviceId: widget.store.appIdentity.deviceId,
                  );
                  if (reversed <= 0) {
                    throw StateError(_l(
                      tr,
                      'The cash movement was not reversed.',
                      'لم يتم عكس حركة الصندوق.',
                    ));
                  }
                  await widget.store.refreshAccountTransactionsFromSqlite();
                  if (!dialogContext.mounted) return;
                  Navigator.pop(dialogContext);
                  _reload();
                } catch (error) {
                  if (!dialogContext.mounted) return;
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(content: Text(localizeRuntimeMessage(error.toString(), tr))),
                  );
                }
              },
              icon: const Icon(Icons.undo_rounded),
              label: Text(_l(tr, 'Reverse', 'عكس')),
            ),
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(_l(tr, 'Close', 'إغلاق'))),
        ],
      ),
    );
  }

  Widget _detailRow(AppLocalizations tr, String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 150, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
          const SizedBox(width: 10),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }

  String _typeLabel(AppLocalizations tr, String value) {
    switch (value) {
      case 'receipt':
        return _l(tr, 'Customer receipt', 'قبض من عميل');
      case 'supplier_payment':
        return _l(tr, 'Supplier payment', 'دفع لمورد');
      case 'sale_payment':
        return _l(tr, 'Sale payment', 'دفع بيع');
      case 'purchase_payment':
        return _l(tr, 'Purchase payment', 'دفع شراء');
      case 'expense':
        return _l(tr, 'Expense', 'مصروف');
      case 'cash_in':
        return _l(tr, 'Cash in', 'إدخال نقدي');
      case 'cash_out':
        return _l(tr, 'Cash out', 'إخراج نقدي');
      case 'cash_deposit':
        return _l(tr, 'Cash deposit', 'إيداع نقدي');
      case 'cash_withdrawal':
        return _l(tr, 'Cash withdrawal', 'سحب نقدي');
      case 'vault_transfer':
        return _l(tr, 'Vault transfer', 'تحويل خزنة');
      case 'shift_transfer':
        return _l(tr, 'Shift transfer', 'تحويل شيفت');
      case 'refund':
        return _l(tr, 'Refund', 'استرداد');
      case 'supplier_refund':
        return _l(tr, 'Supplier refund', 'استرداد من مورد');
      case 'shortage':
        return _l(tr, 'Cash shortage', 'عجز نقدي');
      case 'overage':
        return _l(tr, 'Cash overage', 'زيادة نقدية');
      case 'reversal':
        return _l(tr, 'Reversal', 'عكس حركة');
      case 'closing':
        return _l(tr, 'Closing', 'إغلاق');
      case 'opening':
        return _l(tr, 'Opening', 'افتتاح');
      default:
        return value.trim().isEmpty ? _l(tr, 'Cash movement', 'حركة نقدية') : value;
    }
  }
}

class _CashHistorySnapshot {
  const _CashHistorySnapshot({required this.rows, required this.total, required this.summary});
  final List<CashLedgerTransaction> rows;
  final int total;
  final CashLedgerSummary summary;
}
