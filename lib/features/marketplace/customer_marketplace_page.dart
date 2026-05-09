import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../models/online_order.dart';
import '../../models/platform_store.dart';
import '../../models/product.dart';

class CustomerMarketplacePage extends StatefulWidget {
  const CustomerMarketplacePage({super.key, required this.store});

  final AppStore store;

  @override
  State<CustomerMarketplacePage> createState() => _CustomerMarketplacePageState();
}

class _CustomerMarketplacePageState extends State<CustomerMarketplacePage> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _addressController = TextEditingController(text: 'البيت - حدّد العنوان عند الطلب');
  final Map<String, int> _cart = <String, int>{};
  String _selectedCategory = 'الكل';
  String _selectedStoreId = '';
  bool _placingOrder = false;

  @override
  void dispose() {
    _searchController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  List<PlatformStore> get _stores {
    final onlineStores = widget.store.platformStores.where((item) => item.isOnlineEnabled).toList();
    if (onlineStores.isNotEmpty) return onlineStores;
    if (widget.store.platformStores.isNotEmpty) return widget.store.platformStores;
    return <PlatformStore>[
      PlatformStore(
        id: 'local_store',
        name: widget.store.storeProfile.name,
        phone: widget.store.storeProfile.phone,
        address: widget.store.storeProfile.address,
        description: 'المتجر المحلي المرتبط بالتطبيق',
        isOnlineEnabled: true,
      ),
    ];
  }

  PlatformStore get _activeStore {
    final stores = _stores;
    if (_selectedStoreId.isEmpty) return stores.first;
    return stores.firstWhere((item) => item.id == _selectedStoreId, orElse: () => stores.first);
  }

  List<Product> get _visibleProducts {
    final query = _searchController.text.trim().toLowerCase();
    return widget.store.products.where((product) {
      if (!product.isActive) return false;
      if (product.trackStock && product.stock <= 0) return false;
      if (_selectedCategory != 'الكل' && product.category != _selectedCategory) return false;
      if (query.isEmpty) return true;
      return product.name.toLowerCase().contains(query) ||
          product.nameAr.toLowerCase().contains(query) ||
          product.nameEn.toLowerCase().contains(query) ||
          product.category.toLowerCase().contains(query) ||
          product.brand.toLowerCase().contains(query) ||
          product.barcode.toLowerCase().contains(query);
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  List<String> get _categories {
    final values = widget.store.products.map((item) => item.category.trim()).where((item) => item.isNotEmpty).toSet().toList()..sort();
    return <String>['الكل', ...values];
  }

  List<Product> get _cartProducts => widget.store.products.where((product) => _cart.containsKey(product.id)).toList();

  double get _subtotal => _cartProducts.fold<double>(0, (sum, product) => sum + (product.price * (_cart[product.id] ?? 0)));
  double get _deliveryFee => _cart.isEmpty ? 0 : 2.0;
  double get _total => _subtotal + _deliveryFee;

  void _addToCart(Product product) {
    setState(() => _cart[product.id] = (_cart[product.id] ?? 0) + 1);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تمت إضافة ${product.name} إلى السلة')));
  }

  void _changeQty(Product product, int delta) {
    final next = (_cart[product.id] ?? 0) + delta;
    setState(() {
      if (next <= 0) {
        _cart.remove(product.id);
      } else {
        _cart[product.id] = next;
      }
    });
  }

  Future<void> _checkout() async {
    if (_cart.isEmpty || _placingOrder) return;
    setState(() => _placingOrder = true);
    try {
      final now = DateTime.now();
      final order = OnlineOrder(
        id: 'market_order_${now.microsecondsSinceEpoch}',
        storeId: _activeStore.id,
        customerUserId: widget.store.activeUser?.id ?? 'guest_customer',
        customerName: widget.store.activeUser?.fullName ?? 'Customer',
        customerPhone: widget.store.activeUser?.phone ?? '',
        deliveryAddress: _addressController.text.trim().isEmpty ? 'عنوان غير محدد' : _addressController.text.trim(),
        notes: 'Created from Customer Marketplace Layer',
        status: OnlineOrderStatus.placed,
        deliveryFee: _deliveryFee,
        paymentMethod: 'cash_on_delivery',
        paymentStatus: 'unpaid',
        items: _cartProducts.map((product) => OnlineOrderItem(
          productId: product.id,
          productName: product.name,
          unitPrice: product.price,
          quantity: _cart[product.id] ?? 0,
        )).where((item) => item.quantity > 0).toList(),
        createdAt: now,
        updatedAt: now,
      );
      await widget.store.placeCustomerOnlineOrder(order);
      if (!mounted) return;
      setState(() => _cart.clear());
      Navigator.of(context).maybePop();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إرسال الطلب للمتجر بنجاح')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _placingOrder = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final orders = widget.store.onlineOrders.where((order) => order.customerUserId == widget.store.activeUser?.id).toList();
        return Scaffold(
          appBar: AppBar(
            title: const Text('Marketplace'),
            actions: [
              IconButton(onPressed: _openOrders, icon: Badge.count(count: orders.length, child: const Icon(Icons.receipt_long))),
              IconButton(onPressed: () => widget.store.logout(), icon: const Icon(Icons.logout)),
            ],
          ),
          body: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildHero(context)),
              SliverToBoxAdapter(child: _buildStores(context)),
              SliverToBoxAdapter(child: _buildCategories(context)),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                sliver: _visibleProducts.isEmpty ? const SliverToBoxAdapter(child: _EmptyMarketplaceState()) : SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 260,
                    childAspectRatio: .78,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: _visibleProducts.length,
                  itemBuilder: (context, index) => _ProductCard(
                    product: _visibleProducts[index],
                    quantity: _cart[_visibleProducts[index].id] ?? 0,
                    onAdd: () => _addToCart(_visibleProducts[index]),
                    onMinus: () => _changeQty(_visibleProducts[index], -1),
                    onPlus: () => _changeQty(_visibleProducts[index], 1),
                  ),
                ),
              ),
            ],
          ),
          bottomNavigationBar: _cart.isEmpty ? null : SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton.icon(
                onPressed: _openCart,
                icon: const Icon(Icons.shopping_cart_checkout),
                label: Text('عرض السلة • ${_cart.values.fold<int>(0, (sum, qty) => sum + qty)} منتجات • ${_total.toStringAsFixed(2)} ${widget.store.storeProfile.currency}'),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHero(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(24)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('أهلاً ${widget.store.activeUser?.fullName ?? ''}', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        const Text('اطلب أغراضك من أقرب متجر وخلّي الطلب يوصلك للبيت.'),
        const SizedBox(height: 16),
        TextField(
          controller: _addressController,
          decoration: const InputDecoration(prefixIcon: Icon(Icons.location_on_outlined), labelText: 'عنوان التوصيل', filled: true),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _searchController,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'ابحث عن منتج أو تصنيف أو باركود', filled: true),
        ),
      ]),
    );
  }

  Widget _buildStores(BuildContext context) {
    return SizedBox(
      height: 138,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) {
          final store = _stores[index];
          final selected = store.id == _activeStore.id;
          return InkWell(
            onTap: () => setState(() => _selectedStoreId = store.id),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: 260,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: selected ? Theme.of(context).colorScheme.primary : Theme.of(context).dividerColor),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  CircleAvatar(child: Text(store.name.isEmpty ? 'S' : store.name.substring(0, 1))),
                  const SizedBox(width: 10),
                  Expanded(child: Text(store.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold))),
                ]),
                const SizedBox(height: 8),
                Text(store.address.isEmpty ? 'قريب منك' : store.address, maxLines: 1, overflow: TextOverflow.ellipsis),
                const Spacer(),
                const Row(children: [Icon(Icons.bolt, size: 16), SizedBox(width: 4), Text('30-45 دقيقة'), SizedBox(width: 12), Icon(Icons.star, size: 16), SizedBox(width: 4), Text('4.7')]),
              ]),
            ),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemCount: _stores.length,
      ),
    );
  }

  Widget _buildCategories(BuildContext context) {
    return SizedBox(
      height: 58,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) {
          final category = _categories[index];
          return ChoiceChip(label: Text(category), selected: category == _selectedCategory, onSelected: (_) => setState(() => _selectedCategory = category));
        },
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemCount: _categories.length,
      ),
    );
  }

  void _openCart() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(builder: (context, modalSetState) {
        void updateQty(Product product, int delta) {
          _changeQty(product, delta);
          modalSetState(() {});
        }
        return Padding(
          padding: EdgeInsets.only(left: 16, right: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('سلة الطلب', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('المتجر: ${_activeStore.name}'),
            const Divider(),
            for (final product in _cartProducts)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(product.name),
                subtitle: Text('${product.price.toStringAsFixed(2)} ${widget.store.storeProfile.currency}'),
                trailing: _QtyControl(quantity: _cart[product.id] ?? 0, onMinus: () => updateQty(product, -1), onPlus: () => updateQty(product, 1)),
              ),
            const Divider(),
            _TotalRow(label: 'المجموع', value: _subtotal),
            _TotalRow(label: 'التوصيل', value: _deliveryFee),
            _TotalRow(label: 'الإجمالي', value: _total, bold: true),
            const SizedBox(height: 12),
            TextField(controller: _addressController, decoration: const InputDecoration(labelText: 'عنوان التوصيل', prefixIcon: Icon(Icons.location_on_outlined))),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _placingOrder ? null : _checkout, icon: const Icon(Icons.check_circle), label: Text(_placingOrder ? 'جاري إرسال الطلب...' : 'تأكيد الطلب - دفع عند الاستلام'))),
          ]),
        );
      }),
    );
  }

  void _openOrders() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final orders = widget.store.onlineOrders.where((order) => order.customerUserId == widget.store.activeUser?.id).toList();
        return ListView(padding: const EdgeInsets.all(16), children: [
          Text('طلباتي', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          if (orders.isEmpty) const ListTile(leading: Icon(Icons.receipt_long), title: Text('لا يوجد طلبات بعد.')),
          for (final order in orders)
            Card(child: ListTile(
              leading: const Icon(Icons.shopping_bag_outlined),
              title: Text('${order.total.toStringAsFixed(2)} ${widget.store.storeProfile.currency}'),
              subtitle: Text('${_statusLabel(order.status)}\n${order.deliveryAddress}', maxLines: 2),
              trailing: Text(order.items.length.toString()),
            )),
        ]);
      },
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case OnlineOrderStatus.placed:
        return 'تم إرسال الطلب';
      case OnlineOrderStatus.accepted:
        return 'تم قبول الطلب';
      case OnlineOrderStatus.preparing:
        return 'قيد التحضير';
      case OnlineOrderStatus.readyForDelivery:
        return 'جاهز للتوصيل';
      case OnlineOrderStatus.assignedToDriver:
        return 'تم تعيين مندوب';
      case OnlineOrderStatus.outForDelivery:
        return 'في الطريق';
      case OnlineOrderStatus.delivered:
        return 'تم التسليم';
      case OnlineOrderStatus.cancelled:
        return 'ملغي';
      default:
        return status;
    }
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product, required this.quantity, required this.onAdd, required this.onMinus, required this.onPlus});
  final Product product;
  final int quantity;
  final VoidCallback onAdd;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Container(width: double.infinity, decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceVariant, borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.local_grocery_store, size: 48))),
          const SizedBox(height: 10),
          Text(product.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(product.category, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: Text(product.price.toStringAsFixed(2), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
            quantity == 0 ? IconButton.filled(onPressed: onAdd, icon: const Icon(Icons.add)) : _QtyControl(quantity: quantity, onMinus: onMinus, onPlus: onPlus),
          ]),
        ]),
      ),
    );
  }
}

class _QtyControl extends StatelessWidget {
  const _QtyControl({required this.quantity, required this.onMinus, required this.onPlus});
  final int quantity;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(onPressed: onMinus, icon: const Icon(Icons.remove_circle_outline)),
        Text(quantity.toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
        IconButton(onPressed: onPlus, icon: const Icon(Icons.add_circle_outline)),
      ]);
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.label, required this.value, this.bold = false});
  final String label;
  final double value;
  final bool bold;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          Text(value.toStringAsFixed(2), style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
        ]),
      );
}

class _EmptyMarketplaceState extends StatelessWidget {
  const _EmptyMarketplaceState();
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: const [
            Icon(Icons.search_off, size: 42),
            SizedBox(height: 12),
            Text('لا يوجد منتجات مطابقة حالياً.'),
          ]),
        ),
      );
}
