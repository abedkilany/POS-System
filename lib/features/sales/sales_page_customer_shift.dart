// ignore_for_file: invalid_use_of_protected_member
part of 'sales_page.dart';

extension _SalesPageCustomerShift on _SalesPageState {
  double _salePriceFor(Product product, ProductSaleUnit unit) {
    final configured = widget.store
        .catalog.productPriceFor(product.id, _salePriceType, unitId: unit.id);
    if (configured != null) {
      final override = widget.store.catalog.productPriceOverrideFor(
          configured, widget.store.runtime.profile.defaultSaleInvoiceCurrency);
      if (override != null) {
        return toUsdReferencePrice(
            override.amount, override.currencyCode, widget.store.runtime.profile);
      }
      return toUsdReferencePrice(configured.baseAmount,
          configured.baseCurrencyCode, widget.store.runtime.profile);
    }
    return widget.store.catalog.defaultProductUsdPrice(product, unitId: unit.id);
  }

  void _setSalePriceType(String value) {
    if (value == _salePriceType) return;
    setState(() {
      _salePriceType = value;
      for (var index = 0; index < _cart.length; index++) {
        final item = _cart[index];
        _cart[index] = item.copyWith(
            saleUnit: item.saleUnit
                .copyWith(price: _salePriceFor(item.product, item.saleUnit)));
      }
    });
  }

