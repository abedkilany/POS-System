import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/localization/app_localizations.dart';
import 'core/theme/app_theme.dart';
import 'core/services/lan_sync_service.dart';
import 'core/services/cloud_sync_service.dart';
import 'core/app_config.dart';
import 'data/app_store.dart';
import 'models/user_role.dart';
import 'models/app_user.dart';
import 'models/app_identity.dart';
import 'models/platform_store.dart';
import 'models/product.dart';
import 'models/online_order.dart';
import 'core/services/marketplace_api_service.dart';
import 'features/customers/customers_page.dart';
import 'features/dashboard/dashboard_page.dart';
import 'features/expenses/expenses_page.dart';
import 'features/inventory/inventory_page.dart';
import 'features/products/products_page.dart';
import 'features/platform/platform_page.dart';
import 'features/purchases/purchases_page.dart';
import 'features/reports/reports_page.dart';
import 'features/sales/sales_page.dart';
import 'features/security/pin_lock_page.dart';
import 'features/settings/settings_page.dart';
import 'features/suppliers/suppliers_page.dart';

class StoreManagerApp extends StatefulWidget {
  const StoreManagerApp({super.key});

  @override
  State<StoreManagerApp> createState() => _StoreManagerAppState();
}

class _StoreManagerAppState extends State<StoreManagerApp> {
  Locale _locale = const Locale('en');
  final AppStore _store = AppStore();
  late final AutoLanSyncController _autoSyncController = AutoLanSyncController(_store);
  late final AutoCloudSyncController _autoCloudSyncController = AutoCloudSyncController(_store);

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _store.initialize();
    await _autoSyncController.start();
    await _autoCloudSyncController.start();
  }

  @override
  void dispose() {
    _autoSyncController.stop();
    _autoCloudSyncController.stop();
    _store.dispose();
    super.dispose();
  }

  void _changeLocale(Locale locale) {
    setState(() => _locale = locale);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: _store.storeProfile.name,
          theme: AppTheme.lightTheme,
          locale: _locale,
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: _store.isReady
              ? PinLockPage(
                  store: _store,
                  onLocalConnectionDone: () async {
                    await _autoSyncController.start();
                    await _autoCloudSyncController.start();
                    if (mounted) setState(() {});
                  },
                  child: AccountRouter(
                    store: _store,
                    onLocaleChanged: _changeLocale,
                    onSyncSettingsChanged: () async {
                      await _autoSyncController.start();
                      await _autoCloudSyncController.start();
                    },
                  ),
                )
              : const Scaffold(body: Center(child: CircularProgressIndicator())),
        );
      },
    );
  }
}

class _ShellItem {
  const _ShellItem({required this.label, required this.icon, required this.selectedIcon, required this.page});

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget page;
}


class AccountRouter extends StatelessWidget {
  const AccountRouter({super.key, required this.store, required this.onLocaleChanged, this.onSyncSettingsChanged});

  final AppStore store;
  final ValueChanged<Locale> onLocaleChanged;
  final Future<void> Function()? onSyncSettingsChanged;

  @override
  Widget build(BuildContext context) {
    final user = store.activeUser;
    if (user == null) return const SizedBox.shrink();
    final hasStoreMembership = store.membershipsForActiveUser().isNotEmpty || user.primaryStoreId.trim().isNotEmpty;
    if (!hasStoreMembership && user.accountType != AccountType.appAdmin && user.accountType != AccountType.customer && user.accountType != AccountType.driver) {
      return AccountSetupHome(store: store);
    }
    if (user.accountType == AccountType.customer && !hasStoreMembership) return CustomerHomePage(store: store);
    if (user.accountType == AccountType.driver && !hasStoreMembership) return DriverHomePage(store: store);
    return MainShell(store: store, onLocaleChanged: onLocaleChanged, onSyncSettingsChanged: onSyncSettingsChanged);
  }
}


class AccountSetupHome extends StatefulWidget {
  const AccountSetupHome({super.key, required this.store});
  final AppStore store;

  @override
  State<AccountSetupHome> createState() => _AccountSetupHomeState();
}

class _AccountSetupHomeState extends State<AccountSetupHome> {
  final _storeNameController = TextEditingController();
  final _storePhoneController = TextEditingController();
  final _storeAddressController = TextEditingController();
  final _linkStoreIdController = TextEditingController();
  final _linkTokenController = TextEditingController();
  DeviceRole _deviceRole = DeviceRole.host;
  SyncMode _syncMode = SyncMode.lanOnly;
  bool _busy = false;

