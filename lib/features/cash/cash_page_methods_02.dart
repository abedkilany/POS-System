part of 'cash_page.dart';

extension _CashPageStatePart2 on _CashPageState {
  Future<void> _refundDialog() async {
    final tr = AppLocalizations.of(context);
    await widget.store.commerce.ensurePurchasesLoaded();
    if (!mounted) return;
    try {
      await widget.store.commerce.normalizeRefundAllocations();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizeRuntimeMessage(error.toString(), tr))),
      );
      return;
    }
    final options = <Map<String, Object>>[];
    final purchases = await _cashPurchasesSnapshot();
    if (!mounted) return;

    if (widget.store.security.canDeleteOrCancel) {
      for (final sale
          in widget.store.commerce.sales.where((item) => !item.isDeleted)) {
        try {
          final available =
              await widget.store.commerce.refundableSaleCashAmount(sale.id);
          if (available > 0.000001) {
            options.add(<String, Object>{
              'kind': 'sale',
              'id': sale.id,
              'label': '${sale.invoiceNo} • ${sale.customerName}',
              'amount': available,
            });
          }
        } catch (_) {
          // A single stale invoice must not prevent other valid refunds.
        }
      }
    }

    if (widget.store.security.canManageSupplierPayments) {
      for (final purchase in purchases
          .where((item) => !item.isDeleted && !item.isPurchaseReturn)) {
        try {
          final available = await widget.store.commerce
              .refundablePurchaseCashAmount(purchase.id);
          if (available > 0.000001) {
            options.add(<String, Object>{
              'kind': 'purchase',
              'id': purchase.id,
              'label': '${purchase.purchaseNo} • ${purchase.supplierName}',
              'amount': available,
            });
          }
        } catch (_) {
          // A single stale invoice must not prevent other valid refunds.
        }
      }
      for (final purchase in purchases.where((item) =>
          !item.isDeleted && !item.isCancelled && item.isPurchaseReturn)) {
        try {
          final available = await widget.store
              .commerce.refundablePurchaseReturnCashAmount(purchase.id);
          if (available > 0.000001) {
            options.add(<String, Object>{
              'kind': 'purchase_return',
              'id': purchase.id,
              'label': '${purchase.purchaseNo} • ${purchase.supplierName}',
              'amount': available,
            });
          }
        } catch (_) {
          // A single stale return must not prevent other valid refunds.
        }
      }
    }

    if (widget.store.security.canManageExpenses) {
      for (final expense in widget.store.commerce.expenses.where(
        (item) => !item.isDeleted && item.isPosted,
      )) {
        try {
          final available =
              await widget.store.commerce.refundableExpenseCashAmount(expense.id);
          if (available > 0.000001) {
            options.add(<String, Object>{
              'kind': 'expense',
              'id': expense.id,
              'label': '${expense.title} • ${expense.category}',
              'amount': available,
            });
          }
        } catch (_) {
          // A single stale expense must not prevent other valid refunds.
        }
      }
    }

    if (!mounted) return;
    if (options.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_l(
            tr,
            'No invoice or expense has a cash overpayment available for refund.',
            'لا توجد فاتورة أو مصروف لديه مبلغ نقدي زائد متاح للاسترداد.',
          )),
        ),
      );
      return;
    }

    var selected = options.first;
    final amountController = TextEditingController(
      text: (selected['amount'] as double).toStringAsFixed(2),
    );
    final notesController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(_l(tr, 'Refund', 'استرداد')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: '${selected['kind']}:${selected['id']}',
                  decoration: InputDecoration(
                    labelText: _l(
                        tr, 'Refundable document', 'المستند القابل للاسترداد'),
                  ),
                  items: options.map((item) {
                    final kind = item['kind'] as String;
                    final direction = kind == 'purchase' ||
                            kind == 'purchase_return'
                        ? _l(tr, 'Supplier → Cash', 'من المورد إلى الصندوق')
                        : kind == 'expense'
                            ? _l(tr, 'Expense → Cash', 'استرداد زائد المصروف')
                            : _l(
                                tr, 'Cash → Customer', 'من الصندوق إلى الزبون');
                    return DropdownMenuItem<String>(
                      value: '$kind:${item['id']}',
                      child: Text(
                        '$direction • ${item['label']} • ${formatUsdReferenceAmount(item['amount'] as double, widget.store.runtime.profile)}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(growable: false),
                  onChanged: (value) {
                    if (value == null) return;
                    final found = options.where(
                      (item) => '${item['kind']}:${item['id']}' == value,
                    );
                    if (found.isEmpty) return;
                    setDialogState(() {
                      selected = found.first;
                      amountController.text =
                          (selected['amount'] as double).toStringAsFixed(2);
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('CashRefundAmountField'),
                  controller: amountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: tr.text('amount'),
                    helperText:
                        '${_l(tr, 'Available', 'المتاح')}: ${formatUsdReferenceAmount(selected['amount'] as double, widget.store.runtime.profile)}',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  decoration: InputDecoration(labelText: tr.text('notes')),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(tr.text('cancel')),
            ),
            FilledButton(
              key: const ValueKey('CashRefundConfirmButton'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(_l(tr, 'Refund', 'استرداد')),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) {
      amountController.dispose();
      notesController.dispose();
      return;
    }
    if (!mounted) {
      amountController.dispose();
      notesController.dispose();
      return;
    }

    final rawAmount = amountController.text.trim();
    final normalizedAmount = rawAmount
        .replaceAll('٠', '0')
        .replaceAll('١', '1')
        .replaceAll('٢', '2')
        .replaceAll('٣', '3')
        .replaceAll('٤', '4')
        .replaceAll('٥', '5')
        .replaceAll('٦', '6')
        .replaceAll('٧', '7')
        .replaceAll('٨', '8')
        .replaceAll('٩', '9')
        .replaceAll('٫', '.')
        .replaceAll('٬', '')
        .replaceAll(',', '.');
    final amount = double.tryParse(normalizedAmount) ?? 0;
    final available = selected['amount'] as double;
    // The dialog displays/refills monetary amounts to 2 decimals while the
    // accounting layer intentionally keeps up to 6 decimals. Accept a value
    // that differs only by normal cent-rounding; the service below still caps
    // the posted refund to the exact authoritative refundable amount.
    const displayRoundingTolerance = 0.005001;
    if (amount <= 0 || amount > available + displayRoundingTolerance) {
      amountController.dispose();
      notesController.dispose();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              _l(tr, 'Invalid refund amount.', 'قيمة الاسترداد غير صالحة.')),
        ),
      );
      return;
    }

    try {
      final kind = selected['kind'] as String;
      final id = selected['id'] as String;
      final refunded = kind == 'purchase_return'
          ? await widget.store.commerce.refundPurchaseReturnCash(
              purchaseReturnId: id,
              amount: amount,
              notes: notesController.text.trim(),
            )
          : kind == 'purchase'
              ? await widget.store.commerce.refundPurchaseCash(
                  purchaseId: id,
                  amount: amount,
                  notes: notesController.text.trim(),
                )
              : kind == 'expense'
                  ? await widget.store.commerce.refundExpenseCash(
                      expenseId: id,
                      amount: amount,
                      notes: notesController.text.trim(),
                    )
                  : await widget.store.commerce.refundSaleCash(
                      saleId: id,
                      amount: amount,
                      notes: notesController.text.trim(),
                    );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            refunded > 0
                ? '${_l(tr, 'Refund posted', 'تم تسجيل الاسترداد')}: ${formatUsdReferenceAmount(refunded, widget.store.runtime.profile)}'
                : _l(tr, 'Nothing remains to refund.',
                    'لا يوجد مبلغ متبقٍ للاسترداد.'),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizeRuntimeMessage(error.toString(), tr))),
      );
    } finally {
      amountController.dispose();
      notesController.dispose();
    }
    _refresh();
  }

  Future<void> _settleExpenseDialog(
    AdvancedAccountingItem? currentDrawer,
    AdvancedAccountingItem? currentSession,
  ) async {
    widget.store.security.requireAllPermissions(<String>{
      AppPermission.cashBoxManage,
      AppPermission.expensesManage,
    });
    final tr = AppLocalizations.of(context);

    // The cash-page Expenses action is reserved for expenses that were already
    // approved as credit. Draft expenses must stay in the Expenses module until
    // they are approved, and cash-approved expenses have already affected cash.
    final creditExpenseBalances =
        await AccountingService.readOutstandingCreditExpenseBalances();
    if (!mounted) return;
    final creditExpenses = widget.store.commerce.expenses
        .where((expense) =>
            !expense.isDeleted &&
            expense.isPosted &&
            expense.amount > 0 &&
            creditExpenseBalances.containsKey(expense.id.trim()))
        .toList(growable: false);
    if (creditExpenses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _l(
              tr,
              'No approved credit expenses are available for disbursement.',
              'لا توجد مصاريف معتمدة آجلة متاحة للصرف.',
            ),
          ),
        ),
      );
      return;
    }

    Expense selectedExpense = creditExpenses.first;
    var selectedOutstanding =
        creditExpenseBalances[selectedExpense.id.trim()] ?? 0;
    final amountController = TextEditingController(
      text: selectedOutstanding.toStringAsFixed(2),
    );
    final formKey = GlobalKey<FormState>();
    final selection = await showDialog<_ExpenseSettlementSelection>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(_l(tr, 'Expense disbursement', 'صرف مصروف')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedExpense.id,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: _l(tr, 'Expense', 'المصروف'),
                  ),
                  items: creditExpenses
                      .map(
                        (expense) => DropdownMenuItem<String>(
                          value: expense.id,
                          child: Text(
                            '${expense.title} • ${expense.category} • ${formatUsdReferenceAmount(expense.amount, widget.store.runtime.profile)}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    final found = creditExpenses
                        .where((expense) => expense.id == value)
                        .toList(growable: false);
                    if (found.isEmpty) return;
                    setDialogState(() {
                      selectedExpense = found.first;
                      selectedOutstanding =
                          creditExpenseBalances[selectedExpense.id.trim()] ?? 0;
                      amountController.text =
                          selectedOutstanding.toStringAsFixed(2);
                    });
                  },
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    '${tr.text('amount')}: ${formatUsdReferenceAmount(selectedExpense.amount, widget.store.runtime.profile)}',
                  ),
                ),
                const SizedBox(height: 8),
                Form(
                  key: formKey,
                  child: TextFormField(
                    key: const ValueKey('ExpenseDisbursementAmountField'),
                    controller: amountController,
                    decoration: InputDecoration(
                      labelText: _l(tr, 'Amount paid now (USD)',
                          'المبلغ المدفوع الآن (USD)'),
                      helperText: _l(
                        tr,
                        'Remaining payable: ${selectedOutstanding.toStringAsFixed(2)} USD',
                        'المتبقي المستحق: ${selectedOutstanding.toStringAsFixed(2)} USD',
                      ),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^\d*\.?\d{0,2}$'),
                      ),
                    ],
                    validator: (value) {
                      final amount = double.tryParse(value?.trim() ?? '');
                      if (amount == null || !amount.isFinite || amount <= 0) {
                        return _l(tr, 'Enter an amount greater than zero.',
                            'أدخل مبلغاً أكبر من صفر.');
                      }
                      if (amount > selectedOutstanding + 0.005) {
                        return _l(
                          tr,
                          'Amount cannot exceed the remaining payable.',
                          'المبلغ لا يجوز أن يتجاوز المتبقي المستحق.',
                        );
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop<_ExpenseSettlementSelection>(dialogContext),
              child: Text(tr.text('cancel')),
            ),
            FilledButton(
              onPressed: () {
                if (!(formKey.currentState?.validate() ?? false)) return;
                Navigator.pop(
                  dialogContext,
                  _ExpenseSettlementSelection(
                    expenseId: selectedExpense.id,
                    amount: double.parse(amountController.text.trim()),
                  ),
                );
              },
              child: Text(_l(tr, 'Disburse', 'صرف')),
            ),
          ],
        ),
      ),
    );
    amountController.dispose();
    if (selection == null || !mounted) return;

    try {
      if (currentDrawer == null || currentSession == null) {
        throw StateError(
          _l(tr, 'An open cash shift is required.',
              'يجب وجود وردية صندوق مفتوحة.'),
        );
      }
      final payableAccountId =
          await AccountingService.resolveCreditExpensePayableAccount(
        selection.expenseId,
      );
      if (payableAccountId.isEmpty) {
        throw StateError(
          _l(
            tr,
            'The default payables account is not configured.',
            'حساب الذمم الدائنة الافتراضي غير مضبوط.',
          ),
        );
      }
      final user = widget.store.security.activeUser;
      await CashOperationService.current(authorization: widget.store)
          .withdrawal(
        cashLocationId: currentDrawer.id,
        cashDrawerSessionId: currentSession.id,
        counterpartAccountId: payableAccountId,
        amount: selection.amount,
        notes:
            'Expense credit settlement: ${selectedExpense.id} - ${selectedExpense.title}',
        createdBy: user?.fullName.trim().isNotEmpty == true
            ? user!.fullName
            : widget.store.security.currentRole,
        createdByUserId: user?.id ?? '',
        deviceId: widget.store.runtime.identity.deviceId,
        branchId: widget.store.runtime.identity.branchId,
        storeId: widget.store.runtime.identity.storeId,
        idempotencyKey: 'expense-credit-settlement:${selection.expenseId}:'
            '$_deviceId:${DateTime.now().microsecondsSinceEpoch}',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _l(
              tr,
              'Credit expense settled successfully.',
              'تم صرف المصروف الآجل وتسجيل حركة الصندوق بنجاح.',
            ),
          ),
        ),
      );
      _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizeRuntimeMessage(error.toString(), tr))),
      );
    }
  }
}
