import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/services/accounting_service.dart';
import '../../core/services/cash_operation_service.dart';
import '../../core/services/cash_ledger_service.dart';
import '../../core/services/cash_shift_report_pdf_service.dart';
import '../../core/services/local_database_service.dart';
import '../../core/utils/currency_utils.dart';
import '../../core/utils/responsive.dart';
import '../../data/app_store.dart';
import '../../models/accounting_account.dart';
import '../../models/cash_ledger_transaction.dart';
import '../../models/expense.dart';
import '../../models/purchase.dart';
import '../../models/sale.dart';
import '../../models/user_role.dart';
import 'cash_history_panel.dart';
part 'cash_page_methods_01.dart';
part 'cash_page_methods_02.dart';
part 'cash_page_methods_03.dart';
part 'cash_page_methods_04.dart';

class _ExpenseSettlementSelection {
  const _ExpenseSettlementSelection({
    required this.expenseId,
    required this.amount,
  });

  final String expenseId;
  final double amount;
}

class CashPage extends StatefulWidget {
  const CashPage({super.key, required this.store});

  final AppStore store;

  @override
  State<CashPage> createState() => _CashPageState();
}

class _CashPageState extends State<CashPage> {
  int _refreshKey = 0;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final canManage = widget.store.canManageCashBox;
    return FutureBuilder<AdvancedAccountingItem?>(
      key: ValueKey('cash_page_$_refreshKey'),
      future: AccountingService.currentCashDrawerForDevice(
        deviceId: _deviceId,
        branchId: _branchId,
      ),
      builder: (context, snapshot) {
        final currentDrawer = snapshot.data;
        return FutureBuilder<List<AdvancedAccountingItem>>(
          future: AccountingService.listOpenCashDrawersReport(),
          builder: (context, sessionsSnapshot) {
            final sessions =
                sessionsSnapshot.data ?? const <AdvancedAccountingItem>[];
            final currentDrawerSessions = currentDrawer == null
                ? const <AdvancedAccountingItem>[]
                : sessions
                    .where((item) => item.referenceId == currentDrawer.id)
                    .toList(growable: false);
            final currentSession = currentDrawerSessions.isEmpty
                ? null
                : currentDrawerSessions.first;
            String money(double value) =>
                formatUsdReferenceAmount(value, widget.store.storeProfile);
            final openingBalance = (currentSession?.debit ?? 0).toDouble();
            final expectedBalance =
                (currentSession?.credit ?? currentDrawer?.balance ?? 0)
                    .toDouble();
            final shiftNet =
                currentSession == null ? 0.0 : expectedBalance - openingBalance;

            return Padding(
              padding: VentioResponsive.pageInsets(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _pageHeader(context, tr, currentDrawer, currentSession),
                  const SizedBox(height: 14),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 900;
                      final itemWidth = compact
                          ? (constraints.maxWidth - 10) / 2
                          : (constraints.maxWidth - 30) / 4;
                      return Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _dashboardMetric(
                            context,
                            width: itemWidth,
                            label: _l(tr, 'Current balance', 'الرصيد الحالي'),
                            value: currentDrawer == null
                                ? '—'
                                : money(currentDrawer.balance),
                            icon: Icons.account_balance_wallet_outlined,
                          ),
                          _dashboardMetric(
                            context,
                            width: itemWidth,
                            label: _l(tr, 'Opening balance', 'رصيد الافتتاح'),
                            value: currentSession == null
                                ? '—'
                                : money(openingBalance),
                            icon: Icons.login_rounded,
                          ),
                          _dashboardMetric(
                            context,
                            width: itemWidth,
                            label: _l(tr, 'Expected balance', 'الرصيد المتوقع'),
                            value: currentSession == null
                                ? '—'
                                : money(expectedBalance),
                            icon: Icons.calculate_outlined,
                          ),
                          _dashboardMetric(
                            context,
                            width: itemWidth,
                            label: _l(tr, 'Shift net', 'صافي الوردية'),
                            value:
                                currentSession == null ? '—' : money(shiftNet),
                            icon: Icons.balance_outlined,
                            emphasize: true,
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  _quickActionsCard(
                    context,
                    tr,
                    canManage: canManage,
                    currentDrawer: currentDrawer,
                    currentSession: currentSession,
                  ),
                  const SizedBox(height: 14),
                  if (currentDrawer == null)
                    Expanded(
                      child: Card(
                        elevation: 0,
                        child: Center(
                            child: Text(tr.text('no_cash_drawer_for_device'))),
                      ),
                    )
                  else
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          if (constraints.maxWidth < 1050) {
                            return Column(
                              children: [
                                _shiftSummaryCard(
                                  context,
                                  tr,
                                  currentDrawer: currentDrawer,
                                  currentSession: currentSession,
                                  canManage: canManage,
                                  compact: true,
                                ),
                                const SizedBox(height: 12),
                                Expanded(
                                  child: CashHistoryPanel(
                                    store: widget.store,
                                    cashLocationId: currentDrawer.id,
                                    currentSessionId: currentSession?.id ?? '',
                                    refreshKey: _refreshKey,
                                  ),
                                ),
                              ],
                            );
                          }
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(
                                width: 315,
                                child: _shiftSummaryCard(
                                  context,
                                  tr,
                                  currentDrawer: currentDrawer,
                                  currentSession: currentSession,
                                  canManage: canManage,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: CashHistoryPanel(
                                  store: widget.store,
                                  cashLocationId: currentDrawer.id,
                                  currentSessionId: currentSession?.id ?? '',
                                  refreshKey: _refreshKey,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
