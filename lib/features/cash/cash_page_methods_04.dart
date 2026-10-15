part of 'cash_page.dart';

extension _CashPageStatePart4 on _CashPageState {

  Future<void> _showShiftReportsDialog() async {
    final tr = AppLocalizations.of(context);
    var detailed = false;
    var printingSessionId = '';
    final sessionsFuture =
        AccountingService.listClosedCashDrawerSessions(limit: 500);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.summarize_outlined),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(_l(
                      tr, 'Closed shift reports', 'تقارير الورديات المغلقة'))),
            ],
          ),
          content: SizedBox(
            width: 900,
            height: 560,
            child: Column(
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(detailed
                      ? _l(tr, 'Detailed report', 'تقرير مفصل')
                      : _l(tr, 'Summary report', 'تقرير ملخص')),
                  subtitle: Text(_l(
                    tr,
                    detailed
                        ? 'Printing includes every cash movement linked to the selected shift.'
                        : 'Printing includes the closing summary for the selected shift only.',
                    detailed
                        ? 'الطباعة تشمل جميع حركات الصندوق المرتبطة بالوردية المختارة.'
                        : 'الطباعة تشمل ملخص إغلاق الوردية المختارة فقط.',
                  )),
                  value: detailed,
                  onChanged: (value) => setDialogState(() => detailed = value),
                ),
                const Divider(),
                Expanded(
                  child: FutureBuilder<List<CashShiftReportSession>>(
                    future: sessionsFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return Center(
                            child: Text(localizeRuntimeMessage(
                                snapshot.error.toString(), tr)));
                      }
                      final sessions =
                          snapshot.data ?? const <CashShiftReportSession>[];
                      if (sessions.isEmpty) {
                        return Center(
                            child: Text(_l(tr, 'No closed shifts found.',
                                'لا توجد ورديات مغلقة.')));
                      }
                      return ListView.separated(
                        itemCount: sessions.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final session = sessions[index];
                          String date(DateTime? value) {
                            if (value == null) return '—';
                            final d = value.toLocal();
                            String two(int n) => n.toString().padLeft(2, '0');
                            return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
                          }

                          final isPrinting = printingSessionId == session.id;
                          return ListTile(
                            leading: const Icon(Icons.lock_outline_rounded),
                            title: Text(
                              '${session.drawerNo.isEmpty ? session.id : session.drawerNo} • ${session.cashLocationName}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${_l(tr, 'Closed', 'أغلقت')}: ${date(session.closedAt)} • '
                              '${_l(tr, 'Expected', 'المتوقع')}: ${formatUsdReferenceAmount(session.expectedCash, widget.store.runtime.profile)} • '
                              '${_l(tr, 'Counted', 'المعدود')}: ${formatUsdReferenceAmount(session.countedCash, widget.store.runtime.profile)} • '
                              '${_l(tr, 'Difference', 'الفرق')}: ${formatUsdReferenceAmount(session.difference, widget.store.runtime.profile)}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: FilledButton.tonalIcon(
                              onPressed: isPrinting
                                  ? null
                                  : () async {
                                      final printDetailed = detailed;
                                      setDialogState(
                                          () => printingSessionId = session.id);
                                      try {
                                        final movements =
                                            await _loadAllShiftMovements(
                                                session.id);
                                        if (!dialogContext.mounted) return;
                                        await CashShiftReportPdfService
                                            .printShift(
                                          context: dialogContext,
                                          session: session,
                                          movements: movements,
                                          detailed: printDetailed,
                                          profile: widget.store.runtime.profile,
                                          locale: Localizations.localeOf(
                                              dialogContext),
                                        );
                                      } catch (error) {
                                        if (dialogContext.mounted) {
                                          ScaffoldMessenger.of(dialogContext)
                                              .showSnackBar(
                                            SnackBar(
                                                content: Text(
                                                    localizeRuntimeMessage(
                                                        error.toString(), tr))),
                                          );
                                        }
                                      } finally {
                                        if (dialogContext.mounted) {
                                          setDialogState(
                                              () => printingSessionId = '');
                                        }
                                      }
                                    },
                              icon: isPrinting
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : const Icon(Icons.print_outlined),
                              label: Text(_l(tr, 'Print', 'طباعة')),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(tr.text('close')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pageHeader(
    BuildContext context,
    AppLocalizations tr,
    AdvancedAccountingItem? currentDrawer,
    AdvancedAccountingItem? currentSession,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.point_of_sale_outlined, color: scheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                currentDrawer == null
                    ? tr.text('cash_box')
                    : '${tr.text('cash_box')} • ${currentDrawer.name}',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                currentSession == null
                    ? _l(tr, 'No open shift', 'لا توجد وردية مفتوحة')
                    : _l(tr, 'Open shift • live cash overview',
                        'وردية مفتوحة • ملخص النقد المباشر'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
        OutlinedButton.icon(
          onPressed: _showShiftReportsDialog,
          icon: const Icon(Icons.summarize_outlined),
          label: Text(_l(tr, 'Reports', 'تقارير')),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: _l(tr, 'Refresh', 'تحديث'),
          onPressed: _refresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    );
  }

  Widget _dashboardMetric(
    BuildContext context, {
    required double width,
    required String label,
    required String value,
    required IconData icon,
    bool emphasize = false,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SizedBox(
      width: width,
      child: Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color:
                      scheme.primary.withValues(alpha: emphasize ? 0.10 : 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: scheme.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quickActionsCard(
    BuildContext context,
    AppLocalizations tr, {
    required bool canManage,
    required AdvancedAccountingItem? currentDrawer,
    required AdvancedAccountingItem? currentSession,
  }) {
    final enabled =
        canManage && currentDrawer != null && currentSession != null;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _l(tr, 'Quick actions', 'عمليات سريعة'),
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (currentSession == null)
                  FilledButton.icon(
                    onPressed: canManage && currentDrawer != null
                        ? () => _openDrawerDialog(
                              context,
                              <AdvancedAccountingItem>[currentDrawer],
                            )
                        : null,
                    icon: const Icon(Icons.lock_open_outlined),
                    label: Text(tr.text('open_shift')),
                  ),
                OutlinedButton.icon(
                  onPressed: enabled && widget.store.security.canManageCustomerPayments
                      ? () => _settleSaleInvoiceDialog(currentDrawer)
                      : null,
                  icon: const Icon(Icons.arrow_downward_rounded),
                  label: Text(_l(tr, 'Receipt', 'قبض')),
                ),
                OutlinedButton.icon(
                  onPressed: enabled && widget.store.security.canManageSupplierPayments
                      ? () => _settlePurchaseInvoiceDialog(currentDrawer)
                      : null,
                  icon: const Icon(Icons.arrow_upward_rounded),
                  label: Text(_l(tr, 'Payment', 'دفع')),
                ),
                OutlinedButton.icon(
                  onPressed: enabled && widget.store.security.canManageSupplierPayments
                      ? _refundPurchaseReturnDialog
                      : null,
                  icon: const Icon(Icons.assignment_return_outlined),
                  label: Text(_l(
                    tr,
                    'Purchase return refund',
                    'استرداد مرتجع',
                  )),
                ),
                OutlinedButton.icon(
                  onPressed: enabled &&
                          (widget.store.security.canDeleteOrCancel ||
                              widget.store.security.canManageSupplierPayments ||
                              widget.store.security.canManageExpenses)
                      ? _refundDialog
                      : null,
                  icon: const Icon(Icons.currency_exchange_rounded),
                  label: Text(_l(tr, 'Refund', 'استرداد')),
                ),
                OutlinedButton.icon(
                  onPressed: enabled && widget.store.security.canManageExpenses
                      ? () =>
                          _settleExpenseDialog(currentDrawer, currentSession)
                      : null,
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: Text(_l(tr, 'Expenses', 'مصاريف')),
                ),
                OutlinedButton.icon(
                  onPressed: enabled
                      ? () => _cashTransferDialog(
                            currentDrawer: currentDrawer,
                            currentSession: currentSession,
                            kind: 'vault_transfer',
                          )
                      : null,
                  icon: const Icon(Icons.swap_horiz_rounded),
                  label: Text(_l(tr, 'Transfer', 'تحويل')),
                ),
                PopupMenuButton<String>(
                  enabled: enabled,
                  tooltip:
                      _l(tr, 'More cash operations', 'عمليات نقدية إضافية'),
                  onSelected: (value) {
                    if (currentDrawer == null || currentSession == null) return;
                    if (value == 'vault_transfer' ||
                        value == 'shift_transfer') {
                      _cashTransferDialog(
                        currentDrawer: currentDrawer,
                        currentSession: currentSession,
                        kind: value,
                      );
                    } else {
                      _cashOperationDialog(
                        currentDrawer: currentDrawer,
                        currentSession: currentSession,
                        type: value,
                      );
                    }
                  },
                  itemBuilder: (context) => <PopupMenuEntry<String>>[
                    PopupMenuItem(
                      value: 'cash_deposit',
                      child: Text(_l(tr, 'Cash deposit', 'إيداع نقدي')),
                    ),
                    PopupMenuItem(
                      value: 'cash_withdrawal',
                      child: Text(_l(tr, 'Cash withdrawal', 'سحب نقدي')),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'vault_transfer',
                      child: Text(_l(tr, 'Vault transfer', 'تحويل خزنة')),
                    ),
                    PopupMenuItem(
                      value: 'shift_transfer',
                      child: Text(_l(tr, 'Shift transfer', 'تحويل شيفت')),
                    ),
                  ],
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.more_horiz_rounded, size: 20),
                        const SizedBox(width: 6),
                        Text(_l(tr, 'More', 'المزيد')),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _shiftSummaryCard(
    BuildContext context,
    AppLocalizations tr, {
    required AdvancedAccountingItem currentDrawer,
    required AdvancedAccountingItem? currentSession,
    required bool canManage,
    bool compact = false,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    String money(double value) =>
        formatUsdReferenceAmount(value, widget.store.runtime.profile);
    if (currentSession == null) {
      return Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_clock_outlined,
                  size: 34, color: scheme.onSurfaceVariant),
              const SizedBox(height: 10),
              Text(
                tr.text('no_open_cash_shift'),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: canManage
                    ? () => _openDrawerDialog(
                          context,
                          <AdvancedAccountingItem>[currentDrawer],
                        )
                    : null,
                icon: const Icon(Icons.lock_open_outlined),
                label: Text(tr.text('open_shift')),
              ),
            ],
          ),
        ),
      );
    }

    final opening = currentSession.debit;
    final expected = currentSession.credit;
    final actual = currentDrawer.balance;
    final shiftNet = expected - opening;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.assessment_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _l(tr, 'Shift summary', 'ملخص الوردية'),
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _l(tr, 'Open', 'مفتوحة'),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _shiftLine(context, _l(tr, 'Opening balance', 'رصيد الافتتاح'),
                money(opening)),
            _shiftLine(
                context, _l(tr, 'Shift net', 'صافي الوردية'), money(shiftNet)),
            _shiftLine(context, _l(tr, 'Expected balance', 'الرصيد المتوقع'),
                money(expected)),
            _shiftLine(context, _l(tr, 'Current balance', 'الرصيد الحالي'),
                money(actual),
                strong: true),
            if (!compact) const Spacer(),
            if (currentSession.notes.trim().isNotEmpty) ...[
              const Divider(height: 24),
              Text(
                currentSession.notes,
                maxLines: compact ? 1 : 4,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: canManage
                  ? () => _closeDrawerDialog(context, currentSession)
                  : null,
              icon: const Icon(Icons.lock_outline),
              label: Text(_l(tr, 'Close shift', 'إغلاق الوردية')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shiftLine(
    BuildContext context,
    String label,
    String value, {
    bool strong = false,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