  @override
  void dispose() {
    _storeNameController.dispose();
    _storePhoneController.dispose();
    _storeAddressController.dispose();
    _linkStoreIdController.dispose();
    _linkTokenController.dispose();
    super.dispose();
  }

  Future<void> _createStore() async {
    setState(() => _busy = true);
    try {
      await widget.store.createStoreForActiveAccount(
        storeName: _storeNameController.text,
        phone: _storePhoneController.text,
        address: _storeAddressController.text,
        deviceRole: _deviceRole,
        syncMode: _syncMode,
      );
      if (!mounted) return;
      final token = widget.store.lastIssuedStoreToken;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(token.isEmpty ? 'تم إنشاء المتجر وربط هذا الجهاز.' : 'تم إنشاء المتجر. Store Token: $token')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _linkStore() async {
    setState(() => _busy = true);
    try {
      await widget.store.linkStoreForActiveAccount(
        storeId: _linkStoreIdController.text,
        storeToken: _linkTokenController.text,
        deviceRole: _deviceRole,
        syncMode: _syncMode,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم ربط المتجر بهذا الجهاز.')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.store.activeUser;
    return Scaffold(
      appBar: AppBar(title: const Text('إعداد حساب المنصة'), actions: [_LogoutButton(store: widget.store)]),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('مرحباً ${user?.fullName ?? ''}', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('حسابك على المنصة جاهز. الآن يمكنك إنشاء متجر جديد أو ربط هذا الجهاز بمتجر موجود باستخدام Store ID و Store Token.'),
          const SizedBox(height: 20),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              SizedBox(width: 420, child: _createStoreCard(context)),
              SizedBox(width: 420, child: _linkStoreCard(context)),
              SizedBox(width: 420, child: _deviceSyncCard(context)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _createStoreCard(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('إنشاء متجر جديد', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(controller: _storeNameController, decoration: const InputDecoration(labelText: 'اسم المتجر')),
            const SizedBox(height: 12),
            TextField(controller: _storePhoneController, decoration: const InputDecoration(labelText: 'هاتف المتجر اختياري')),
            const SizedBox(height: 12),
            TextField(controller: _storeAddressController, decoration: const InputDecoration(labelText: 'العنوان اختياري')),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _busy ? null : _createStore, icon: const Icon(Icons.add_business), label: Text(_busy ? '...' : 'إنشاء وربط'))),
            if (widget.store.lastIssuedStoreToken.isNotEmpty) ...[
              const SizedBox(height: 12),
              SelectableText('Store Token: ${widget.store.lastIssuedStoreToken}'),
              const Text('احفظ هذا التوكن لأنه يستخدم لربط الأجهزة الأخرى. يمكن لاحقاً تجديده من إعدادات المتجر.'),
            ],
          ]),
        ),
      );

  Widget _linkStoreCard(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('ربط متجر موجود', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(controller: _linkStoreIdController, decoration: const InputDecoration(labelText: 'Store ID')),
            const SizedBox(height: 12),
            TextField(controller: _linkTokenController, obscureText: true, decoration: const InputDecoration(labelText: 'Store Token')),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _busy ? null : _linkStore, icon: const Icon(Icons.link), label: Text(_busy ? '...' : 'ربط الجهاز'))),
          ]),
        ),
      );

  Widget _deviceSyncCard(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('إعدادات الجهاز والمزامنة', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            DropdownButtonFormField<DeviceRole>(
              value: _deviceRole,
              decoration: const InputDecoration(labelText: 'نوع الجهاز'),
              items: const [
                DropdownMenuItem(value: DeviceRole.host, child: Text('Host / الجهاز الرئيسي')),
                DropdownMenuItem(value: DeviceRole.client, child: Text('Client / جهاز إضافي')),
                DropdownMenuItem(value: DeviceRole.standalone, child: Text('Standalone / محلي فقط')),
              ],
              onChanged: (value) => setState(() => _deviceRole = value ?? DeviceRole.host),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<SyncMode>(
              value: _syncMode,
              decoration: const InputDecoration(labelText: 'نوع المزامنة'),
              items: const [
                DropdownMenuItem(value: SyncMode.localOnly, child: Text('Local only')),
                DropdownMenuItem(value: SyncMode.lanOnly, child: Text('LAN')),
                DropdownMenuItem(value: SyncMode.cloudConnected, child: Text('Online / Cloud')),
                DropdownMenuItem(value: SyncMode.marketplaceEnabled, child: Text('Hybrid / Marketplace')),
              ],
              onChanged: (value) => setState(() => _syncMode = value ?? SyncMode.lanOnly),
            ),
          ]),
        ),
      );
}

