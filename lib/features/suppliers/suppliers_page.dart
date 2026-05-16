import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';
import '../../data/app_store.dart';
import '../../models/supplier.dart';
import '../../widgets/app_section_header.dart';
import '../../widgets/empty_state_card.dart';

class SuppliersPage extends StatefulWidget {
  const SuppliersPage({super.key, required this.store});

  final AppStore store;

  @override
  State<SuppliersPage> createState() => _SuppliersPageState();
}

class _SuppliersPageState extends State<SuppliersPage> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final suppliers = widget.store.suppliers.where((supplier) {
      final value = query.toLowerCase();
      return supplier.name.toLowerCase().contains(value) || supplier.phone.toLowerCase().contains(value);
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          AppSectionHeader(
            title: tr.text('suppliers'),
            subtitle: tr.text('suppliers_page_desc'),
            action: FilledButton.icon(
              onPressed: () => _openSupplierForm(context),
              icon: const Icon(Icons.local_shipping_outlined),
              label: Text(tr.text('add_supplier')),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            decoration: InputDecoration(hintText: tr.text('search_supplier'), prefixIcon: const Icon(Icons.search)),
            onChanged: (value) => setState(() => query = value),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: suppliers.isEmpty
                ? EmptyStateCard(icon: Icons.local_shipping_outlined, title: tr.text('no_suppliers'), subtitle: tr.text('no_suppliers_desc'))
                : Card(
                    child: ListView.separated(
                      itemCount: suppliers.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final supplier = suppliers[index];
                        return ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.local_shipping_outlined)),
                          title: Text(supplier.name),
                          subtitle: Text([supplier.phone, supplier.address, supplier.notes].where((e) => e.isNotEmpty).join(' • ')),
                          trailing: Wrap(
                            children: [
                              IconButton(onPressed: () => _openSupplierForm(context, supplier: supplier), icon: const Icon(Icons.edit_outlined)),
                              IconButton(onPressed: () => _deleteSupplier(context, supplier), icon: const Icon(Icons.delete_outline)),
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

  Future<void> _deleteSupplier(BuildContext context, Supplier supplier) async {
    await widget.store.deleteSupplier(supplier.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Supplier deleted: ${supplier.name}')));
    }
  }

  Future<void> _openSupplierForm(BuildContext context, {Supplier? supplier}) async {
    final result = await showDialog<Supplier>(
      context: context,
      builder: (_) => _SupplierDialog(supplier: supplier),
    );
    if (result != null) {
      await widget.store.addOrUpdateSupplier(result);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(supplier == null ? 'Supplier saved' : 'Supplier updated')));
      }
    }
  }
}

class _SupplierDialog extends StatefulWidget {
  const _SupplierDialog({this.supplier});

  final Supplier? supplier;

  @override
  State<_SupplierDialog> createState() => _SupplierDialogState();
}

class _SupplierDialogState extends State<_SupplierDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController nameController;
  late final TextEditingController nameEnController;
  late final TextEditingController nameArController;
  late final TextEditingController phoneController;
  late final TextEditingController addressController;
  late final TextEditingController notesController;

  @override
  void initState() {
    super.initState();
    final supplier = widget.supplier;
    nameController = TextEditingController(text: supplier?.name ?? '');
    nameEnController = TextEditingController(text: supplier?.nameEn.isNotEmpty == true ? supplier!.nameEn : supplier?.name ?? '');
    nameArController = TextEditingController(text: supplier?.nameAr ?? '');
    phoneController = TextEditingController(text: supplier?.phone ?? '');
    addressController = TextEditingController(text: supplier?.address ?? '');
    notesController = TextEditingController(text: supplier?.notes ?? '');
  }

  @override
  void dispose() {
    nameController.dispose();
    nameEnController.dispose();
    nameArController.dispose();
    phoneController.dispose();
    addressController.dispose();
    notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.supplier == null ? tr.text('add_supplier') : tr.text('edit_supplier')),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(controller: nameEnController, decoration: InputDecoration(labelText: tr.text('name_en')), validator: _required),
                const SizedBox(height: 12),
                TextFormField(controller: nameArController, decoration: InputDecoration(labelText: tr.text('name_ar'))),
                const SizedBox(height: 12),
                TextFormField(controller: phoneController, decoration: InputDecoration(labelText: tr.text('phone'))),
                const SizedBox(height: 12),
                TextFormField(controller: addressController, decoration: InputDecoration(labelText: tr.text('address'))),
                const SizedBox(height: 12),
                TextFormField(controller: notesController, decoration: InputDecoration(labelText: tr.text('notes')), maxLines: 3),
              ],
            ),
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
              Supplier(
                id: widget.supplier?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
                name: nameEnController.text.trim().isNotEmpty ? nameEnController.text.trim() : nameArController.text.trim(),
                nameEn: nameEnController.text.trim(),
                nameAr: nameArController.text.trim(),
                phone: phoneController.text.trim(),
                address: addressController.text.trim(),
                notes: notesController.text.trim(),
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
