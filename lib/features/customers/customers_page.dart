import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';
import '../../data/app_store.dart';
import '../../models/customer.dart';
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
    final customers = widget.store.customers.where((customer) {
      final value = query.toLowerCase();
      return customer.name.toLowerCase().contains(value) || customer.phone.toLowerCase().contains(value);
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(16),
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
            decoration: InputDecoration(hintText: tr.text('search_customer'), prefixIcon: const Icon(Icons.search)),
            onChanged: (value) => setState(() => query = value),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: customers.isEmpty
                ? EmptyStateCard(icon: Icons.people_outline, title: tr.text('no_customers'), subtitle: tr.text('no_customers_desc'))
                : Card(
                    child: ListView.separated(
                      itemCount: customers.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final customer = customers[index];
                        return ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                          title: Text(customer.name),
                          subtitle: Text('${customer.phone} • ${customer.address}'),
                          trailing: Wrap(
                            children: [
                              IconButton(onPressed: () => _openCustomerForm(context, customer: customer), icon: const Icon(Icons.edit_outlined)),
                              IconButton(onPressed: () => _deleteCustomer(context, customer), icon: const Icon(Icons.delete_outline)),
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
    await widget.store.deleteCustomer(customer.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Customer deleted: ${customer.name}')));
    }
  }

  Future<void> _openCustomerForm(BuildContext context, {Customer? customer}) async {
    final result = await showDialog<Customer>(
      context: context,
      builder: (_) => _CustomerDialog(customer: customer),
    );
    if (result != null) {
      await widget.store.addOrUpdateCustomer(result);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(customer == null ? 'Customer saved' : 'Customer updated')));
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
    return AlertDialog(
      title: Text(widget.customer == null ? tr.text('add_customer') : tr.text('edit_customer')),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(controller: nameController, decoration: InputDecoration(labelText: tr.text('customer_name')), validator: _required),
              const SizedBox(height: 12),
              TextFormField(controller: phoneController, decoration: InputDecoration(labelText: tr.text('phone'))),
              const SizedBox(height: 12),
              TextFormField(controller: addressController, decoration: InputDecoration(labelText: tr.text('address'))),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr.text('cancel'))),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              Customer(
                id: widget.customer?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
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

  String? _required(String? value) => value == null || value.trim().isEmpty ? 'Required' : null;
}