class CustomerHomePage extends StatefulWidget {
  const CustomerHomePage({super.key, required this.store});
  final AppStore store;

  @override
  State<CustomerHomePage> createState() => _CustomerHomePageState();
}

class _CustomerHomePageState extends State<CustomerHomePage> {
  final _api = MarketplaceApiService();
  final _searchController = TextEditingController();
  late Future<void> _loadFuture;
  List<PlatformStore> _stores = const [];
  List<OnlineOrder> _orders = const [];
  String _error = '';

  @override
  void initState() {
    super.initState();
    _loadFuture = _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final userId = widget.store.activeUser?.id ?? '';
      final results = await Future.wait<dynamic>([
        _api.fetchStores(),
        if (userId.isNotEmpty) _api.fetchCustomerOrders(userId) else Future.value(<OnlineOrder>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _stores = results[0] as List<PlatformStore>;
        _orders = results[1] as List<OnlineOrder>;
        _error = '';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  Future<void> _refresh() async {
    setState(() => _loadFuture = _load());
    await _loadFuture;
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.store.activeUser;
    final settings = CloudSyncSettings.load();
    final apiUrl = settings.apiBaseUrl.trim().isEmpty ? AppConfig.platformBaseUrl : settings.apiBaseUrl.trim();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Marketplace'),
        actions: [
          IconButton(tooltip: 'تحديث', icon: const Icon(Icons.refresh), onPressed: _refresh),
          IconButton(
            tooltip: 'الإعدادات',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerSettingsPage(store: widget.store))),
          ),
          _LogoutButton(store: widget.store),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<void>(
          future: _loadFuture,
          builder: (context, snapshot) {
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: LinearGradient(colors: [Theme.of(context).colorScheme.primaryContainer, Theme.of(context).colorScheme.surfaceContainerHighest]),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('أهلاً ${user?.fullName ?? ''}', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text('تصفح المتاجر والمنتجات المنشورة من السيرفر المحلي للـ Marketplace.'),
                    const SizedBox(height: 8),
                    Text('API: $apiUrl', style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _searchController,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: 'ابحث عن متجر...',
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.surface,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 20),
                Wrap(spacing: 12, runSpacing: 12, children: const [
                  _MarketplaceChip(icon: Icons.local_grocery_store_outlined, label: 'بقالة'),
                  _MarketplaceChip(icon: Icons.local_drink_outlined, label: 'مشروبات'),
                  _MarketplaceChip(icon: Icons.eco_outlined, label: 'خضار'),
                  _MarketplaceChip(icon: Icons.cleaning_services_outlined, label: 'منظفات'),
                  _MarketplaceChip(icon: Icons.local_offer_outlined, label: 'عروض'),
                ]),
                const SizedBox(height: 24),
                if (snapshot.connectionState == ConnectionState.waiting) const LinearProgressIndicator(),
                if (_error.isNotEmpty)
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('تعذر الاتصال بالـ Marketplace Server', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Text(_error),
                        const SizedBox(height: 12),
                        const Text('تأكد أن local-server شغال، وأن رابط Cloudflare محفوظ في إعدادات المزامنة.'),
                      ]),
                    ),
                  ),
                Row(children: [
                  Text('المتاجر المتاحة', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Text('${_filteredStores.length} متجر'),
                ]),
                const SizedBox(height: 12),
                if (_filteredStores.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Icon(Icons.storefront_outlined, size: 36),
                        const SizedBox(height: 12),
                        Text('لا توجد متاجر منشورة بعد', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 6),
                        const Text('عند مزامنة جهاز المتجر مع هذا السيرفر ستظهر المتاجر والمنتجات هنا.'),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(icon: const Icon(Icons.refresh), label: const Text('تحديث'), onPressed: _refresh),
                      ]),
                    ),
                  )
                else
                  for (final item in _filteredStores)
                    Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.storefront)),
                        title: Text(item.name),
                        subtitle: Text([item.address, item.phone, item.description].where((e) => e.trim().isNotEmpty).join(' • ')),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MarketplaceStorefrontPage(store: widget.store, marketplaceStore: item))).then((_) => _refresh()),
                      ),
                    ),
                const SizedBox(height: 24),
                Row(children: [
                  Text('طلباتي', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Text('${_orders.length} طلب'),
                ]),
                const SizedBox(height: 12),
                if (_orders.isEmpty)
                  const Card(child: ListTile(leading: Icon(Icons.shopping_bag_outlined), title: Text('لا توجد طلبات بعد'), subtitle: Text('أول طلب من صفحة المتجر سيظهر هنا.')))
                else
                  for (final order in _orders.take(8))
                    Card(child: ListTile(leading: const Icon(Icons.receipt_long_outlined), title: Text(order.customerName), subtitle: Text(order.status), trailing: Text(order.total.toStringAsFixed(2)))),
              ],
            );
          },
        ),
      ),
    );
  }

  List<PlatformStore> get _filteredStores {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return _stores;
    return _stores.where((s) => s.name.toLowerCase().contains(q) || s.address.toLowerCase().contains(q) || s.description.toLowerCase().contains(q)).toList();
  }
}

