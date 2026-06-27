// ignore_for_file: curly_braces_in_flow_control_structures

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/utils/responsive.dart';
import '../../data/app_store.dart';
import '../../models/customer.dart';
import '../../models/user_role.dart';
import '../accounts/account_ledger_widgets.dart';
import '../../widgets/app_section_header.dart';
import '../../widgets/empty_state_card.dart';

class CustomersPage extends StatefulWidget {
  const CustomersPage({super.key, required this.store});

  final AppStore store;

  @override
  State<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends State<CustomersPage> {
  String query = '';

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
    final customers = widget.store.customers.where((customer) {
      final isWalkIn = customer.id == AppStore.walkInCustomerId ||
          customer.name.trim().toLowerCase() ==
              AppStore.walkInCustomerName.toLowerCase();
      if (isWalkIn) return false;
      return customer.name.toLowerCase().contains(value) ||
          customer.phone.toLowerCase().contains(value);
    }).toList();

    return Padding(
      padding: VentioResponsive.pageInsets(context),
      child: Column(
        children: [
          AppSectionHeader(
            title: tr.text('customers'),
            subtitle: tr.text('customers_page_desc'),
            action: FilledButton.icon(
              onPressed: widget.store.canManageCustomers
                  ? () => _openCustomerForm(context)
                  : null,
              icon: const Icon(Icons.person_add_alt_1),
              label: Text(tr.text('add_customer')),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            decoration: InputDecoration(
                hintText: tr.text('search_customer'),
                prefixIcon: const Icon(Icons.search)),
            onChanged: (value) => setState(() => query = value),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: customers.isEmpty
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
                          itemCount: customers.length,
                          itemBuilder: (context, index) {
                            final customer = customers[index];
                            return ListTile(
                              leading: const CircleAvatar(
                                  child: Icon(Icons.person_outline)),
                              title: Text(customer.name),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${customer.phone} ? ${customer.address}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 4),
                                  Text(
                                    accountBalanceText(context, widget.store,
                                        'customer', customer.id),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: accountBalanceColor(context,
                                            widget.store,
                                            'customer',
                                            customer.id),
                                        fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                              trailing: VentioResponsive.isMobile(context)
                                  ? PopupMenuButton<String>(
                                      tooltip: tr.text('actions'),
                                      onSelected: (value) {
                                        if (value == 'ledger' &&
                                            widget.store.hasAnyPermission(<String>{
                                              AppPermission.customersLedgerView,
                                              AppPermission.customersManage,
                                            })) {
                                          showAccountLedgerSheet(
                                              context: context,
                                              store: widget.store,
                                              accountType: 'customer',
                                              accountId: customer.id,
                                              accountName: customer.name);
                                        }
                                        if (value == 'payment' &&
                                            widget.store.hasAnyPermission(<String>{
                                              AppPermission.customersPaymentManage,
                                              AppPermission.customersManage,
                                            })) {
                                          showAccountPaymentDialog(
                                              context: context,
                                              store: widget.store,
                                              accountType: 'customer',
                                              accountId: customer.id,
                                              accountName: customer.name);
                                        }
                                        if (value == 'edit' &&
                                            widget.store.canManageCustomers) {
                                          _openCustomerForm(context,
                                              customer: customer);
                                        }
                                        if (value == 'delete' &&
                                            widget.store.canManageCustomers) {
                                          _deleteCustomer(context, customer);
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        PopupMenuItem(
                                            value: 'ledger',
                                            child: Text(
                                                tr.text('account_ledger'))),
                                        PopupMenuItem(
                                            value: 'payment',
                                            child: Text(
                                                tr.text('receive_payment'))),
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
                                            onPressed: widget.store.hasAnyPermission(<String>{
                                                      AppPermission.customersLedgerView,
                                                      AppPermission.customersManage,
                                                    })
                                                ? () => showAccountLedgerSheet(
                                                    context: context,
                                                    store: widget.store,
                                                    accountType: 'customer',
                                                    accountId: customer.id,
                                                    accountName:
                                                        customer.name)
                                                : null,
                                            icon: const Icon(
                                                Icons.receipt_long_outlined),
                                            tooltip: tr.text('account_ledger')),
                                        IconButton(
                                            onPressed: widget.store.hasAnyPermission(<String>{
                                                      AppPermission.customersPaymentManage,
                                                      AppPermission.customersManage,
                                                    })
                                                ? () => showAccountPaymentDialog(
                                                    context: context,
                                                    store: widget.store,
                                                    accountType: 'customer',
                                                    accountId: customer.id,
                                                    accountName:
                                                        customer.name)
                                                : null,
                                            icon: const Icon(
                                                Icons.payments_outlined),
                                            tooltip: tr.text('receive_payment')),
                                        IconButton(
                                            onPressed: widget.store.canManageCustomers
                                                ? () => _openCustomerForm(
                                                    context,
                                                    customer: customer)
                                                : null,
                                            icon: const Icon(
                                                Icons.edit_outlined),
                                            tooltip: tr.text('edit')),
                                        IconButton(
                                            onPressed: widget.store.canManageCustomers
                                                ? () => _deleteCustomer(
                                                    context,
                                                    customer)
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
    await widget.store.deleteCustomer(customer.id);
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
      await widget.store.addOrUpdateCustomer(result);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context).text(
                customer == null ? 'customer_saved' : 'customer_updated'))));
      }
    }
  }
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
