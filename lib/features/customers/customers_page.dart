import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/utils/responsive.dart';
import '../../data/app_store.dart';
import '../../models/customer.dart';
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
              onPressed: () => _openCustomerForm(context),
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
                    child: ListView.separated(
                      itemCount: customers.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final customer = customers[index];
                        return ListTile(
                          leading: const CircleAvatar(
                              child: Icon(Icons.person_outline)),
                          title: Text(customer.name),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${customer.phone} • ${customer.address}'),
                              const SizedBox(height: 4),
                              Text(
                                accountBalanceText(context, widget.store,
                                    'customer', customer.id),
                                style: TextStyle(
                                    color: accountBalanceColor(context,
                                        widget.store, 'customer', customer.id),
                                    fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                          trailing: VentioResponsive.isMobile(context)
                              ? PopupMenuButton<String>(
                                  tooltip: tr.text('actions'),
                                  onSelected: (value) {
                                    if (value == 'ledger') {
                                      showAccountLedgerSheet(
                                          context: context,
                                          store: widget.store,
                                          accountType: 'customer',
                                          accountId: customer.id,
                                          accountName: customer.name);
                                    }
                                    if (value == 'payment') {
                                      showAccountPaymentDialog(
                                          context: context,
                                          store: widget.store,
                                          accountType: 'customer',
                                          accountId: customer.id,
                                          accountName: customer.name);
                                    }
                                    if (value == 'edit') {
                                      _openCustomerForm(context,
                                          customer: customer);
                                    }
                                    if (value == 'delete') {
                                      _deleteCustomer(context, customer);
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    PopupMenuItem(
                                        value: 'ledger',
                                        child: Text(tr.text('account_ledger'))),
                                    PopupMenuItem(
                                        value: 'payment',
                                        child:
                                            Text(tr.text('receive_payment'))),
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
                                        onPressed: () => showAccountLedgerSheet(
                                            context: context,
                                            store: widget.store,
                                            accountType: 'customer',
                                            accountId: customer.id,
                                            accountName: customer.name),
                                        icon: const Icon(
                                            Icons.receipt_long_outlined),
                                        tooltip: tr.text('account_ledger')),
                                    IconButton(
                                        onPressed: () =>
                                            showAccountPaymentDialog(
                                                context: context,
                                                store: widget.store,
                                                accountType: 'customer',
                                                accountId: customer.id,
                                                accountName: customer.name),
                                        icon:
                                            const Icon(Icons.payments_outlined),
                                        tooltip: tr.text('receive_payment')),
                                    IconButton(
                                        onPressed: () => _openCustomerForm(
                                            context,
                                            customer: customer),
                                        icon: const Icon(Icons.edit_outlined),
                                        tooltip: tr.text('edit')),
                                    IconButton(
                                        onPressed: () =>
                                            _deleteCustomer(context, customer),
                                        icon: const Icon(Icons.delete_outline),
                                        tooltip: tr.text('delete')),
                                  ],
                                ),
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
