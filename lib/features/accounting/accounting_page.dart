import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/accounting/accounting_account_role.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/utils/currency_utils.dart';
import '../../core/utils/responsive.dart';
import '../../core/utils/revision_cache.dart';
import '../../core/services/accounting_service.dart';
import '../../core/services/accounting_aging_service.dart';
import '../../core/services/cash_ledger_service.dart';
import '../../core/services/local_database_service.dart';
import '../../core/services/print_service.dart';
import '../../data/app_store.dart';
import 'accounting_snapshot_service.dart';
import '../../models/account_transaction.dart';
import '../../models/cash_ledger_transaction.dart';
import '../../models/accounting_account.dart';
import '../../models/journal_entry.dart';
import '../../models/print_settings.dart';
import '../../models/tax_profile.dart';
import '../../models/aging_report.dart';
import '../../models/user_role.dart';
import '../accounts/account_ledger_widgets.dart';

part 'accounting_page_chart_of_accounts.dart';
part 'accounting_page_report_navigation.dart';
part 'accounting_page_subledgers.dart';
part 'accounting_page_cash.dart';
part 'accounting_page_transactions.dart';
part 'accounting_page_journal_entries.dart';
part 'accounting_page_general_ledger.dart';
part 'accounting_page_financial_statements.dart';
part 'accounting_page_cash_tax_reports.dart';
part 'accounting_page_advanced.dart';
part 'accounting_page_advanced_cash.dart';
part 'accounting_page_advanced_journal.dart';
part 'accounting_page_advanced_assets.dart';
part 'accounting_page_advanced_operations.dart';
part 'accounting_page_shell_widgets.dart';
part 'accounting_page_roles.dart';
part 'accounting_page_settings.dart';
part 'accounting_page_report_widgets.dart';

const ScrollCacheExtent _kAccountingListCacheExtent =
    ScrollCacheExtent.pixels(2000);
const int _kCashFlowDetailRowLimit = 200;

class AccountingPage extends StatefulWidget {
  const AccountingPage({super.key, required this.store});

  final AppStore store;

  @override
  State<AccountingPage> createState() => _AccountingPageState();
}

class _AccountingPageState extends State<AccountingPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  static const AccountingSnapshotService _snapshotService =
      AccountingSnapshotService();

  void _handleStoreChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _handleTopTabChanged() {
    if (!mounted || _tabController.indexIsChanging) return;
    if (_tabController.index >= 3 && _searchController.text.isNotEmpty) {
      _searchController.clear();
      return;
    }
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(_handleTopTabChanged);
    widget.store.addListener(_handleStoreChanged);
    _searchController.addListener(() =>
        setState(() => _query = _searchController.text.trim().toLowerCase()));
  }

  @override
  void didUpdateWidget(covariant AccountingPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_handleStoreChanged);
      widget.store.addListener(_handleStoreChanged);
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_handleStoreChanged);
    _tabController.removeListener(_handleTopTabChanged);
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    if (!widget.store.canViewAccounting) {
      return _AccessDeniedScaffold(
        title: tr.text('accounting'),
        message: tr.text('no_access_accounting_data'),
      );
    }
    if (!widget.store.isCoreDataLoaded || !widget.store.isLedgerDataLoaded) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    final pageInsets = VentioResponsive.isDesktop(context)
        ? const EdgeInsets.fromLTRB(16, 10, 16, 10)
        : VentioResponsive.pageInsets(context);

    return Padding(
      padding: pageInsets,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AccountingHeader(
            title: tr.text('accounting'),
            subtitle: _topSectionSubtitle(context, _tabController.index),
            onRefresh: () => setState(() {}),
          ),
          const SizedBox(height: 8),
          _AccountingTabs(controller: _tabController),
          const SizedBox(height: 6),
          if (_tabController.index <= 2) ...[
            _AccountingSearchField(
                controller: _searchController, query: _query),
            const SizedBox(height: 10),
          ],
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _LazyTabPane(
                  controller: _tabController,
                  index: 0,
                  builder: (_) => _AccountsAccountingGroup(
                      store: widget.store, query: _query),
                ),
                _LazyTabPane(
                  controller: _tabController,
                  index: 1,
                  builder: (_) => _OperationsAccountingGroup(
                      store: widget.store, query: _query),
                ),
                _LazyTabPane(
                  controller: _tabController,
                  index: 2,
                  builder: (_) =>
                      _CashAccountingGroup(store: widget.store, query: _query),
                ),
                _LazyTabPane(
                  controller: _tabController,
                  index: 3,
                  builder: (_) => _ReportsAccountingGroup(
                      store: widget.store, query: _query),
                ),
                _LazyTabPane(
                  controller: _tabController,
                  index: 4,
                  builder: (_) => _SettingsAccountingGroup(store: widget.store),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
