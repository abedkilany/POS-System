import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/utils/responsive.dart';
import '../../data/app_store.dart';
import '../../models/supplier.dart';
import '../accounts/account_ledger_widgets.dart';
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
      return supplier.name.toLowerCase().contains(value) ||
          supplier.phone.toLowerCase().contains(value);
    }).toList();

    return Padding(
      padding: VentioResponsive.pageInsets(context),
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
            decoration: InputDecoration(
                hintText: tr.text('search_supplier'),
                prefixIcon: const Icon(Icons.search)),
            onChanged: (value) => setState(() => query = value),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: suppliers.isEmpty
                ? EmptyStateCard(
                    icon: Icons.local_shipping_outlined,
                    title: tr.text('no_suppliers'),
                    subtitle: tr.text('no_suppliers_desc'))
                : Card(
                    child: ListView.separated(
                      itemCount: suppliers.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final supplier = suppliers[index];
                        return ListTile(
                          leading: const CircleAvatar(
                              child: Icon(Icons.local_shipping_outlined)),
                          title: Text(supplier.name),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text([
                                supplier.phone,
                                supplier.address,
                                supplier.notes
                              ].where((e) => e.isNotEmpty).join(' • ')),
                              const SizedBox(height: 4),
                              Text(
                                accountBalanceText(context, widget.store,
                                    'supplier', supplier.id),
                                style: TextStyle(
                                    color: accountBalanceColor(context,
                                        widget.store, 'supplier', supplier.id),
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
                                          accountType: 'supplier',
                                          accountId: supplier.id,
                                          accountName: supplier.name);
                                    }
                                    if (value == 'payment') {
                                      showAccountPaymentDialog(
                                          context: context,
                                          store: widget.store,
                                          accountType: 'supplier',
                                          accountId: supplier.id,
                                          accountName: supplier.name);
                                    }
                                    if (value == 'edit') {
                                      _openSupplierForm(context,
                                          supplier: supplier);
                                    }
                                    if (value == 'delete') {
                                      _deleteSupplier(context, supplier);
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    PopupMenuItem(
                                        value: 'ledger',
                                        child: Text(tr.text('account_ledger'))),
                                    PopupMenuItem(
                                        value: 'payment',
                                        child: Text(tr.text('pay_supplier'))),
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
                                            accountType: 'supplier',
                                            accountId: supplier.id,
                                            accountName: supplier.name),
                                        icon: const Icon(
                                            Icons.receipt_long_outlined),
                                        tooltip: tr.text('account_ledger')),
                                    IconButton(
                                        onPressed: () =>
                                            showAccountPaymentDialog(
                                                context: context,
                                                store: widget.store,
                                                accountType: 'supplier',
                                                accountId: supplier.id,
                                                accountName: supplier.name),
                                        icon:
                                            const Icon(Icons.payment_outlined),
                                        tooltip: tr.text('pay_supplier')),
                                    IconButton(
                                        onPressed: () => _openSupplierForm(
                                            context,
                                            supplier: supplier),
                                        icon: const Icon(Icons.edit_outlined),
                                        tooltip: tr.text('edit')),
                                    IconButton(
                                        onPressed: () =>
                                            _deleteSupplier(context, supplier),
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

  Future<void> _deleteSupplier(BuildContext context, Supplier supplier) async {
    final tr = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr.text('confirm_delete')),
        content: Text('${tr.text('delete_confirm_message')} ${supplier.name}?'),
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
    await widget.store.deleteSupplier(supplier.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr
              .text('supplier_deleted')
              .replaceAll('{name}', supplier.name))));
    }
  }

  Future<void> _openSupplierForm(BuildContext context,
      {Supplier? supplier}) async {
    final result = await showDialog<Supplier>(
      context: context,
      builder: (_) => _SupplierDialog(supplier: supplier),
    );
    if (result != null) {
      await widget.store.addOrUpdateSupplier(result);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context).text(
                supplier == null ? 'supplier_saved' : 'supplier_updated'))));
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
    nameEnController = TextEditingController(
        text: supplier?.nameEn.isNotEmpty == true
            ? supplier!.nameEn
            : supplier?.name ?? '');
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
      title: Text(widget.supplier == null
          ? tr.text('add_supplier')
          : tr.text('edit_supplier')),
      content: ResponsiveDialogBox(
        maxWidth: VentioResponsive.dialogWidth(
          context,
          mobile: 420,
          tablet: 680,
          desktop: 720,
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                    controller: nameEnController,
                    decoration: InputDecoration(labelText: tr.text('name_en')),
                    validator: _required),
                const SizedBox(height: 12),
                TextFormField(
                    controller: nameArController,
                    decoration: InputDecoration(labelText: tr.text('name_ar'))),
                const SizedBox(height: 12),
                TextFormField(
                    controller: phoneController,
                    decoration: InputDecoration(labelText: tr.text('phone'))),
                const SizedBox(height: 12),
                TextFormField(
                    controller: addressController,
                    decoration: InputDecoration(labelText: tr.text('address'))),
                const SizedBox(height: 12),
                TextFormField(
                    controller: notesController,
                    decoration: InputDecoration(labelText: tr.text('notes')),
                    maxLines: 3),
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
              Supplier(
                id: widget.supplier?.id ??
                    DateTime.now().microsecondsSinceEpoch.toString(),
                name: nameEnController.text.trim().isNotEmpty
                    ? nameEnController.text.trim()
                    : nameArController.text.trim(),
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

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;
}