class MarketplaceStorefrontPage extends StatefulWidget {
  const MarketplaceStorefrontPage({super.key, required this.store, required this.marketplaceStore});
  final AppStore store;
  final PlatformStore marketplaceStore;

  @override
  State<MarketplaceStorefrontPage> createState() => _MarketplaceStorefrontPageState();
}

class _MarketplaceStorefrontPageState extends State<MarketplaceStorefrontPage> {
  final _api = MarketplaceApiService();
  final _addressController = TextEditingController();
  final _notesController = TextEditingController();
  late Future<void> _loadFuture;
  List<Product> _products = const [];
  final Map<String, int> _cart = <String, int>{};
  String _error = '';
  bool _placing = false;

  @override
  void initState() {
    super.initState();
    _loadFuture = _load();
  }

  @override
  void dispose() {
    _addressController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final products = await _api.fetchStoreProducts(widget.marketplaceStore.id);
      if (!mounted) return;
      setState(() {
        _products = products;
        _error = '';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  List<OnlineOrderItem> get _cartItems => _cart.entries.map((entry) {
        final product = _products.firstWhere((p) => p.id == entry.key);
        return OnlineOrderItem(productId: product.id, productName: product.name, unitPrice: product.price, quantity: entry.value);
      }).toList();

  double get _total => _cartItems.fold<double>(0, (sum, item) => sum + item.total);

  void _add(Product product) {
    setState(() => _cart[product.id] = (_cart[product.id] ?? 0) + 1);
  }

  void _remove(Product product) {
    setState(() {
      final next = (_cart[product.id] ?? 0) - 1;
      if (next <= 0) {
        _cart.remove(product.id);
      } else {
        _cart[product.id] = next;
      }
    });
  }

  Future<void> _placeOrder() async {
    if (_cart.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الطلب'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: _addressController, decoration: const InputDecoration(labelText: 'عنوان التوصيل')),
            TextField(controller: _notesController, decoration: const InputDecoration(labelText: 'ملاحظات اختيارية')),
            const SizedBox(height: 12),
            Text('الإجمالي: ${_total.toStringAsFixed(2)}'),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('إرسال الطلب')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _placing = true);
    try {
      final user = widget.store.activeUser;
      await _api.createOrder(
        storeId: widget.marketplaceStore.id,
        customerUserId: user?.id ?? '',
        customerName: user?.fullName ?? '',
        customerPhone: user?.phone ?? '',
        deliveryAddress: _addressController.text,
        notes: _notesController.text,
        items: _cartItems,
      );
      if (!mounted) return;
      setState(() => _cart.clear());
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إرسال الطلب إلى المتجر.')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.marketplaceStore.name)),
      body: FutureBuilder<void>(
        future: _loadFuture,
        builder: (context, snapshot) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.marketplaceStore.name, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                  if (widget.marketplaceStore.address.isNotEmpty) Text(widget.marketplaceStore.address),
                  if (widget.marketplaceStore.phone.isNotEmpty) Text(widget.marketplaceStore.phone),
                  if (widget.marketplaceStore.description.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(widget.marketplaceStore.description)),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            if (snapshot.connectionState == ConnectionState.waiting) const LinearProgressIndicator(),
            if (_error.isNotEmpty) Card(color: Theme.of(context).colorScheme.errorContainer, child: ListTile(leading: const Icon(Icons.error_outline), title: const Text('تعذر تحميل المنتجات'), subtitle: Text(_error))),
            if (_products.isEmpty && _error.isEmpty && snapshot.connectionState != ConnectionState.waiting)
              const Card(child: ListTile(leading: Icon(Icons.inventory_2_outlined), title: Text('لا توجد منتجات منشورة'), subtitle: Text('يجب أن يزامن جهاز المتجر منتجاته مع سيرفر الـ Marketplace.')))
            else
              for (final product in _products)
                Card(
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.shopping_basket_outlined)),
                    title: Text(product.name),
                    subtitle: Text('${product.category} • المتوفر: ${product.stock}'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(product.price.toStringAsFixed(2)),
                      IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: (_cart[product.id] ?? 0) > 0 ? () => _remove(product) : null),
                      Text('${_cart[product.id] ?? 0}'),
                      IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => _add(product)),
                    ]),
                  ),
                ),
            const SizedBox(height: 90),
          ],
        ),
      ),
      bottomNavigationBar: _cart.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  icon: _placing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.shopping_cart_checkout),
                  label: Text('إتمام الطلب • ${_total.toStringAsFixed(2)}'),
                  onPressed: _placing ? null : _placeOrder,
                ),
              ),
            ),
    );
  }
}

