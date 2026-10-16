// ignore_for_file: curly_braces_in_flow_control_structures

import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/localization/localized_domain_exception.dart';
import '../../core/services/manufacturing_pdf_service.dart';

import 'package:ventio/core/contracts/application_session.dart';
import '../../models/manufacturing.dart';
import '../../models/inventory_batch.dart';
import '../../models/product.dart';
import '../../models/user_role.dart';
import 'batch_allocation_dialog.dart';
part 'manufacturing_page_methods_01.dart';
part 'manufacturing_page_methods_02.dart';
part 'manufacturing_page_methods_03.dart';

class ManufacturingPage extends StatefulWidget {
  const ManufacturingPage({super.key, required this.store});
  final ApplicationSession store;

  @override
  State<ManufacturingPage> createState() => _ManufacturingPageState();
}

class _ManufacturingPageState extends State<ManufacturingPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final Set<String> _selectedOrderIds = <String>{};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.store.security.hasPermission(
      AppPermission.inventoryManufacturingManage,
    )) {
      return _AccessDeniedScaffold(
        title: _t('manufacturing_orders'),
        message: _t('no_access_manufacturing_tools'),
      );
    }
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final query = _searchQuery.trim().toLowerCase();
        final boms = widget.store.inventory.billsOfMaterials.where((bom) {
          if (query.isEmpty) return true;
          return <String>[
            bom.name,
            bom.outputProductName,
            bom.notes,
            ...bom.components.map((item) => item.productName),
          ].any((value) => value.toLowerCase().contains(query));
        }).toList()
          ..sort((a, b) {
            final nameComparison = a.name.trim().toLowerCase().compareTo(
                  b.name.trim().toLowerCase(),
                );
            if (nameComparison != 0) return nameComparison;
            return a.id.compareTo(b.id);
          });
        final orders =
            widget.store.inventory.manufacturingOrders.where((order) {
          if (query.isEmpty) return true;
          return <String>[
            order.orderNo,
            order.bomName,
            order.outputProductName,
            order.status,
            order.rawMaterialsWarehouseName,
            order.finishedGoodsWarehouseName,
            order.notes,
          ].any((value) => value.toLowerCase().contains(query));
        }).toList(growable: false);

        return DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: Text(_t('manufacturing_page')),
              bottom: TabBar(
                tabs: [
                  Tab(
                    icon: const Icon(Icons.account_tree_outlined),
                    text: _t('bills_of_materials'),
                  ),
                  Tab(
                    icon: const Icon(Icons.precision_manufacturing_outlined),
                    text: _t('manufacturing_orders'),
                  ),
                ],
              ),
            ),
            body: Builder(
              builder: (tabContext) {
                final tabController = DefaultTabController.of(tabContext);
                return AnimatedBuilder(
                  animation: tabController,
                  builder: (context, _) {
                    final isRecipesTab = tabController.index == 0;
                    return Column(
                      children: [
                        if (isRecipesTab)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                            child: Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(0, 48),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 14,
                                  ),
                                ),
                                onPressed: widget.store.security.hasPermission(
                                  AppPermission.inventoryManufacturingManage,
                                )
                                    ? () => _showBomDialog()
                                    : null,
                                icon: const Icon(Icons.add),
                                label: Text(_t('new_bom')),
                              ),
                            ),
                          ),
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            16,
                            isRecipesTab ? 0 : 16,
                            16,
                            8,
                          ),
                          child: TextField(
                            controller: _searchController,
                            onChanged: (value) =>
                                setState(() => _searchQuery = value),
                            decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.search),
                              hintText: _localizedText(
                                ar: 'بحث في التصنيع',
                                en: 'Search manufacturing',
                                fr: 'Rechercher dans la fabrication',
                              ),
                              suffixIcon: _searchQuery.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: _localizedText(
                                        ar: 'مسح البحث',
                                        en: 'Clear search',
                                        fr: 'Effacer la recherche',
                                      ),
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() => _searchQuery = '');
                                      },
                                      icon: const Icon(Icons.clear),
                                    ),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                        Expanded(
                          child: TabBarView(
                            children: [
                              _buildRecipesTab(boms),
                              _buildOrdersTab(orders),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );
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

class _SummaryCard extends StatelessWidget {
  const _SummaryCard(
      {required this.title, required this.value, required this.icon});
  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title),
              Text(value, style: Theme.of(context).textTheme.headlineSmall)
            ])
          ],
        ),
      ),
    );
  }
}
