// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/services/local_database_service.dart';
import '../../core/utils/responsive.dart';
import '../../core/utils/revision_cache.dart';
import '../../data/app_store.dart';
import '../../models/supplier.dart';
import '../../models/user_role.dart';
import '../accounts/account_ledger_widgets.dart';
import '../../widgets/app_section_header.dart';
import '../../widgets/empty_state_card.dart';
import '../../widgets/page_data_load_indicator.dart';

class SuppliersPage extends StatefulWidget {
  const SuppliersPage({super.key, required this.store});

  final AppStore store;

  @override
  State<SuppliersPage> createState() => _SuppliersPageState();
}

class _SuppliersPageState extends State<SuppliersPage> {
  String query = '';
  Timer? _supplierRevealTimer;
  int _visibleSupplierCount = 100;
  int _supplierRevealTargetCount = 0;
  Future<_SupplierQueryResult?>? _supplierQueryFuture;
  String _supplierQueryFutureKey = '';
  final RevisionKeyCache<List<Supplier>> _filteredSuppliersCache =
      RevisionKeyCache<List<Supplier>>();

  @override
  void dispose() {
    _supplierRevealTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SuppliersPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      _supplierQueryFuture = null;
      _supplierQueryFutureKey = '';
      _filteredSuppliersCache.invalidate();
      _resetSupplierReveal();
    }
  }

  void _resetSupplierReveal() {
    _supplierRevealTimer?.cancel();
    _supplierRevealTimer = null;
    _visibleSupplierCount = 100;
    _supplierRevealTargetCount = 0;
  }

  void _syncSupplierReveal(int totalCount) {
    _supplierRevealTargetCount = totalCount;
    if (_visibleSupplierCount > totalCount) {
      _visibleSupplierCount = totalCount;
    }
    if (_visibleSupplierCount >= totalCount) {
      _supplierRevealTimer?.cancel();
      _supplierRevealTimer = null;
      return;
    }
    _supplierRevealTimer ??=
        Timer.periodic(const Duration(milliseconds: 20), (timer) {
      if (!mounted) {
        timer.cancel();
        _supplierRevealTimer = null;
        return;
      }
      if (_visibleSupplierCount >= _supplierRevealTargetCount) {
        timer.cancel();
        _supplierRevealTimer = null;
        return;
      }
      setState(() {
        _visibleSupplierCount = math.min(
          _supplierRevealTargetCount,
          _visibleSupplierCount + 100,
        );
      });
      if (_visibleSupplierCount >= _supplierRevealTargetCount) {
        timer.cancel();
        _supplierRevealTimer = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    if (!widget.store.canViewSuppliers) {
      return const _AccessDeniedScaffold(
        title: 'Suppliers',
        message: 'You do not have access to supplier records.',
      );
    }
    final value = query.trim().toLowerCase();
    if (LocalDatabaseService.canQueryBusinessSqlite) {
      return FutureBuilder<_SupplierQueryResult?>(
        future: _querySuppliersFromSqlite(value),
        builder: (context, snapshot) {
          final result = snapshot.data;
          if (result != null && !snapshot.hasError) {
            return _buildSuppliersView(
              context,
              tr,
              suppliers: result.items,
              totalCount: result.totalCount,
              loading: snapshot.connectionState == ConnectionState.waiting &&
                  result.items.isEmpty,
              onLoadMore: result.hasMore
                  ? () => _loadMoreSuppliers(result.totalCount)
                  : null,
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildSuppliersView(
              context,
              tr,
              suppliers: const <Supplier>[],
              totalCount: 0,
              loading: true,
            );
          }
          return _buildSuppliersFromMemory(context, tr, value);
        },
      );
    }
    return _buildSuppliersFromMemory(context, tr, value);
  }

  Widget _buildSuppliersFromMemory(
    BuildContext context,
    AppLocalizations tr,
    String value,
  ) {
    final suppliers = _filteredSuppliersCache.getOrCompute(
      widget.store.suppliersRevision,
      value,
      () => widget.store.suppliers.where((supplier) {
        return supplier.name.toLowerCase().contains(value) ||
            supplier.phone.toLowerCase().contains(value);
      }).toList(growable: false),
    );
    _syncSupplierReveal(suppliers.length);
    final visibleSuppliers = suppliers
        .take(math.min(_visibleSupplierCount, suppliers.length))
        .toList(
          growable: false,
        );
    return _buildSuppliersView(
      context,
      tr,
      suppliers: visibleSuppliers,
      totalCount: suppliers.length,
    );
  }

  Future<_SupplierQueryResult?> _querySuppliersFromSqlite(String value) {
    final limit = math.max(1, _visibleSupplierCount);
    final key = '${widget.store.suppliersRevision}|$value|$limit';
    if (_supplierQueryFuture == null || _supplierQueryFutureKey != key) {
      _supplierQueryFutureKey = key;
      _supplierQueryFuture = () async {
        final page = await LocalDatabaseService.querySuppliersFromSqlite(
          query: value,
          limit: limit,
        );
        if (page == null) return null;
        return _SupplierQueryResult(
          items: page.items,
          totalCount: page.totalCount,
        );
      }();
    }
    return _supplierQueryFuture!;
  }

  void _loadMoreSuppliers(int totalCount) {
    setState(() {
      _supplierRevealTimer?.cancel();
      _supplierRevealTimer = null;
      _visibleSupplierCount = math.min(totalCount, _visibleSupplierCount + 100);
    });
  }

  Widget _buildSuppliersView(
    BuildContext context,
    AppLocalizations tr, {
    required List<Supplier> suppliers,
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
            title: tr.text('suppliers'),
            subtitle: tr.text('suppliers_page_desc'),
            action: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                PageDataLoadIndicator(
                  loadedCount: suppliers.length,
                  totalCount: totalCount,
                ),
                FilledButton.icon(
                  onPressed: widget.store.canManageSuppliers
                      ? () => _openSupplierForm(context)
                      : null,
                  icon: const Icon(Icons.local_shipping_outlined),
                  label: Text(tr.text('add_supplier')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            decoration: InputDecoration(
                hintText: tr.text('search_supplier'),
                prefixIcon: const Icon(Icons.search)),
            onChanged: (value) => setState(() {
              query = value;
              _resetSupplierReveal();
            }),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator.adaptive())
                : totalCount == 0
                    ? EmptyStateCard(
                        icon: Icons.local_shipping_outlined,
                        title: tr.text('no_suppliers'),
                        subtitle: tr.text('no_suppliers_desc'))
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
                                  suppliers.length + (hasLoadMore ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (index >= suppliers.length) {
                                  return Center(
                                    child: TextButton.icon(
                                      onPressed: onLoadMore,
                                      icon: const Icon(Icons.expand_more),
                                      label: Text(
                                        '${tr.text('more')} '
                                        '(${suppliers.length}/$totalCount)',
                                      ),
                                    ),
                                  );
                                }
                                final supplier = suppliers[index];
                                return ListTile(
                                  leading: const CircleAvatar(
                                      child:
                                          Icon(Icons.local_shipping_outlined)),
                                  title: Text(supplier.name),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                          [
                                            supplier.phone,
                                            supplier.address,
                                            supplier.notes
                                          ]
                                              .where((e) => e.isNotEmpty)
                                              .join(' ? '),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                      const SizedBox(height: 4),
                                      Text(
                                        accountBalanceText(
                                            context,
                                            widget.store,
                                            'supplier',
                                            supplier.id),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            color: accountBalanceColor(
                                                context,
                                                widget.store,
                                                'supplier',
                                                supplier.id),
                                            fontWeight: FontWeight.w700),
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
                                                      .suppliersLedgerView,
                                                  AppPermission.suppliersManage,
                                                })) {
                                              showAccountLedgerSheet(
                                                  context: context,
                                                  store: widget.store,
                                                  accountType: 'supplier',
                                                  accountId: supplier.id,
                                                  accountName: supplier.name);
                                            }
                                            if (value == 'payment' &&
                                                widget.store
                                                    .hasAnyPermission(<String>{
                                                  AppPermission
                                                      .suppliersPaymentManage,
                                                  AppPermission.suppliersManage,
                                                })) {
                                              showAccountPaymentDialog(
                                                  context: context,
                                                  store: widget.store,
                                                  accountType: 'supplier',
                                                  accountId: supplier.id,
                                                  accountName: supplier.name);
                                            }
                                            if (value == 'edit' &&
                                                widget
                                                    .store.canManageSuppliers) {
                                              _openSupplierForm(context,
                                                  supplier: supplier);
                                            }
                                            if (value == 'delete' &&
                                                widget
                                                    .store.canManageSuppliers) {
                                              _deleteSupplier(
                                                  context, supplier);
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
                                                    tr.text('pay_supplier'))),
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
                                                      .suppliersLedgerView,
                                                  AppPermission.suppliersManage,
                                                })
                                                    ? () =>
                                                        showAccountLedgerSheet(
                                                            context: context,
                                                            store: widget.store,
                                                            accountType:
                                                                'supplier',
                                                            accountId:
                                                                supplier.id,
                                                            accountName:
                                                                supplier.name)
                                                    : null,
                                                icon: const Icon(Icons
                                                    .receipt_long_outlined),
                                                tooltip:
                                                    tr.text('account_ledger')),
                                            IconButton(
                                                onPressed: widget.store
                                                        .hasAnyPermission(<String>{
                                                  AppPermission
                                                      .suppliersPaymentManage,
                                                  AppPermission.suppliersManage,
                                                })
                                                    ? () =>
                                                        showAccountPaymentDialog(
                                                            context: context,
                                                            store: widget.store,
                                                            accountType:
                                                                'supplier',
                                                            accountId:
                                                                supplier.id,
                                                            accountName:
                                                                supplier.name)
                                                    : null,
                                                icon: const Icon(
                                                    Icons.payments_outlined),
                                                tooltip:
                                                    tr.text('pay_supplier')),
                                            IconButton(
                                                onPressed: widget.store
                                                        .canManageSuppliers
                                                    ? () => _openSupplierForm(
                                                        context,
                                                        supplier: supplier)
                                                    : null,
                                                icon: const Icon(
                                                    Icons.edit_outlined),
                                                tooltip: tr.text('edit')),
                                            IconButton(
                                                onPressed: widget.store
                                                        .canManageSuppliers
                                                    ? () => _deleteSupplier(
                                                        context, supplier)
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

  Future<void> _deleteSupplier(BuildContext context, Supplier supplier) async {
    if (!widget.store.canManageSuppliers) return;
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
    if (!widget.store.canManageSuppliers) return;
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

class _SupplierQueryResult {
  const _SupplierQueryResult({
    required this.items,
    required this.totalCount,
  });

  final List<Supplier> items;
  final int totalCount;

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
    final dialogWidth = VentioResponsive.modalMaxWidth(context, 640);
    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: VentioResponsive.pagePadding(context),
        vertical: 24,
      ),
      constraints: BoxConstraints(maxWidth: dialogWidth),
      title: Text(widget.supplier == null
          ? tr.text('add_supplier')
          : tr.text('edit_supplier')),
      content: SizedBox(
        width: dialogWidth,
        child: ResponsiveDialogBox(
          maxWidth: dialogWidth,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                      controller: nameEnController,
                      decoration:
                          InputDecoration(labelText: tr.text('name_en')),
                      validator: _required),
                  const SizedBox(height: 12),
                  TextFormField(
                      controller: nameArController,
                      decoration:
                          InputDecoration(labelText: tr.text('name_ar'))),
                  const SizedBox(height: 12),
                  TextFormField(
                      controller: phoneController,
                      decoration: InputDecoration(labelText: tr.text('phone'))),
                  const SizedBox(height: 12),
                  TextFormField(
                      controller: addressController,
                      decoration:
                          InputDecoration(labelText: tr.text('address'))),
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