class _MarketplaceChip extends StatelessWidget {
  const _MarketplaceChip({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => ActionChip(avatar: Icon(icon, size: 18), label: Text(label), onPressed: () {});
}

class CustomerSettingsPage extends StatelessWidget {
  const CustomerSettingsPage({super.key, required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final user = store.activeUser;
    final hasStore = store.membershipsForActiveUser().isNotEmpty || (user?.primaryStoreId.trim().isNotEmpty ?? false);
    return Scaffold(
      appBar: AppBar(title: const Text('إعدادات الحساب')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('حسابي', style: Theme.of(context).textTheme.titleLarge),
                const Divider(),
                _CustomerInfoLine(title: 'الاسم', value: user?.fullName ?? '—'),
                _CustomerInfoLine(title: 'اسم المستخدم', value: user?.username ?? '—'),
                _CustomerInfoLine(title: 'الهاتف', value: (user?.phone ?? '').isEmpty ? '—' : user!.phone),
                _CustomerInfoLine(title: 'الإيميل', value: (user?.email ?? '').isEmpty ? '—' : user!.email),
                _CustomerInfoLine(title: 'الوضع الحالي', value: hasStore ? 'زبون + متجر' : 'زبون'),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.cloud_outlined),
              title: const Text('رابط سيرفر الـ Marketplace'),
              subtitle: Text(CloudSyncSettings.load().apiBaseUrl),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MarketplaceServerSettingsPage())),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.add_business_outlined),
              title: Text(hasStore ? 'إدارة المتجر المرتبط' : 'تفعيل وضع المتجر'),
              subtitle: const Text('أنشئ متجر جديد أو اربط حسابك بمتجر موجود. بعدها ستظهر لك لوحة إدارة المتجر.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AccountSetupHome(store: store))),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.delivery_dining_outlined),
              title: const Text('طلب تفعيل مندوب توصيل'),
              subtitle: const Text('محجوز للمرحلة التالية: حساب الزبون نفسه يمكن أن يطلب تفعيل وضع المندوب.'),
              trailing: const Icon(Icons.hourglass_empty),
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('سيتم تفعيل هذا الخيار لاحقاً.'))),
            ),
          ),
        ],
      ),
    );
  }
}


class MarketplaceServerSettingsPage extends StatefulWidget {
  const MarketplaceServerSettingsPage({super.key});

  @override
  State<MarketplaceServerSettingsPage> createState() => _MarketplaceServerSettingsPageState();
}

class _MarketplaceServerSettingsPageState extends State<MarketplaceServerSettingsPage> {
  final _urlController = TextEditingController();
  final _tokenController = TextEditingController();
  bool _testing = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    final settings = CloudSyncSettings.load();
    _urlController.text = settings.apiBaseUrl;
    _tokenController.text = settings.apiToken;
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final loaded = CloudSyncSettings.load();
    await loaded.copyWith(apiBaseUrl: _urlController.text.trim(), apiToken: _tokenController.text.trim(), enabled: true).save();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ رابط السيرفر.')));
    setState(() => _status = 'تم الحفظ. ارجع للـ Marketplace واضغط تحديث.');
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _status = '';
    });
    try {
      final loaded = CloudSyncSettings.load();
      final temp = loaded.copyWith(apiBaseUrl: _urlController.text.trim(), apiToken: _tokenController.text.trim(), enabled: true);
      final result = await CloudSyncService(AppStore()).testConnection(temp);
      if (!mounted) return;
      setState(() => _status = result.message);
    } catch (error) {
      if (mounted) setState(() => _status = error.toString());
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Marketplace Server')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('ضع هنا رابط Cloudflare Tunnel أو السيرفر المحلي. مثال: https://xxxxx.trycloudflare.com'),
          const SizedBox(height: 16),
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(labelText: 'Marketplace API URL', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tokenController,
            decoration: const InputDecoration(labelText: 'Token اختياري', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          Row(children: [
            FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save_outlined), label: const Text('حفظ')),
            const SizedBox(width: 12),
            OutlinedButton.icon(onPressed: _testing ? null : _test, icon: const Icon(Icons.wifi_tethering), label: const Text('اختبار /health')),
          ]),
          if (_testing) const Padding(padding: EdgeInsets.only(top: 16), child: LinearProgressIndicator()),
          if (_status.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 16), child: Text(_status)),
        ],
      ),
    );
  }
}


