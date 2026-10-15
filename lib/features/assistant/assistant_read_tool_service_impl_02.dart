part of 'assistant_read_tool_service.dart';

extension _AssistantReadToolServicePart2
    on _AssistantReadToolServiceImplementation {
  Future<AssistantJsonMap> execute({
    required AppStore store,
    required String name,
    required Map<String, Object?> arguments,
    DateTime? now,
  }) async {
    final toolName = name.trim();
    if (!_knownToolNames.contains(toolName)) {
      throw const AssistantReadToolException(
        'unknown_tool',
        'This assistant read tool is not available.',
      );
    }
    _requireToolPermission(store, toolName);
    _requireReadDatabase();
    final reference = (now ?? DateTime.now()).toLocal();

    switch (toolName) {
      case 'income_statement':
        _requireOnlyArguments(arguments, const <String>{'from', 'to'});
        final period = _parsePeriod(arguments);
        final report = await AccountingService.incomeStatementReport(
          from: period.from,
          to: period.toInclusive,
        );
        return _envelope(
          store,
          toolName,
          reference,
          data: <String, Object?>{
            'grossSales': report.grossSales,
            'salesReturns': report.salesReturns,
            'salesDiscounts': report.salesDiscounts,
            'netSales': report.netSales,
            'otherRevenue': report.otherRevenue,
            'revenue': report.revenue,
            'costOfGoodsSold': report.costOfGoodsSold,
            'grossProfit': report.grossProfit,
            'expenses': report.expenses,
            'netProfit': report.netProfit,
            'inventoryGain': report.inventoryGain,
            'cashOver': report.cashOver,
            'inventoryLoss': report.inventoryLoss,
            'manufacturingWaste': report.manufacturingWaste,
            'manufacturingVariance': report.manufacturingVariance,
            'cashShort': report.cashShort,
            'otherRevenueLines': _statementLines(report.otherRevenueLines),
            'otherRevenueLinesTruncated':
                report.otherRevenueLines.length > _maxReturnedRows,
            'costOfSalesLines': _statementLines(report.costOfSalesLines),
            'costOfSalesLinesTruncated':
                report.costOfSalesLines.length > _maxReturnedRows,
            'expenseLines': _statementLines(report.expenseLines),
            'expenseLinesTruncated':
                report.expenseLines.length > _maxReturnedRows,
          },
          period: period,
          source: 'AccountingService.incomeStatementReport',
        );

      case 'balance_sheet':
        _requireOnlyArguments(arguments, const <String>{'as_of'});
        final asOf = _parseOptionalDate(arguments, 'as_of') ??
            DateTime(reference.year, reference.month, reference.day);
        final report = await AccountingService.balanceSheetReport(
          asOf: _endOfDay(asOf),
        );
        return _envelope(
          store,
          toolName,
          reference,
          asOf: asOf,
          data: <String, Object?>{
            'assets': report.assets,
            'liabilities': report.liabilities,
            'equity': report.equity,
            'retainedEarnings': report.retainedEarnings,
            'liabilitiesAndEquity': report.liabilitiesAndEquity,
            'difference': report.difference,
            'currentAssets': report.currentAssets,
            'nonCurrentAssets': report.nonCurrentAssets,
            'currentLiabilities': report.currentLiabilities,
            'nonCurrentLiabilities': report.nonCurrentLiabilities,
            'currentAssetLines': _statementLines(report.currentAssetLines),
            'currentAssetLinesTruncated':
                report.currentAssetLines.length > _maxReturnedRows,
            'nonCurrentAssetLines':
                _statementLines(report.nonCurrentAssetLines),
            'nonCurrentAssetLinesTruncated':
                report.nonCurrentAssetLines.length > _maxReturnedRows,
            'currentLiabilityLines':
                _statementLines(report.currentLiabilityLines),
            'currentLiabilityLinesTruncated':
                report.currentLiabilityLines.length > _maxReturnedRows,
            'nonCurrentLiabilityLines':
                _statementLines(report.nonCurrentLiabilityLines),
            'nonCurrentLiabilityLinesTruncated':
                report.nonCurrentLiabilityLines.length > _maxReturnedRows,
            'equityLines': _statementLines(report.equityLines),
            'equityLinesTruncated':
                report.equityLines.length > _maxReturnedRows,
          },
          source: 'AccountingService.balanceSheetReport',
        );

      case 'trial_balance':
        _requireOnlyArguments(arguments, const <String>{'from', 'to'});
        final period = _parsePeriod(arguments);
        final rows = await AccountingService.trialBalanceReport(
          from: period.from,
          to: period.toInclusive,
        );
        final debitTotal = rows.fold<double>(0, (sum, row) => sum + row.debit);
        final creditTotal =
            rows.fold<double>(0, (sum, row) => sum + row.credit);
        final visibleRows = rows.take(_maxReturnedRows).map((row) {
          return <String, Object?>{
            'accountCode': row.accountCode,
            'accountName': row.accountName,
            'accountType': row.accountType,
            'accountSubtype': row.accountSubtype,
            'normalBalance': row.normalBalance,
            'debit': row.debit,
            'credit': row.credit,
            'opening': row.opening,
            'closing': row.closing,
          };
        }).toList(growable: false);
        return _envelope(
          store,
          toolName,
          reference,
          data: <String, Object?>{
            'totalDebit': debitTotal,
            'totalCredit': creditTotal,
            'difference': debitTotal - creditTotal,
            'accountCount': rows.length,
            'accounts': visibleRows,
            'accountsTruncated': rows.length > visibleRows.length,
          },
          period: period,
          source: 'AccountingService.trialBalanceReport',
        );

      case 'cash_flow_statement':
        _requireOnlyArguments(arguments, const <String>{'from', 'to'});
        final period = _parsePeriod(arguments);
        final report = await AccountingService.cashFlowStatementReport(
          from: period.from,
          to: period.toInclusive,
        );
        return _envelope(
          store,
          toolName,
          reference,
          data: <String, Object?>{
            'operatingInflows': report.operatingInflows,
            'operatingOutflows': report.operatingOutflows,
            'operatingNet': report.operatingNet,
            'investingInflows': report.investingInflows,
            'investingOutflows': report.investingOutflows,
            'investingNet': report.investingNet,
            'financingInflows': report.financingInflows,
            'financingOutflows': report.financingOutflows,
            'financingNet': report.financingNet,
            'openingCash': report.openingCash,
            'closingCash': report.closingCash,
            'netChangeInCash': report.netChangeInCash,
          },
          period: period,
          source: 'AccountingService.cashFlowStatementReport',
        );

      case 'tax_summary':
        _requireOnlyArguments(arguments, const <String>{'from', 'to'});
        final period = _parsePeriod(arguments);
        final report = await AccountingService.taxReport(
          from: period.from,
          to: period.toInclusive,
        );
        return _envelope(
          store,
          toolName,
          reference,
          data: <String, Object?>{
            'outputTax': report.outputTax,
            'inputTax': report.inputTax,
            'netTaxPayable': report.netTaxPayable,
            'payableAccountMovement': report.payableAccountMovement,
          },
          period: period,
          source: 'AccountingService.taxReport',
        );

      case 'sales_summary':
        _requireOnlyArguments(arguments, const <String>{'from', 'to'});
        final period = _parsePeriod(arguments);
        final data = await LocalDatabaseService.assistantSalesSummaryFromSqlite(
          from: period.from,
          to: period.toCalendarDate,
        );
        if (data == null) _throwBusinessDatabaseUnavailable();
        return _envelope(
          store,
          toolName,
          reference,
          data: data,
          period: period,
          source: 'BusinessSqliteStore.assistantSalesSummary',
        );

      case 'purchase_summary':
        _requireOnlyArguments(arguments, const <String>{'from', 'to'});
        final period = _parsePeriod(arguments);
        final data =
            await LocalDatabaseService.assistantPurchaseSummaryFromSqlite(
          from: period.from,
          to: period.toCalendarDate,
        );
        if (data == null) _throwBusinessDatabaseUnavailable();
        return _envelope(
          store,
          toolName,
          reference,
          data: data,
          period: period,
          source: 'BusinessSqliteStore.assistantPurchaseSummary',
        );

      case 'expense_summary':
        _requireOnlyArguments(arguments, const <String>{'from', 'to'});
        final period = _parsePeriod(arguments);
        final data =
            await LocalDatabaseService.assistantExpenseSummaryFromSqlite(
          from: period.from,
          to: period.toCalendarDate,
        );
        if (data == null) _throwBusinessDatabaseUnavailable();
        return _envelope(
          store,
          toolName,
          reference,
          data: data,
          period: period,
          source: 'BusinessSqliteStore.assistantExpenseSummary',
        );

      case 'customer_receivables_aging':
      case 'supplier_payables_aging':
        _requireOnlyArguments(arguments, const <String>{'as_of'});
        final asOf = _parseOptionalDate(arguments, 'as_of') ??
            DateTime(reference.year, reference.month, reference.day);
        final report = toolName == 'customer_receivables_aging'
            ? await AccountingAgingService.customerAgingReport(asOfDate: asOf)
            : await AccountingAgingService.supplierAgingReport(asOfDate: asOf);
        final parties = report.rows.take(_maxReturnedRows).map((row) {
          return <String, Object?>{
            'partyName': row.partyName,
            'current': row.current,
            'days1To30': row.days1To30,
            'days31To60': row.days31To60,
            'days61To90': row.days61To90,
            'over90': row.over90,
            'total': row.total,
          };
        }).toList(growable: false);
        return _envelope(
          store,
          toolName,
          reference,
          asOf: report.asOfDate,
          data: <String, Object?>{
            'total': report.total,
            'current': report.current,
            'days1To30': report.days1To30,
            'days31To60': report.days31To60,
            'days61To90': report.days61To90,
            'over90': report.over90,
            'partyCount': report.rows.length,
            'parties': parties,
            'partiesTruncated': report.rows.length > parties.length,
          },
          source: toolName == 'customer_receivables_aging'
              ? 'AccountingAgingService.customerAgingReport'
              : 'AccountingAgingService.supplierAgingReport',
        );

      case 'customer_account_statement':
      case 'supplier_account_statement':
        final isCustomer = toolName == 'customer_account_statement';
        final partyArgument = isCustomer ? 'customer' : 'supplier';
        _requireOnlyArguments(
          arguments,
          <String>{partyArgument, 'from', 'to'},
        );
        return _readPartyAccountStatement(
          store: store,
          toolName: toolName,
          partyType: isCustomer ? 'customer' : 'supplier',
          partyArgument: partyArgument,
          arguments: arguments,
          reference: reference,
        );

      case 'sales_invoice_details':
      case 'purchase_invoice_details':
        _requireOnlyArguments(arguments, const <String>{'query', 'from', 'to'});
        return _readInvoiceDetails(
          store: store,
          toolName: toolName,
          arguments: arguments,
          reference: reference,
        );

      case 'party_payment_history':
        _requireOnlyArguments(
          arguments,
          const <String>{'party_type', 'party', 'from', 'to'},
        );
        return _readPartyPaymentHistory(
          store: store,
          arguments: arguments,
          reference: reference,
        );

      case 'party_balance_reconciliation':
        _requireOnlyArguments(
          arguments,
          const <String>{'party_type', 'party', 'as_of'},
        );
        return _readPartyBalanceReconciliation(
          store: store,
          arguments: arguments,
          reference: reference,
        );

      case 'cash_balances':
        _requireOnlyArguments(arguments, const <String>{});
        final balances = await AccountingService.listCashBalancesReport();
        final rows = balances.take(_maxReturnedRows).map((item) {
          return <String, Object?>{
            'name': item.name,
            'type': item.type,
            'balance': item.balance,
          };
        }).toList(growable: false);
        return _envelope(
          store,
          toolName,
          reference,
          data: <String, Object?>{
            'balanceCount': balances.length,
            'balances': rows,
            'balancesTruncated': balances.length > rows.length,
          },
          source: 'AccountingService.listCashBalancesReport',
        );

      case 'inventory_cost_valuation':
        _requireOnlyArguments(arguments, const <String>{});
        final rows = await AccountingService.inventoryValuationReport();
        final sorted = List.of(rows)
          ..sort((left, right) => right.totalValue.compareTo(left.totalValue));
        final visibleRows = sorted.take(_maxReturnedRows).map((row) {
          return <String, Object?>{
            'productName': row.productName,
            'warehouseName': row.warehouseName,
            'quantity': row.quantity,
            'unitCost': row.unitCost,
            'totalValue': row.totalValue,
            'inventoryCategory': row.inventoryCategory,
          };
        }).toList(growable: false);
        return _envelope(
          store,
          toolName,
          reference,
          data: <String, Object?>{
            'totalCostValue': rows.fold<double>(
              0,
              (sum, row) => sum + row.totalValue,
            ),
            'productWarehouseCount': rows.length,
            'rows': visibleRows,
            'rowsTruncated': rows.length > visibleRows.length,
            'valuationBasis': 'Ventio inventory accounting valuation',
          },
          source: 'AccountingService.inventoryValuationReport',
        );

      case 'current_stock_balances':
        _requireOnlyArguments(
          arguments,
          const <String>{'product', 'warehouse'},
        );
        final data =
            await LocalDatabaseService.assistantStockBalancesFromSqlite(
          storeId: store.runtime.identity.storeId,
          productQuery: _optionalStringArgument(arguments, 'product'),
          warehouseQuery: _optionalStringArgument(arguments, 'warehouse'),
        );
        if (data == null) _throwBusinessDatabaseUnavailable();
        return _envelope(
          store,
          toolName,
          reference,
          data: data,
          source: 'BusinessSqliteStore.assistantStockBalances',
        );

      case 'stock_movement_summary':
        _requireOnlyArguments(
          arguments,
          const <String>{'from', 'to', 'product', 'warehouse', 'type'},
        );
        final period = _parsePeriod(arguments);
        final data =
            await LocalDatabaseService.assistantStockMovementSummaryFromSqlite(
          storeId: store.runtime.identity.storeId,
          from: period.from,
          to: period.toCalendarDate,
          productQuery: _optionalStringArgument(arguments, 'product'),
          warehouseQuery: _optionalStringArgument(arguments, 'warehouse'),
          type: _optionalStringArgument(
            arguments,
            'type',
            maxLength: 80,
          ),
        );
        if (data == null) _throwBusinessDatabaseUnavailable();
        return _envelope(
          store,
          toolName,
          reference,
          data: data,
          period: period,
          source: 'BusinessSqliteStore.assistantStockMovementSummary',
        );

      case 'manufacturing_cost_summary':
        _requireOnlyArguments(arguments, const <String>{});
        final rows = await AccountingService.manufacturingOrderCostReport();
        final visibleRows = rows.take(_maxReturnedRows).map((row) {
          return <String, Object?>{
            'orderNo': row.orderNo,
            'outputProductName': row.outputProductName,
            'outputQuantity': row.outputQuantity,
            'totalMaterialCost': row.totalMaterialCost,
            'wasteValue': row.wasteValue,
            'eligibleCost': row.eligibleCost,
            'actualUnitCost': row.actualUnitCost,
            'status': row.status,
          };
        }).toList(growable: false);
        return _envelope(
          store,
          toolName,
          reference,
          data: <String, Object?>{
            'orderCount': rows.length,
            'totalMaterialCost': rows.fold<double>(
              0,
              (sum, row) => sum + row.totalMaterialCost,
            ),
            'totalWasteValue':
                rows.fold<double>(0, (sum, row) => sum + row.wasteValue),
            'totalEligibleCost':
                rows.fold<double>(0, (sum, row) => sum + row.eligibleCost),
            'orders': visibleRows,
            'ordersTruncated': rows.length > visibleRows.length,
          },
          source: 'AccountingService.manufacturingOrderCostReport',
        );

      case 'manufacturing_waste':
        _requireOnlyArguments(arguments, const <String>{});
        final rows = await AccountingService.manufacturingWasteReport();
        final visibleRows = rows.take(_maxReturnedRows).map((row) {
          return <String, Object?>{
            'orderNo': row.orderNo,
            'productName': row.productName,
            'quantity': row.quantity,
            'unitCost': row.unitCost,
            'value': row.value,
            'reason': row.reason,
            'status': row.status,
          };
        }).toList(growable: false);
        return _envelope(
          store,
          toolName,
          reference,
          data: <String, Object?>{
            'wasteLineCount': rows.length,
            'totalValue': rows.fold<double>(0, (sum, row) => sum + row.value),
            'lines': visibleRows,
            'linesTruncated': rows.length > visibleRows.length,
          },
          source: 'AccountingService.manufacturingWasteReport',
        );

      case 'inventory_count_variances':
        _requireOnlyArguments(arguments, const <String>{});
        final rows = await AccountingService.inventoryCountVarianceReport();
        final visibleRows = rows.take(_maxReturnedRows).map((row) {
          return <String, Object?>{
            'countNo': row.countNo,
            'status': row.status,
            'productName': row.productName,
            'systemQuantity': row.systemQuantity,
            'countedQuantity': row.countedQuantity,
            'differenceQuantity': row.differenceQuantity,
            'unitCost': row.unitCost,
            'differenceValue': row.differenceValue,
          };
        }).toList(growable: false);
        return _envelope(
          store,
          toolName,
          reference,
          data: <String, Object?>{
            'varianceLineCount': rows.length,
            'netDifferenceValue': rows.fold<double>(
              0,
              (sum, row) => sum + row.differenceValue,
            ),
            'grossDifferenceValue': rows.fold<double>(
              0,
              (sum, row) => sum + row.differenceValue.abs(),
            ),
            'lines': visibleRows,
            'linesTruncated': rows.length > visibleRows.length,
          },
          source: 'AccountingService.inventoryCountVarianceReport',
        );

      case 'business_data_analysis':
        _requireOnlyArguments(
          arguments,
          const <String>{
            'dataset',
            'group_by',
            'from',
            'to',
            'search',
            'limit'
          },
        );
        try {
          final data = await AssistantBusinessAnalysisService.execute(
            store: store,
            arguments: arguments,
          );
          return _envelope(
            store,
            toolName,
            reference,
            data: data,
            source: 'Ventio read-only aggregate analysis',
          );
        } on AssistantBusinessAnalysisException catch (error) {
          throw AssistantReadToolException(error.code, error.message);
        }

      case 'business_schema_catalog':
        _requireOnlyArguments(arguments, const <String>{'table'});
        try {
          return _envelope(
            store,
            toolName,
            reference,
            data: await AssistantDatabaseExplorerService.executeCatalog(
              store: store,
              arguments: arguments,
            ),
            source: 'Ventio permitted business schema catalog',
          );
        } on AssistantDatabaseExplorerException catch (error) {
          throw AssistantReadToolException(error.code, error.message);
        }

      case 'business_table_analysis':
        _requireOnlyArguments(
          arguments,
          const <String>{
            'table',
            'group_by',
            'measure',
            'from',
            'to',
            'search',
            'filter_by',
            'filter_value',
            'filter_match',
            'limit',
          },
        );
        try {
          return _envelope(
            store,
            toolName,
            reference,
            data: await AssistantDatabaseExplorerService.executeAnalysis(
              store: store,
              arguments: arguments,
            ),
            source: 'Ventio permission-scoped table aggregate',
          );
        } on AssistantDatabaseExplorerException catch (error) {
          throw AssistantReadToolException(error.code, error.message);
        }

      default:
        throw const AssistantReadToolException(
          'unknown_tool',
          'This assistant read tool is not available.',
        );
    }
  }
}
