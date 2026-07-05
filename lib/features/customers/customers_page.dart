// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/services/business_revision_service.dart';
import '../../core/repositories/business_repositories.dart';
import '../../core/services/accounting_service.dart';
import '../../core/services/local_database_service.dart';
import '../../core/utils/responsive.dart';
import '../../data/app_store.dart';
import '../../models/customer.dart';
import '../../models/user_role.dart';
import '../accounts/account_ledger_widgets.dart';
import '../../widgets/app_section_header.dart';
import '../../widgets/empty_state_card.dart';
import '../../widgets/page_data_load_indicator.dart';

class CustomersPage extends StatefulWidget {
  const CustomersPage({super.key, required this.store});

  final AppStore store;

  @override
  State<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends State<CustomersPage> {
  String query = '';
  Timer? _customerRevealTimer;
  int _visibleCustomerCount = 100;
  Future<_CustomerQueryResult?>? _customerQueryFuture;
  String _customerQueryFutureKey = '';

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _customerRevealTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CustomersPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      _customerQueryFuture = null;
      _customerQueryFutureKey = '';
      _resetCustomerReveal();
    }
  }

  void _resetCustomerReveal() {
    _customerRevealTimer?.cancel();
    _customerRevealTimer = null;
    _visibleCustomerCount = 100;
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    if (!widget.store.canViewCustomers) {
      return const _AccessDeniedScaffold(
        title: 'Customers',
        message: 'You do not have access to customer records.',
      );
    }
    final value = query.trim().toLowerCase();
    if (LocalDatabaseService.canQueryBusinessSqlite) {
      return FutureBuilder<_CustomerQueryResult?>(
        future: _queryCustomersFromSqlite(value),
        builder: (context, snapshot) {
          final result = snapshot.data;
          if (result != null && !snapshot.hasError) {
            return _buildCustomersView(
              context,
              tr,
              customers: result.items,
              balancesById: result.balancesById,
              totalCount: result.totalCount,
              loading: snapshot.connectionState == ConnectionState.waiting &&
                  result.items.isEmpty,
              onLoadMore: result.hasMore
                  ? () => _loadMoreCustomers(result.totalCount)
                  : null,
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildCustomersView(
              context,
              tr,
              customers: const <Customer>[],
              balancesById: const <String, double>{},
              totalCount: 0,
              loading: true,
            );
          }
          return _buildCustomersFromMemory(context, tr, value);
        },
      );
    }
    return _buildCustomersFromMemory(context, tr, value);
  }

  Widget _buildCustomersFromMemory(
    BuildContext context,
    AppLocalizations tr,
    String value,
  ) {
    return const Center(child: CircularProgressIndicator.adaptive());
  }

  Future<_CustomerQueryResult?> _queryCustomersFromSqlite(String value) {
    final limit = math.max(1, _visibleCustomerCount);
    final key =
        '${BusinessRevisionService.instance.customersRevision}|$value|$limit';
    if (_customerQueryFuture == null || _customerQueryFutureKey != key) {
      _customerQueryFutureKey = key;
      _customerQueryFuture = () async {
        final page = await CustomerRepository.queryPage(
          query: value,
          limit: limit,
        );
        if (page == null) return null;
        final balancesById = await AccountingService.readPartyBalancesByIds(
          accountType: 'customer',
          accountIds: page.items.map((customer) => customer.id),
        );
        return _CustomerQueryResult(
          items: page.items,
          totalCount: page.totalCount,
          balancesById: balancesById,
        );
      }();
    }
    return _customerQueryFuture!;
  }

  void _loadMoreCustomers(int totalCount) {
    setState(() {
      _customerRevealTimer?.cancel();
      _customerRevealTimer = null;
      _visibleCustomerCount = math.min(totalCount, _visibleCustomerCount + 100);
    });
  }

  Widget _buildCustomersView(
    BuildContext context,
    AppLocalizations tr, {
    required List<Customer> customers,
    required Map<String, double> balancesById,
    required int totalCount,
    bool loading = false,
    VoidCallback? onLoadMore,
  }) {
    final hasLoadMore = onLoadMore != null;
    return Padding(
      padding: VentioResponsive.pageInsets(context),
      child: Column(
        children: [
          AppSectionHeader(
            title: tr.text('customers'),
            subtitle: tr.text('customers_page_desc'),
            action: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                PageDataLoadIndicator(
                  loadedCount: customers.length,
                  totalCount: totalCount,
                ),
                FilledButton.icon(
                  onPressed: widget.store.canManageCustomers
                      ? () => _openCustomerForm(context)
                      : null,
                  icon: const Icon(Icons.person_add_alt_1),
                  label: Text(tr.text('add_customer')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            decoration: InputDecoration(
                hintText: tr.text('search_customer'),
                prefixIcon: const Icon(Icons.search)),
            onChanged: (value) => setState(() {
              query = value;
              _resetCustomerReveal();
            }),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator.adaptive())
                : totalCount == 0
                    ? EmptyStateCard(
                        icon: Icons.people_outline,
                        title: tr.text('no_customers'),
                        subtitle: tr.text('no_customers_desc'))
                    : Card(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final rowExtent =
                                constraints.maxWidth < 620 ? 132.0 : 104.0;
                            return ListView.builder(
                              scrollCacheExtent:
                                  const ScrollCacheExtent.pixels(2000),
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              itemExtent: rowExtent,
                              itemCount:
                                  customers.length + (hasLoadMore ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (index >= customers.length) {
                                  return Center(
                                    child: TextButton.icon(
                                      onPressed: onLoadMore,
                                      icon: const Icon(Icons.expand_more),
                                      label: Text(
                                        '${tr.text('more')} '
                                        '(${customers.length}/$totalCount)',
                                      ),
                                    ),
                                  );
                                }
                                final customer = customers[index];
                                return ListTile(
                                  leading: const CircleAvatar(
                                      child: Icon(Icons.person_outline)),
                                  title: Text(customer.name),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                          '${customer.phone} ? ${customer.address}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                      const SizedBox(height: 4),
                                      Text(
                                        accountBalanceText(
                                          context,
                                          'customer',
                                          balancesById[customer.id] ?? 0,
                                          widget.store.storeProfile,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: accountBalanceColor(
                                            context,
                                            'customer',
                                            balancesById[customer.id] ?? 0,
                                          ),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                  trailing: VentioResponsive.isMobile(context)
                                      ? PopupMenuButton<String>(
                                          tooltip: tr.text('actions'),
                                          onSelected: (value) {
                                            if (value == 'ledger' &&
                                                widget.store
                                                    .hasAnyPermission(<String>{
                                                  AppPermission
                                                      .customersLedgerView,
                                                  AppPermission.customersManage,
                                                })) {
                                              showAccountLedgerSheet(
                                                  context: context,
                                                  store: widget.store,
                                                  accountType: 'customer',
                                                  accountId: customer.id,
                                                  accountName: customer.name);
                                            } else if (value == 'payment' &&
                                                widget.store
                                                    .hasAnyPermission(<String>{
                                                  AppPermission
                                                      .customersPaymentManage,
                                                  AppPermission.customersManage,
                                                })) {
                                              _payCustomer(context, customer);
                                            } else if (value == 'edit' &&
                                                widget
                                                    .store.canManageCustomers) {
                                              _openCustomerForm(context,
                                                  customer: customer);
                                            } else if (value == 'delete' &&
                                                widget
                                                    .store.canManageCustomers) {
                                              _deleteCustomer(
                                                  context, customer);
                                            }
                                          },
                                          itemBuilder: (context) => [
                                            PopupMenuItem(
                                                value: 'ledger',
                                                child: Text(
                                                    tr.text('account_ledger'))),
                                            PopupMenuItem(
                                                value: 'payment',
                                                child: Text(tr
                                                    .text('receive_payment'))),
                                            PopupMenuItem(
                                                value: 'edit',
                                                child: Text(tr.text('edit'))),
                                            PopupMenuItem(
                                                value: 'delete',
                                                child: Text(tr.text('delete'))),
                                          ],
                                        )
                                      : Wrap(
                                          children: [
                                            IconButton(
                                                onPressed: widget.store
                                                        .hasAnyPermission(<String>{
                                                  AppPermission
                                                      .customersLedgerView,
                                                  AppPermission.customersManage,
                                                })
                                                    ? () =>
                                                        showAccountLedgerSheet(
                                                            context: context,
                                                            store: widget.store,
                                                            accountType:
                                                                'customer',
                                                            accountId:
                                                                customer.id,
                                                            accountName:
                                                                customer.name)
                                                    : null,
                                                icon: const Icon(Icons
                                                    .receipt_long_outlined),
                                                tooltip:
                                                    tr.text('account_ledger')),
                                            IconButton(
                                                onPressed: widget.store
                                                        .hasAnyPermission(<String>{
                                                  AppPermission
                                                      .customersPaymentManage,
                                                  AppPermission.customersManage,
                                                })
                                                    ? () => _payCustomer(
                                                        context, customer)
                                                    : null,
                                                icon: const Icon(
                                                    Icons.payments_outlined),
                                                tooltip:
                                                    tr.text('receive_payment')),
                                            IconButton(
                                                onPressed: widget.store
                                                        .canManageCustomers
                                                    ? () => _openCustomerForm(
                                                        context,
                                                        customer: customer)
                                                    : null,
                                                icon: const Icon(
                                                    Icons.edit_outlined),
                                                tooltip: tr.text('edit')),
                                            IconButton(
                                                onPressed: widget.store
                                                        .canManageCustomers
                                                    ? () => _deleteCustomer(
                                                        context, customer)
                                                    : null,
                                                icon: const Icon(
                                                    Icons.delete_outline),
                                                tooltip: tr.text('delete')),
                                          ],
                                        ),
                                );
                              },
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Future<void> _payCustomer(
    BuildContext context,
    Customer customer,
  ) async {
    await showAccountPaymentDialog(
      context: context,
      store: widget.store,
      accountType: 'customer',
      accountId: customer.id,
      accountName: customer.name,
    );
    if (!mounted) return;
    setState(() {
      _customerQueryFuture = null;
      _customerQueryFutureKey = '';
    });
  }

  Future<void> _deleteCustomer(BuildContext context, Customer customer) async {
    if (!widget.store.canManageCustomers) return;
    final tr = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr.text('confirm_delete')),
        content: Text('${tr.text('delete_confirm_message')} ${customer.name}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(tr.text('cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            child: Text(tr.text('delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await CustomerRepository.deleteCustomer(widget.store, customer.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr
              .text('customer_deleted')
              .replaceAll('{name}', customer.name))));
    }
  }

  Future<void> _openCustomerForm(BuildContext context,
      {Customer? customer}) async {
    if (!widget.store.canManageCustomers) return;
    final result = await showDialog<Customer>(
      context: context,
      builder: (_) => _CustomerDialog(customer: customer),
    );
    if (result != null) {
      await CustomerRepository.addOrUpdateCustomer(widget.store, result);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context).text(
                customer == null ? 'customer_saved' : 'customer_updated'))));
      }
    }
  }
}

class _CustomerQueryResult {
  const _CustomerQueryResult({
    required this.items,
    required this.totalCount,
    required this.balancesById,
  });

  final List<Customer> items;
  final int totalCount;
  final Map<String, double> balancesById;

  bool get hasMore => items.length < totalCount;
}

class _AccessDeniedScaffold extends StatelessWidget {
  const _AccessDeniedScaffold({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 42),
                  const SizedBox(height: 12),
                  Text(title,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(message, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CustomerDialog extends StatefulWidget {
  const _CustomerDialog({this.customer});

  final Customer? customer;

  @override
  State<_CustomerDialog> createState() => _CustomerDialogState();
}

class _CustomerDialogState extends State<_CustomerDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController nameController;
  late final TextEditingController phoneController;
  late final TextEditingController addressController;

  @override
  void initState() {
    super.initState();
    final customer = widget.customer;
    nameController = TextEditingController(text: customer?.name ?? '');
    phoneController = TextEditingController(text: customer?.phone ?? '');
    addressController = TextEditingController(text: customer?.address ?? '');
  }

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final dialogWidth = VentioResponsive.modalMaxWidth(context, 600);
    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: VentioResponsive.pagePadding(context),
        vertical: 24,
      ),
      constraints: BoxConstraints(maxWidth: dialogWidth),
      title: Text(widget.customer == null
          ? tr.text('add_customer')
          : tr.text('edit_customer')),
      content: SizedBox(
        width: dialogWidth,
        child: ResponsiveDialogBox(
          maxWidth: dialogWidth,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                    controller: nameController,
                    decoration:
                        InputDecoration(labelText: tr.text('customer_name')),
                    validator: _required),
                const SizedBox(height: 12),
                TextFormField(
                    controller: phoneController,
                    decoration: InputDecoration(labelText: tr.text('phone'))),
                const SizedBox(height: 12),
                TextFormField(
                    controller: addressController,
                    decoration: InputDecoration(labelText: tr.text('address'))),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr.text('cancel'))),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              Customer(
                id: widget.customer?.id ??
                    DateTime.now().microsecondsSinceEpoch.toString(),
                name: nameController.text.trim(),
                phone: phoneController.text.trim(),
                address: addressController.text.trim(),
              ),
            );
          },
          child: Text(tr.text('save')),
        ),
      ],
    );
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;
}