class _CustomerInfoLine extends StatelessWidget {
  const _CustomerInfoLine({required this.title, required this.value});
  final String title;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          SizedBox(width: 120, child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: Text(value, textAlign: TextAlign.end)),
        ]),
      );
}

class DriverHomePage extends StatelessWidget {
  const DriverHomePage({super.key, required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Delivery account'), actions: [_LogoutButton(store: store)]),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('مرحباً ${store.activeUser?.fullName ?? ''}', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('واجهة الدليفري محفوظة للمرحلة القادمة. حالياً الحساب يتسجل كدليفري ويستطيع النظام ربط الطلبات به لاحقاً.'),
          const SizedBox(height: 24),
          Card(child: ListTile(leading: const Icon(Icons.delivery_dining), title: const Text('طلبات جاهزة للتوصيل'), subtitle: Text('${store.pendingOnlineOrders.length} طلب بانتظار المعالجة/التوصيل'))),
        ],
      ),
    );
  }
}

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({required this.icon, required this.title, required this.value});
  final IconData icon;
  final String title;
  final String value;
  @override
  Widget build(BuildContext context) => SizedBox(width: 200, child: Card(child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [CircleAvatar(child: Icon(icon)), const SizedBox(width: 12), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title), Text(value, style: Theme.of(context).textTheme.titleLarge)])]))));
}

class _LogoutButton extends StatelessWidget {
  const _LogoutButton({required this.store});
  final AppStore store;
  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Logout',
        icon: const Icon(Icons.logout),
        onPressed: () async {
          await store.logout();
          if (context.mounted) Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => PinLockPage(store: store, child: AccountRouter(store: store, onLocaleChanged: (_) {}))));
        },
      );
}


class _PublishMarketplaceButton extends StatefulWidget {
  const _PublishMarketplaceButton({required this.store});
  final AppStore store;

  @override
  State<_PublishMarketplaceButton> createState() => _PublishMarketplaceButtonState();
}

class _PublishMarketplaceButtonState extends State<_PublishMarketplaceButton> {
  bool _busy = false;