  Widget _buildSalePriceTypeSelector(
      BuildContext context, AppLocalizations tr) {
    return Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('${tr.text('invoice_price_type')}:',
              style: Theme.of(context).textTheme.labelLarge),
          ChoiceChip(
              label: Text(tr.text('retail_price')),
              selected: _salePriceType == 'retail',
              onSelected: (_) => _setSalePriceType('retail')),
          ChoiceChip(
              label: Text(tr.text('wholesale_price')),
              selected: _salePriceType == 'wholesale',
              onSelected: (_) => _setSalePriceType('wholesale')),
          ChoiceChip(
              label: Text(tr.text('bulk_wholesale_price')),
              selected: _salePriceType == 'wholesale_bulk',
              onSelected: (_) => _setSalePriceType('wholesale_bulk'))
        ]);
  }

  Customer _selectedCustomer() {
    final id = widget.store.commerce.sanitizeSelectedCustomerId(_selectedCustomerId);
    return widget.store.commerce.customers.firstWhere((customer) => customer.id == id,
        orElse: () => widget.store.commerce.walkInCustomer);
  }

  String _walkInCustomerLabel(AppLocalizations tr) {
    final localized = tr.text('walk_in_customer');
    return localized.isNotEmpty ? localized : widget.store.commerce.walkInCustomer.name;
  }

  String _customerSearchText(Customer customer, AppLocalizations tr) {
    if (customer.id == AppStore.walkInCustomerId) {
      return _walkInCustomerLabel(tr);
    }
    return customer.name;
  }

  List<Customer> _customerSearchOptions(String query, AppLocalizations tr) {
    final rawQuery = query.trim().toLowerCase();
    final walkInName = _walkInCustomerLabel(tr).toLowerCase();
    final normalized = rawQuery == walkInName ? '' : rawQuery;
    final seen = <String>{};
    final customers = <Customer>[];
    for (final customer in [
      widget.store.commerce.walkInCustomer,
      ...widget.store.commerce.customers
    ]) {
      if (!seen.add(customer.id)) continue;
      if (normalized.isEmpty ||
          customer.name.toLowerCase().contains(normalized) ||
          customer.phone.toLowerCase().contains(normalized) ||
          customer.id.toLowerCase().contains(normalized)) {
        customers.add(customer);
      }
    }
    customers.sort((a, b) {
      if (a.id == AppStore.walkInCustomerId) return -1;
      if (b.id == AppStore.walkInCustomerId) return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return customers.take(20).toList();
  }

  Widget _buildCustomerSelector(BuildContext context, AppLocalizations tr,
      {bool dense = false, void Function(void Function())? modalSetState}) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
          child: RawAutocomplete<Customer>(
              key: ValueKey(
                  'sale_customer_${_selectedCustomerId}_${widget.store.commerce.customersRevision}'),
              initialValue: TextEditingValue(
                  text: _customerSearchText(_selectedCustomer(), tr)),
              displayStringForOption: (customer) =>
                  _customerSearchText(customer, tr),
              optionsBuilder: (value) => _customerSearchOptions(value.text, tr),
              onSelected: (customer) {
                _setSelectedCustomerId(customer.id);
                modalSetState?.call(() {});
              },
              fieldViewBuilder:
                  (context, controller, focusNode, onFieldSubmitted) {
                return TextFormField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: InputDecoration(
                        labelText: tr.text('customer'),
                        hintText: '${tr.text('search')} / phone / ID',
                        isDense: dense,
                        prefixIcon: const Icon(Icons.search)),
                    onTap: () => controller.selection = TextSelection(
                        baseOffset: 0, extentOffset: controller.text.length));
              },
              optionsViewBuilder: (context, onSelected, options) {
                final list = options.toList();
                return Align(
                    alignment: AlignmentDirectional.topStart,
                    child: Material(
                        elevation: 8,
                        borderRadius: BorderRadius.circular(12),
                        clipBehavior: Clip.antiAlias,
                        child: ConstrainedBox(
                            constraints: const BoxConstraints(
                                maxHeight: 280, maxWidth: 520),
                            child: ListView.separated(
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                itemCount: list.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final customer = list[index];
                                  final isWalkIn =
                                      customer.id == AppStore.walkInCustomerId;
                                  final phone = customer.phone.trim();
                                  final walkInLabel = _walkInCustomerLabel(tr);
                                  return ListTile(
                                      dense: true,
                                      leading: Icon(isWalkIn
                                          ? Icons.person_outline
                                          : Icons.badge_outlined),
                                      title: Text(
                                          isWalkIn
                                              ? walkInLabel
                                              : '#${customer.id} - ${customer.name}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                      subtitle: isWalkIn || phone.isEmpty
                                          ? null
                                          : Text(phone,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis),
                                      onTap: () => onSelected(customer));
                                }))));
              })),
      const SizedBox(width: 8),
      IconButton.filledTonal(
          onPressed: () async {
            final id = await _showQuickCustomerDialog(context, tr);
            if (id == null || !mounted) return;
            _setSelectedCustomerId(id);
            modalSetState?.call(() {});
          },
          icon: const Icon(Icons.person_add_alt_1),
          tooltip: tr.text('add_customer'))
    ]);
  }

  Widget _buildPaymentMethodChips(AppLocalizations tr,
      {void Function(void Function())? modalSetState}) {
    final methods = <MapEntry<String, String>>[
      MapEntry('Cash', tr.text('payment_cash')),
      if (!_isWalkInCustomer) MapEntry('Credit', tr.text('credit_unpaid')),
      MapEntry('Card', tr.text('payment_card')),
      MapEntry('Wish', tr.text('payment_wish')),
      MapEntry('Check', tr.text('payment_check'))
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr.text('payment_method'),
          style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final method in methods)
          ChoiceChip(
              label: Text(method.value),
              selected: _paymentMethod == method.key,
              onSelected: (_) {
                _setPaymentMethod(method.key);
                modalSetState?.call(() {});
              })
      ])
    ]);
  }

  Widget _buildPaymentCurrencySwitch(AppLocalizations tr,
      {void Function(void Function())? modalSetState}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr.text('payment_currency'),
          style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 8),
      LayoutBuilder(builder: (context, constraints) {
        final fullWidth = constraints.maxWidth < 420;
        final currencies = widget.store.runtime.profile.currencies
            .where((item) => item.isActive)
            .toList(growable: false);
        final children = [
          for (final currency in currencies)
            ChoiceChip(
                label: Text(currency.code),
                selected: _paymentCurrency == currency.code,
                onSelected: (_) {
                  setState(() => _paymentCurrency = currency.code);
                  modalSetState?.call(() {});
                })
        ];
        if (!fullWidth) {
          return Wrap(spacing: 8, runSpacing: 8, children: children);
        }
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                children[i],
                if (i != children.length - 1) const SizedBox(height: 8)
              ]
            ]);
      })
    ]);
  }

  Widget _buildCashReceivedField(AppLocalizations tr,
      {bool dense = false, void Function(void Function())? modalSetState}) {
    return TextFormField(
        focusNode: _cashReceivedFocusNode,
        controller: _paidAmountController,
        decoration: InputDecoration(
            labelText: '${tr.text('paid_amount')} ($_paymentCurrency)',
            isDense: dense),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}$'))
        ],
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) {
          setState(() {});
          modalSetState?.call(() {});
        });
  }

  Future<String?> _showQuickCustomerDialog(
      BuildContext context, AppLocalizations tr) async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final addressController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    try {
      final customer = await showDialog<Customer>(
          context: context,
          builder: (dialogContext) => AlertDialog(
                  title: Text(tr.text('add_customer')),
                  content: SizedBox(
                      width: 420,
                      child: Form(
                          key: formKey,
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                            TextFormField(
                                controller: nameController,
                                autofocus: true,
                                decoration: InputDecoration(
                                    labelText: tr.text('customer_name')),
                                validator: (value) =>
                                    value == null || value.trim().isEmpty
                                        ? tr.text('required_field')
                                        : null),
                            const SizedBox(height: 12),
                            TextFormField(
                                controller: phoneController,
                                decoration: InputDecoration(
                                    labelText: tr.text('phone'))),
                            const SizedBox(height: 12),
                            TextFormField(
                                controller: addressController,
                                decoration: InputDecoration(
                                    labelText: tr.text('address')))
                          ]))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: Text(tr.text('cancel'))),
                    FilledButton(
                        onPressed: () {
                          if (!formKey.currentState!.validate()) return;
                          Navigator.pop(
                              dialogContext,
                              Customer(
                                  id: DateTime.now()
                                      .microsecondsSinceEpoch
                                      .toString(),
                                  name: nameController.text.trim(),
                                  phone: phoneController.text.trim(),
                                  address: addressController.text.trim()));
                        },
                        child: Text(tr.text('save')))
                  ]));
      if (customer == null) return null;
      if (!context.mounted) return null;
      final messenger = ScaffoldMessenger.of(context);
      final createdMessage = tr.text('customer_created_selected');
      await widget.store.commerce.addOrUpdateCustomer(customer);
      if (!context.mounted) return null;
      messenger.showSnackBar(SnackBar(content: Text(createdMessage)));
      return customer.id;
    } catch (_) {
      if (context.mounted) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(
            SnackBar(content: Text(tr.text('customer_save_failed'))));
      }
      return null;
    } finally {
      nameController.dispose();
      phoneController.dispose();
      addressController.dispose();
    }
  }

  String _activeUserDisplayName([AppUser? user]) {
    final current = user ?? widget.store.security.activeUser;
    final fullName = current?.fullName.trim() ?? '';
    if (fullName.isNotEmpty) return fullName;
    final username = current?.username.trim() ?? '';
    if (username.isNotEmpty) return username;
    return widget.store.security.currentRole;
  }

  Future<_SaleShiftStatus> _loadSaleShiftStatus() async {
    final locations = await AccountingService.listActiveCashLocations();
    final openSessions = await AccountingService.listOpenCashDrawersReport();
    final deviceId = widget.store.runtime.identity.deviceId.trim();
    final branchId = widget.store.runtime.identity.branchId.trim();
    final linkedDrawers = locations
        .where((item) =>
            item.type == 'cash_drawer' &&
            deviceId.isNotEmpty &&
            item.referenceId == deviceId)
        .toList(growable: false);
    final allDrawers = locations
        .where((item) => item.type == 'cash_drawer')
        .toList(growable: false);
    final drawer = linkedDrawers.isNotEmpty
        ? linkedDrawers.first
        : (allDrawers.isNotEmpty ? allDrawers.first : null);
    AdvancedAccountingItem? openSession;
    if (drawer != null) {
      for (final item in openSessions) {
        if (item.referenceId == drawer.id) {
          openSession = item;
          break;
        }
      }
    }
    return _SaleShiftStatus(
        drawer: drawer,
        openSession: openSession,
        drawers: allDrawers,
        cashLocations: locations,
        branchId: branchId);
  }

  Widget _buildSaleShiftActionButton(
      BuildContext context, AppLocalizations tr) {
    return FutureBuilder<_SaleShiftStatus>(
        key: ValueKey('sale_shift_action_$_cashShiftRefreshKey'),
        future: _loadSaleShiftStatus(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2));
          }
          final status = snapshot.data;
          final openSession = status?.openSession;
          if (openSession == null) {
            return OutlinedButton.icon(
                onPressed: status == null || status.drawers.isEmpty
                    ? null
                    : () => _openSaleDrawerDialog(status),
                icon: const Icon(Icons.lock_open_outlined),
                label: Text(tr.text('open_shift')));
          }
          return OutlinedButton.icon(
              onPressed: status == null
                  ? null
                  : () => _closeSaleDrawerDialog(openSession, status),
              icon: const Icon(Icons.lock_outline),
              label: Text(tr.text('close_handover')));
        });
  }

  Widget _buildSaleShiftMobileAction(AppLocalizations tr) {
    return FutureBuilder<_SaleShiftStatus>(
        key: ValueKey('sale_shift_mobile_action_$_cashShiftRefreshKey'),
        future: _loadSaleShiftStatus(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2));
          }
          final status = snapshot.data;
          final openSession = status?.openSession;
          return _MobileSaleAction(
              icon: openSession == null
                  ? Icons.lock_open_outlined
                  : Icons.lock_outline,
              label: openSession == null
                  ? tr.text('open_shift')
                  : tr.text('close_handover'),
              onTap: status == null
                  ? () {}
                  : openSession == null
                      ? (status.drawers.isEmpty
                          ? () {}
                          : () => _openSaleDrawerDialog(status))
                      : () => _closeSaleDrawerDialog(openSession, status));
        });
  }

  Future<void> _showSaleShiftQuickAction() async {
    if (!widget.store.security.canSell) return;
    final tr = AppLocalizations.of(context);
    try {
      final status = await _loadSaleShiftStatus();
      if (!mounted) return;
      final openSession = status.openSession;
      if (openSession == null) {
        if (status.drawers.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(tr.text('add_cash_drawer_first'))));
          return;
        }
        await _openSaleDrawerDialog(status);
      } else {
        await _closeSaleDrawerDialog(openSession, status);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(localizeRuntimeMessage(error.toString(), tr))));
    }
  }
}
