part of 'assistant_read_tool_service.dart';

extension _AssistantReadToolServicePart3
    on _AssistantReadToolServiceImplementation {
  Future<AssistantJsonMap> _readPartyAccountStatement({
    required AppStore store,
    required String toolName,
    required String partyType,
    required String partyArgument,
    required Map<String, Object?> arguments,
    required DateTime reference,
  }) async {
    final query = _optionalStringArgument(
      arguments,
      partyArgument,
      maxLength: 160,
    );
    if (query.isEmpty) {
      throw AssistantReadToolException(
        '${partyType}_required',
        'A $partyType name is required to read an account statement.',
      );
    }
    final candidates = await _loadPartyCandidates(store, partyType);
    final matches = _matchPartyCandidates(candidates, query);
    if (matches.length != 1) {
      return _envelope(
        store,
        toolName,
        reference,
        data: <String, Object?>{
          'matchStatus': matches.isEmpty ? 'not_found' : 'ambiguous',
          'partyQuery': query,
          'matchingPartyCount': matches.length,
          'matchingParties': matches
              .take(10)
              .map((party) => <String, Object?>{
                    'partyId': party.id,
                    'partyName': party.name,
                  })
              .toList(growable: false),
        },
        source: 'AppStore.${partyType}_account_statement',
      );
    }

    await store.ensureAccountTransactionsLoaded();
    final party = matches.single;
    final allTransactions = store
        .accountTransactionsForAccount(partyType, party.id)
        .where((transaction) => !transaction.isDeleted)
        .toList(growable: false)
      ..sort(_compareAccountTransactions);
    final today = DateTime(reference.year, reference.month, reference.day);
    final firstDate = allTransactions.isEmpty
        ? today
        : _localDateOnly(allTransactions.first.date);
    final from = _parseOptionalDate(arguments, 'from') ?? firstDate;
    final to = _parseOptionalDate(arguments, 'to') ?? today;
    if (from.isAfter(to)) {
      throw const AssistantReadToolException(
        'invalid_date_range',
        'The start date must be on or before the end date.',
      );
    }
    final toInclusive = _endOfDay(to);
    final currencies = allTransactions
        .map((transaction) => _transactionCurrency(transaction, store))
        .toSet()
        .toList()
      ..sort();
    if (currencies.isEmpty) currencies.add(store.storeProfile.baseCurrency);
    final transactionsByCurrency = <String, List<AccountTransaction>>{
      for (final currency in currencies)
        currency: allTransactions
            .where((transaction) =>
                _transactionCurrency(transaction, store) == currency)
            .toList(growable: false),
    };
    final currencySummaries = <AssistantJsonMap>[];
    final openingByCurrency = <String, double>{};
    final isCustomer = partyType == 'customer';
    final balanceSign = isCustomer ? 1.0 : -1.0;
    for (final currency in currencies) {
      final currencyTransactions = transactionsByCurrency[currency]!;
      final opening = currencyTransactions
          .where((transaction) => transaction.date.isBefore(from))
          .fold<double>(
            0,
            (sum, transaction) => sum + transaction.signedAmount * balanceSign,
          );
      final periodTransactions = currencyTransactions
          .where((transaction) =>
              !transaction.date.isBefore(from) &&
              !transaction.date.isAfter(toInclusive))
          .toList(growable: false);
      final debitTotal = periodTransactions.fold<double>(
        0,
        (sum, transaction) => sum + transaction.debit,
      );
      final creditTotal = periodTransactions.fold<double>(
        0,
        (sum, transaction) => sum + transaction.credit,
      );
      final currentBalance = currencyTransactions.fold<double>(
        0,
        (sum, transaction) => sum + transaction.signedAmount * balanceSign,
      );
      final balanceMovement =
          isCustomer ? debitTotal - creditTotal : creditTotal - debitTotal;
      openingByCurrency[currency] = opening;
      currencySummaries.add(<String, Object?>{
        'currency': currency,
        'openingBalance': opening,
        'debitTotal': debitTotal,
        'creditTotal': creditTotal,
        'closingBalance': opening + balanceMovement,
        'currentBalance': currentBalance,
        'transactionCount': periodTransactions.length,
      });
    }

    final rangeTransactions = allTransactions
        .where((transaction) =>
            !transaction.date.isBefore(from) &&
            !transaction.date.isAfter(toInclusive))
        .toList(growable: false);
    final runningByCurrency = Map<String, double>.of(openingByCurrency);
    final visibleTransactions = <AssistantJsonMap>[];
    for (final transaction
        in rangeTransactions.take(_maxCustomerStatementRows)) {
      final currency = _transactionCurrency(transaction, store);
      final runningBalance = (runningByCurrency[currency] ?? 0) +
          transaction.signedAmount * balanceSign;
      runningByCurrency[currency] = runningBalance;
      visibleTransactions.add(<String, Object?>{
        'date': _dateLabel(transaction.date),
        'type': _customerTransactionTypeLabel(transaction.type),
        'referenceId': transaction.referenceId,
        'reference': transaction.referenceNo.trim().isEmpty
            ? transaction.referenceId
            : transaction.referenceNo,
        'debit': transaction.debit,
        'credit': transaction.credit,
        'currency': currency,
        'runningBalanceInCurrency': runningBalance,
        'details': transaction.note,
        'paymentMethod': transaction.paymentMethod,
      });
    }
    final period = _AssistantDatePeriod(
      from: from,
      toInclusive: toInclusive,
      fromLabel: _dateLabel(from),
      toLabel: _dateLabel(to),
    );
    return _envelope(
      store,
      toolName,
      reference,
      data: <String, Object?>{
        'matchStatus': 'matched',
        'partyType': partyType,
        'partyId': party.id,
        'partyName': party.name,
        'balanceMeaning': isCustomer
            ? 'Within each currency, debit increases the customer amount due and credit reduces it.'
            : 'Within each currency, credit increases the amount Ventio owes the supplier and debit reduces it.',
        'currencyCount': currencies.length,
        if (currencies.length == 1)
          'ventioLedgerBalance': currencySummaries.first['currentBalance'],
        'currencySummaries': currencySummaries,
        'transactionCount': rangeTransactions.length,
        'transactions': visibleTransactions,
        'transactionsTruncated':
            rangeTransactions.length > visibleTransactions.length,
        'returnedTransactionCount': visibleTransactions.length,
      },
      period: period,
      source: 'AppStore.${partyType}_account_statement',
    );
  }

  Future<AssistantJsonMap> _readInvoiceDetails({
    required AppStore store,
    required String toolName,
    required Map<String, Object?> arguments,
    required DateTime reference,
  }) async {
    final query = _optionalStringArgument(arguments, 'query', maxLength: 160);
    if (query.isEmpty) {
      throw const AssistantReadToolException(
        'query_required',
        'Enter an invoice number, customer or supplier name, or product name.',
      );
    }
    final from = _parseOptionalDate(arguments, 'from');
    final to = _parseOptionalDate(arguments, 'to') ??
        DateTime(reference.year, reference.month, reference.day);
    if (from != null && from.isAfter(to)) {
      throw const AssistantReadToolException(
        'invalid_date_range',
        'The start date must be on or before the end date.',
      );
    }
    final isSales = toolName == 'sales_invoice_details';
    final normalized = _normalizePartyName(query);
    final matches = <Object>[];
    if (isSales) {
      await store.ensureSalesLoaded();
      final documents = store.sales.where((sale) {
        if (sale.isDeleted || !_dateMatches(sale.date, from, to)) return false;
        return _invoiceMatches(
          query: query,
          normalizedQuery: normalized,
          documentId: sale.id,
          documentNumber: sale.invoiceNo,
          partyName: sale.customerName,
          productNames: sale.items.map((item) => item.productName),
        );
      }).toList(growable: false)
        ..sort((left, right) => right.date.compareTo(left.date));
      final exact = documents
          .where(
              (sale) => _invoiceNumberIsExact(query, sale.id, sale.invoiceNo))
          .toList(growable: false);
      matches.addAll(exact.isEmpty ? documents : exact);
    } else {
      await store.ensurePurchasesLoaded();
      final documents = store.purchases.where((purchase) {
        if (purchase.isDeleted || !_dateMatches(purchase.date, from, to)) {
          return false;
        }
        return _invoiceMatches(
          query: query,
          normalizedQuery: normalized,
          documentId: purchase.id,
          documentNumber: purchase.purchaseNo,
          partyName: purchase.supplierName,
          productNames: purchase.items.map((item) => item.productName),
        );
      }).toList(growable: false)
        ..sort((left, right) => right.date.compareTo(left.date));
      final exact = documents
          .where((purchase) =>
              _invoiceNumberIsExact(query, purchase.id, purchase.purchaseNo))
          .toList(growable: false);
      matches.addAll(exact.isEmpty ? documents : exact);
    }
    final invoices = <AssistantJsonMap>[];
    for (final document in matches.take(_maxInvoiceMatches)) {
      if (document is Sale) {
        invoices.add(_saleInvoiceData(document));
      } else if (document is Purchase) {
        invoices.add(_purchaseInvoiceData(document));
      }
    }
    final filterFrom = from == null ? null : _dateLabel(from);
    return _envelope(
      store,
      toolName,
      reference,
      data: <String, Object?>{
        'query': query,
        'matchStatus': matches.isEmpty ? 'not_found' : 'matched',
        'matchCount': matches.length,
        'returnedInvoiceCount': invoices.length,
        'invoices': invoices,
        'invoicesTruncated': matches.length > invoices.length,
        'dateFilterFrom': filterFrom,
        'dateFilterTo': _dateLabel(to),
        if (isSales)
          'amountBasis':
              'Invoice total and paid/due/return amounts use each invoice currency. Sales line prices and line totals use the invoice base currency, which is shown separately.'
        else
          'amountBasis':
              'Purchase line totals and document subtotal are USD reference values; original unit costs retain their recorded currency and exchange rate.',
      },
      source: isSales ? 'AppStore.sales' : 'AppStore.purchases',
    );
  }

  AssistantJsonMap _saleInvoiceData(Sale sale) {
    final visibleItems = sale.items.take(_maxInvoiceLines).map((item) {
      return <String, Object?>{
        'productId': item.productId,
        'productName': item.productName,
        'quantity': item.quantity,
        'unitName': item.unitName,
        'unitPrice': item.unitPrice,
        'unitPriceCurrency': sale.baseCurrency,
        'lineTotal': item.lineTotal,
        'lineTotalCurrency': sale.baseCurrency,
      };
    }).toList(growable: false);
    return <String, Object?>{
      'id': sale.id,
      'invoiceNumber': sale.invoiceNo,
      'date': _dateLabel(sale.date),
      'status': sale.status,
      'customerId': sale.customerId,
      'customerName': sale.customerName,
      'currency': sale.invoiceCurrency,
      'invoiceTotal': sale.invoiceTotal,
      'paidAmount': sale.paidAmount,
      'balanceDue': sale.balanceDue,
      'returnedAmount': sale.returnedAmount,
      'baseAmount': sale.effectiveBaseAmount,
      'baseCurrency': sale.baseCurrency,
      'discount': sale.discount,
      'discountCurrency': sale.discountCurrency,
      'paymentStatus': sale.paymentStatus,
      'paymentMethod': sale.paymentMethod,
      'warehouse': sale.warehouseName,
      'items': visibleItems,
      'itemCount': sale.items.length,
      'itemsTruncated': sale.items.length > visibleItems.length,
    };
  }

  AssistantJsonMap _purchaseInvoiceData(Purchase purchase) {
    final visibleItems = purchase.items.take(_maxInvoiceLines).map((item) {
      return <String, Object?>{
        'productId': item.productId,
        'productName': item.productName,
        'quantity': item.quantity,
        'purchaseUnitName': item.purchaseUnitName,
        'unitCostUsdReference': item.unitCost,
        'lineTotalUsdReference': item.lineTotal,
        'originalUnitCost': item.originalUnitCost,
        'originalCurrency': item.unitCostCurrency,
        'exchangeRateAtEntry': item.exchangeRateAtEntry,
      };
    }).toList(growable: false);
    return <String, Object?>{
      'id': purchase.id,
      'documentNumber': purchase.purchaseNo,
      'date': _dateLabel(purchase.date),
      'status': purchase.status,
      'documentType': purchase.documentType,
      'sourcePurchaseNumber': purchase.sourcePurchaseNo,
      'supplierId': purchase.supplierId,
      'supplierName': purchase.supplierName,
      'subtotalUsdReference': purchase.subtotal,
      'paidAmountUsdReference': purchase.paidAmount,
      'balanceDueUsdReference': purchase.balanceDue,
      'paymentStatus': purchase.paymentStatus,
      'paymentMethod': purchase.paymentMethod,
      'warehouse': purchase.warehouseName,
      'items': visibleItems,
      'itemCount': purchase.items.length,
      'itemsTruncated': purchase.items.length > visibleItems.length,
    };
  }

  Future<AssistantJsonMap> _readPartyPaymentHistory({
    required AppStore store,
    required Map<String, Object?> arguments,
    required DateTime reference,
  }) async {
    final partyType = _requiredPartyType(arguments);
    _requirePartyLedgerPermission(store, partyType);
    final query = _optionalStringArgument(arguments, 'party', maxLength: 160);
    if (query.isEmpty) {
      throw const AssistantReadToolException(
        'party_required',
        'A customer or supplier name is required to read payment history.',
      );
    }
    final candidates = await _loadPartyCandidates(store, partyType);
    final matches = _matchPartyCandidates(candidates, query);
    if (matches.length != 1) {
      return _envelope(
        store,
        'party_payment_history',
        reference,
        data: <String, Object?>{
          'matchStatus': matches.isEmpty ? 'not_found' : 'ambiguous',
          'partyType': partyType,
          'partyQuery': query,
          'matchingPartyCount': matches.length,
          'matchingParties': matches
              .take(10)
              .map((party) => <String, Object?>{
                    'partyId': party.id,
                    'partyName': party.name,
                  })
              .toList(growable: false),
        },
        source: 'PaymentVoucherService',
      );
    }
    final party = matches.single;
    final from = _parseOptionalDate(arguments, 'from');
    final to = _parseOptionalDate(arguments, 'to') ??
        DateTime(reference.year, reference.month, reference.day);
    if (from != null && from.isAfter(to)) {
      throw const AssistantReadToolException(
        'invalid_date_range',
        'The start date must be on or before the end date.',
      );
    }
    final database = SqliteMigrationManager.database;
    if (database == null) _throwBusinessDatabaseUnavailable();
    final service = PaymentVoucherService(database);
    final vouchers = <Object>[];
    var offset = 0;
    var historyMayBeIncomplete = false;
    for (var pageIndex = 0; pageIndex < _maxPaymentHistoryPages; pageIndex++) {
      final page = partyType == 'customer'
          ? await service.listReceipts(
              customerId: party.id,
              limit: 500,
              offset: offset,
            )
          : await service.listPayments(
              supplierId: party.id,
              limit: 500,
              offset: offset,
            );
      vouchers.addAll(page);
      if (page.length < 500) break;
      offset += page.length;
      if (pageIndex == _maxPaymentHistoryPages - 1) {
        historyMayBeIncomplete = true;
      }
    }
    final filtered = vouchers.where((voucher) {
      final date = voucher is ReceiptVoucher
          ? voucher.date
          : (voucher as PaymentVoucher).date;
      return _dateMatches(date, from, to);
    }).toList(growable: false);
    final rows = filtered.take(_maxPaymentHistoryRows).map((voucher) {
      if (voucher is ReceiptVoucher) return _receiptVoucherData(voucher);
      return _paymentVoucherData(voucher as PaymentVoucher);
    }).toList(growable: false);
    final visibleFrom = from == null ? null : _dateLabel(from);
    return _envelope(
      store,
      'party_payment_history',
      reference,
      data: <String, Object?>{
        'matchStatus': 'matched',
        'partyType': partyType,
        'partyId': party.id,
        'partyName': party.name,
        'historyCount': filtered.length,
        'history': rows,
        'historyTruncated': filtered.length > rows.length,
        'historyMayBeIncomplete': historyMayBeIncomplete,
        'dateFilterFrom': visibleFrom,
        'dateFilterTo': _dateLabel(to),
        'allocationBasis':
            'Only non-deleted active allocations are included by the local voucher service.',
      },
      source: 'PaymentVoucherService.listReceipts/listPayments',
    );
  }

  AssistantJsonMap _receiptVoucherData(ReceiptVoucher voucher) => _voucherData(
        id: voucher.id,
        number: voucher.voucherNo,
        date: voucher.date,
        status: voucher.status,
        amount: voucher.amount,
        discount: voucher.discount,
        unallocatedAmount: voucher.unallocatedAmount,
        currency: voucher.currency,
        method: voucher.paymentMethod,
        notes: voucher.notes,
        reversalReason: voucher.reversalReason,
        reversedAt: voucher.reversedAt,
        allocations: voucher.allocations,
      );

  AssistantJsonMap _paymentVoucherData(PaymentVoucher voucher) => _voucherData(
        id: voucher.id,
        number: voucher.voucherNo,
        date: voucher.date,
        status: voucher.status,
        amount: voucher.amount,
        discount: voucher.discount,
        unallocatedAmount: voucher.unallocatedAmount,
        currency: voucher.currency,
        method: voucher.paymentMethod,
        notes: voucher.notes,
        reversalReason: voucher.reversalReason,
        reversedAt: voucher.reversedAt,
        allocations: voucher.allocations,
      );

  AssistantJsonMap _voucherData({
    required String id,
    required String number,
    required DateTime date,
    required String status,
    required double amount,
    required double discount,
    required double unallocatedAmount,
    required String currency,
    required String method,
    required String notes,
    required String reversalReason,
    required DateTime? reversedAt,
    required List<PaymentAllocation> allocations,
  }) {
    final visibleAllocations = allocations.take(10).map((allocation) {
      return <String, Object?>{
        'documentType': allocation.referenceType,
        'documentId': allocation.referenceId,
        'documentNumber': allocation.referenceNumber,
        'voucherAmount': allocation.amount,
        'voucherCurrency': allocation.currency,
        'documentAmount': allocation.effectiveReferenceAmount,
        'documentCurrency': allocation.referenceCurrency,
        'exchangeRate': allocation.exchangeRate,
        'status': allocation.status,
      };
    }).toList(growable: false);
    return <String, Object?>{
      'id': id,
      'number': number,
      'date': _dateLabel(date),
      'status': status,
      'amount': amount,
      'discount': discount,
      'unallocatedAmount': unallocatedAmount,
      'currency': currency,
      'paymentMethod': method,
      'notes': notes,
      'reversalReason': reversalReason,
      'reversedAt': reversedAt?.toLocal().toIso8601String(),
      'allocations': visibleAllocations,
      'allocationCount': allocations.length,
      'allocationsTruncated': allocations.length > visibleAllocations.length,
    };
  }

  Future<AssistantJsonMap> _readPartyBalanceReconciliation({
    required AppStore store,
    required Map<String, Object?> arguments,
    required DateTime reference,
  }) async {
    final partyType = _requiredPartyType(arguments);
    _requirePartyLedgerPermission(store, partyType);
    final query = _optionalStringArgument(arguments, 'party', maxLength: 160);
    if (query.isEmpty) {
      throw const AssistantReadToolException(
        'party_required',
        'A customer or supplier name is required for balance reconciliation.',
      );
    }
    final asOf = _parseOptionalDate(arguments, 'as_of') ??
        DateTime(reference.year, reference.month, reference.day);
    final candidates = await _loadPartyCandidates(store, partyType);
    final matches = _matchPartyCandidates(candidates, query);
    if (matches.length != 1) {
      return _envelope(
        store,
        'party_balance_reconciliation',
        reference,
        asOf: asOf,
        data: <String, Object?>{
          'matchStatus': matches.isEmpty ? 'not_found' : 'ambiguous',
          'partyType': partyType,
          'partyQuery': query,
          'matchingPartyCount': matches.length,
          'matchingParties': matches
              .take(10)
              .map((party) => <String, Object?>{
                    'partyId': party.id,
                    'partyName': party.name,
                  })
              .toList(growable: false),
        },
        source: 'AppStore and AccountingAgingService',
      );
    }
    final party = matches.single;
    await store.ensureAccountTransactionsLoaded();
    final asOfInclusive = _endOfDay(asOf);
    final transactions = store
        .accountTransactionsForAccount(partyType, party.id)
        .where((transaction) =>
            !transaction.isDeleted && !transaction.date.isAfter(asOfInclusive))
        .toList(growable: false);
    final amountsByCurrency = <String, _PartyLedgerTotals>{};
    for (final transaction in transactions) {
      final currency = _transactionCurrency(transaction, store);
      amountsByCurrency.putIfAbsent(currency, _PartyLedgerTotals.new).add(
            transaction,
          );
    }
    final accountingReport = partyType == 'customer'
        ? await AccountingAgingService.customerAgingReport(asOfDate: asOf)
        : await AccountingAgingService.supplierAgingReport(asOfDate: asOf);
    bool belongsToParty(String rowId, String rowName) =>
        rowId.trim() == party.id ||
        _normalizePartyName(rowName) == _normalizePartyName(party.name);
    final agingMatches = accountingReport.rows
        .where((row) => belongsToParty(row.partyId, row.partyName))
        .toList(growable: false);
    final agingRow = agingMatches.isEmpty ? null : agingMatches.first;
    final agingDocuments = accountingReport.openDocuments
        .where(
            (document) => belongsToParty(document.partyId, document.partyName))
        .toList(growable: false);
    final baseCurrency = store.storeProfile.baseCurrency.toUpperCase();
    final onlyCurrency =
        amountsByCurrency.length == 1 ? amountsByCurrency.keys.single : null;
    final ledgerTotals =
        onlyCurrency == null ? null : amountsByCurrency[onlyCurrency];
    final signedLedgerBalance = ledgerTotals?.signedBalance;
    final netOwed = signedLedgerBalance == null
        ? null
        : partyType == 'customer'
            ? signedLedgerBalance
            : -signedLedgerBalance;
    final compatibleCurrency = onlyCurrency == baseCurrency;
    final compatibleDirection = netOwed != null && netOwed >= -0.005;
    final comparable =
        transactions.isNotEmpty && compatibleCurrency && compatibleDirection;
    final agingTotal = agingRow?.total ?? 0.0;
    final status = transactions.isEmpty
        ? 'subledger_empty'
        : !compatibleCurrency
            ? (onlyCurrency == null
                ? 'multiple_subledger_currencies'
                : 'currency_mismatch')
            : !compatibleDirection
                ? 'subledger_credit_balance'
                : 'comparable';
    final visibleDocuments = agingDocuments.take(25).map((document) {
      return <String, Object?>{
        'documentNumber': document.number,
        'date': _dateLabel(document.date),
        'originalAmount': document.originalAmount,
        'openAmount': document.openAmount,
        'bucket': document.bucketLabel,
        'ageDays': document.ageDays,
      };
    }).toList(growable: false);
    final ledgerCurrencies = amountsByCurrency.entries.map((entry) {
      return <String, Object?>{
        'currency': entry.key,
        'debitTotal': entry.value.debit,
        'creditTotal': entry.value.credit,
        'signedBalanceDebitMinusCredit': entry.value.signedBalance,
        'transactionCount': entry.value.count,
      };
    }).toList(growable: false);
    return _envelope(
      store,
      'party_balance_reconciliation',
      reference,
      asOf: asOf,
      data: <String, Object?>{
        'matchStatus': 'matched',
        'partyType': partyType,
        'partyId': party.id,
        'partyName': party.name,
        'accountingAgingSource': partyType == 'customer'
            ? 'AccountingAgingService.customerAgingReport'
            : 'AccountingAgingService.supplierAgingReport',
        'agingCurrency': baseCurrency,
        'grossAgingOpenBalance': agingTotal,
        'agingBuckets': <String, Object?>{
          'current': agingRow?.current ?? 0,
          'days1To30': agingRow?.days1To30 ?? 0,
          'days31To60': agingRow?.days31To60 ?? 0,
          'days61To90': agingRow?.days61To90 ?? 0,
          'over90': agingRow?.over90 ?? 0,
        },
        'openDocumentCount': agingDocuments.length,
        'openDocuments': visibleDocuments,
        'openDocumentsTruncated':
            agingDocuments.length > visibleDocuments.length,
        'subledgerCurrencySummaries': ledgerCurrencies,
        'subledgerCurrentNetAmountInOneCurrency': netOwed,
        'subledgerNetMeaning': partyType == 'customer'
            ? 'Debit minus credit; a positive amount is due from the customer.'
            : 'Credit minus debit; a positive amount is due to the supplier.',
        'comparisonStatus': status,
        'comparisonIsValid': comparable,
        if (comparable) 'differenceAgingMinusSubledger': agingTotal - netOwed,
        'comparisonNote': comparable
            ? 'Both figures are in the base currency and have a non-credit net balance. Aging shows open documents; the subledger value is its signed net balance.'
            : 'The comparison is withheld because the subledger is empty, has multiple currencies, uses a different currency, or has a net credit/advance balance. Source values are shown separately.',
      },
      source: 'AccountingAgingService and AppStore account transactions',
    );
  }

  Future<List<_AssistantParty>> _loadPartyCandidates(
    AppStore store,
    String partyType,
  ) async {
    if (partyType == 'customer') {
      await store.ensureCustomersLoaded();
      return store.customers
          .where((customer) => !customer.isDeleted)
          .map((customer) => _AssistantParty(customer.id, customer.name))
          .toList(growable: false);
    }
    await store.ensureSuppliersLoaded();
    return store.suppliers
        .where((supplier) => !supplier.isDeleted)
        .map((supplier) => _AssistantParty(supplier.id, supplier.name))
        .toList(growable: false);
  }

  List<_AssistantParty> _matchPartyCandidates(
    List<_AssistantParty> candidates,
    String query,
  ) {
    final normalizedQuery = _normalizePartyName(query);
    final exact = candidates
        .where((party) =>
            _normalizePartyName(party.name) == normalizedQuery ||
            party.id.trim().toLowerCase() == query.trim().toLowerCase())
        .toList(growable: false);
    return exact.isNotEmpty
        ? exact
        : candidates
            .where((party) =>
                _normalizePartyName(party.name).contains(normalizedQuery))
            .toList(growable: false);
  }
}