  Future<void> _publish() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final identity = widget.store.appIdentity;
      final storeId = identity.storeId.trim().isEmpty ? 'store_${widget.store.deviceId}' : identity.storeId.trim();
      final branchId = identity.branchId.trim().isEmpty ? 'main' : identity.branchId.trim();
      final products = widget.store.products.where((p) => p.isActive && !p.isDeleted).toList();
      final api = MarketplaceApiService();
      final result = await api.publishStore(
        storeId: storeId,
        branchId: branchId,
        store: {
          ...widget.store.storeProfile.toJson(),
          'id': storeId,
          'storeId': storeId,
          'branchId': branchId,
          'description': widget.store.storeProfile.footerNote,
        },
        products: products,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم نشر المتجر على الـ Marketplace: ${result['publishedProducts'] ?? products.length} منتج')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل النشر: $error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'نشر المتجر للـ Marketplace',
      onPressed: _busy ? null : _publish,
      icon: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.cloud_upload_outlined),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.onLocaleChanged, required this.store, this.onSyncSettingsChanged});

  final ValueChanged<Locale> onLocaleChanged;
  final AppStore store;
  final Future<void> Function()? onSyncSettingsChanged;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final items = [
      _ShellItem(label: tr.text('dashboard'), icon: Icons.dashboard_outlined, selectedIcon: Icons.dashboard, page: DashboardPage(store: widget.store)),
      if (widget.store.hasPermission(AppPermission.productsCreate) || widget.store.hasPermission(AppPermission.productsEdit) || widget.store.hasPermission(AppPermission.productsDelete))
        _ShellItem(label: tr.text('products'), icon: Icons.inventory_2_outlined, selectedIcon: Icons.inventory_2, page: ProductsPage(store: widget.store)),
      if (widget.store.hasPermission(AppPermission.customersManage))
        _ShellItem(label: tr.text('customers'), icon: Icons.people_outline, selectedIcon: Icons.people, page: CustomersPage(store: widget.store)),
      if (widget.store.hasPermission(AppPermission.suppliersManage))
        _ShellItem(label: tr.text('suppliers'), icon: Icons.local_shipping_outlined, selectedIcon: Icons.local_shipping, page: SuppliersPage(store: widget.store)),
      if (widget.store.hasPermission(AppPermission.salesCreate) || widget.store.hasPermission(AppPermission.salesCancel))
        _ShellItem(label: tr.text('sales'), icon: Icons.receipt_long_outlined, selectedIcon: Icons.receipt_long, page: SalesPage(store: widget.store)),
      if (widget.store.hasPermission(AppPermission.suppliersManage))
        _ShellItem(label: tr.text('purchases'), icon: Icons.add_shopping_cart_outlined, selectedIcon: Icons.add_shopping_cart, page: PurchasesPage(store: widget.store)),
      if (widget.store.hasPermission(AppPermission.expensesManage))
        _ShellItem(label: tr.text('expenses'), icon: Icons.payments_outlined, selectedIcon: Icons.payments, page: ExpensesPage(store: widget.store)),
      _ShellItem(label: tr.text('inventory'), icon: Icons.warehouse_outlined, selectedIcon: Icons.warehouse, page: InventoryPage(store: widget.store)),
      if (widget.store.hasPermission(AppPermission.reportsView))
        _ShellItem(label: tr.text('reports'), icon: Icons.bar_chart_outlined, selectedIcon: Icons.bar_chart, page: ReportsPage(store: widget.store)),
      if (widget.store.hasPermission(AppPermission.platformManage) || widget.store.hasPermission(AppPermission.onlineOrdersView))
        _ShellItem(label: 'Platform', icon: Icons.hub_outlined, selectedIcon: Icons.hub, page: PlatformPage(store: widget.store)),
      _ShellItem(label: tr.text('settings'), icon: Icons.settings_outlined, selectedIcon: Icons.settings, page: SettingsPage(store: widget.store, onLocaleChanged: widget.onLocaleChanged, onSyncSettingsChanged: widget.onSyncSettingsChanged)),
    ];
    if (selectedIndex >= items.length) selectedIndex = items.length - 1;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1100;
        return Scaffold(
          appBar: AppBar(
            title: Text('${widget.store.storeProfile.name} • ${items[selectedIndex].label}'),
            actions: [
              HostConnectionIndicator(store: widget.store),
              _PublishMarketplaceButton(store: widget.store),
              if (constraints.maxWidth >= 520)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Center(child: Text(widget.store.activeUser?.fullName ?? '')),
                ),
              IconButton(
                tooltip: tr.text('logout'),
                onPressed: () async {
                  await widget.store.logout();
                  if (context.mounted) {
                    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => PinLockPage(store: widget.store, child: AccountRouter(store: widget.store, onLocaleChanged: widget.onLocaleChanged, onSyncSettingsChanged: widget.onSyncSettingsChanged))));
                  }
                },
                icon: const Icon(Icons.logout),
              ),
            ],
          ),
          drawer: isWide
              ? null
              : Drawer(
                  child: SafeArea(
                    child: ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return ListTile(
                          leading: Icon(index == selectedIndex ? item.selectedIcon : item.icon),
                          title: Text(item.label),
                          selected: index == selectedIndex,
                          onTap: () {
                            Navigator.pop(context);
                            setState(() => selectedIndex = index);
                          },
                        );
                      },
                    ),
                  ),
                ),
          body: isWide
              ? Row(
                  children: [
                    SizedBox(
                      width: 104,
                      child: Scrollbar(
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          child: NavigationRail(
                            selectedIndex: selectedIndex,
                            onDestinationSelected: (value) => setState(() => selectedIndex = value),
                            labelType: NavigationRailLabelType.all,
                            leading: const Padding(
                              padding: EdgeInsets.all(12),
                              child: CircleAvatar(radius: 24, child: Icon(Icons.storefront)),
                            ),
                            destinations: [
                              for (final item in items)
                                NavigationRailDestination(
                                  icon: Icon(item.icon),
                                  selectedIcon: Icon(item.selectedIcon),
                                  label: Text(item.label),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: items[selectedIndex].page),
                  ],
                )
              : items[selectedIndex].page,
        );
      },
    );
  }
}


enum _HostReachability { disabled, hostDevice, checking, connected, pending, disconnected, cloudOffline }

class HostConnectionIndicator extends StatefulWidget {
  const HostConnectionIndicator({super.key, required this.store});

  final AppStore store;

  @override
  State<HostConnectionIndicator> createState() => _HostConnectionIndicatorState();
}

class _HostConnectionIndicatorState extends State<HostConnectionIndicator> {
  Timer? _timer;
  _HostReachability _state = _HostReachability.checking;
  DateTime? _lastOk;
  String _message = '';

  String trText(String key) => AppLocalizations.of(context).text(key);

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (kIsWeb) {
      final settings = CloudSyncSettings.load();
      if (!settings.isConfigured || !widget.store.appIdentity.isCloudEnabled) {
        if (mounted) setState(() { _state = _HostReachability.disabled; _message = trText('cloud_off'); });
        return;
      }
      if (mounted) setState(() => _state = _HostReachability.checking);
      final status = await CloudSyncService(widget.store).getHostHeartbeatStatus(settings);
      final pending = widget.store.pendingSyncCount;
      if (!mounted) return;
      setState(() {
        if (!status.cloudReachable) {
          _state = _HostReachability.cloudOffline;
          _message = status.message;
        } else if (status.hostReachable) {
          _lastOk = status.lastSeenAt ?? DateTime.now();
          _state = pending > 0 ? _HostReachability.pending : _HostReachability.connected;
          _message = pending > 0 ? trText('pending_changes').replaceAll('{count}', '$pending') : trText('host_heartbeat_fresh');
        } else {
          _lastOk = status.lastSeenAt;
          _state = _HostReachability.disconnected;
          _message = status.lastSeenAt == null ? trText('no_host_heartbeat') : trText('host_heartbeat_stale');
        }
      });
      return;
    }

    final settings = LanSyncSettings.load();
    if (!settings.setupComplete) {
      if (mounted) setState(() { _state = _HostReachability.disabled; _message = trText('lan_not_configured'); });
      return;
    }
    if (settings.isHost) {
      if (mounted) setState(() { _state = _HostReachability.hostDevice; _message = trText('this_device_is_host'); });
      return;
    }
    if (mounted) setState(() => _state = _HostReachability.checking);
    final result = await LanSyncService(widget.store).testConnection(settings.host, port: settings.port, token: settings.secret);
    final pending = widget.store.pendingSyncCount;
    if (!mounted) return;
    setState(() {
      if (result.ok) {
        _lastOk = DateTime.now();
        _state = pending > 0 ? _HostReachability.pending : _HostReachability.connected;
        _message = pending > 0 ? trText('pending_changes').replaceAll('{count}', '$pending') : trText('host_reachable');
      } else {
        _state = _HostReachability.disconnected;
        _message = result.message;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final color = switch (_state) {
      _HostReachability.connected => Colors.green,
      _HostReachability.pending => Colors.orange,
      _HostReachability.disconnected => theme.colorScheme.error,
      _HostReachability.cloudOffline => theme.colorScheme.error,
      _HostReachability.hostDevice => Colors.blue,
      _HostReachability.checking => Colors.amber,
      _HostReachability.disabled => Colors.grey,
    };
    final label = switch (_state) {
      _HostReachability.connected => tr.text('host_connected'),
      _HostReachability.pending => tr.text('sync_pending'),
      _HostReachability.disconnected => tr.text('host_offline'),
      _HostReachability.cloudOffline => tr.text('cloud_offline'),
      _HostReachability.hostDevice => tr.text('host_device'),
      _HostReachability.checking => kIsWeb ? tr.text('checking_cloud') : tr.text('checking_host'),
      _HostReachability.disabled => kIsWeb ? tr.text('cloud_off') : tr.text('lan_off'),
    };
    final last = _lastOk == null ? '' : ' • ${tr.text(kIsWeb ? 'last_seen' : 'last_ok')} ${_lastOk!.toLocal().hour.toString().padLeft(2, '0')}:${_lastOk!.toLocal().minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: Tooltip(
        message: '${tr.text('host_status')}: $label$last\n$_message',
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: _refresh,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.14),
              border: Border.all(color: color.withOpacity(0.45)),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, color: color, size: 10),
                const SizedBox(width: 6),
                Text(label, style: theme.textTheme.labelMedium),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
