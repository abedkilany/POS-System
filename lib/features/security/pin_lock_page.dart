import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';
import '../../data/app_store.dart';
import '../../models/app_user.dart';

class PinLockPage extends StatefulWidget {
  const PinLockPage({super.key, required this.store, required this.child});

  final AppStore store;
  final Widget child;

  @override
  State<PinLockPage> createState() => _PinLockPageState();
}

class _PinLockPageState extends State<PinLockPage> {
  final TextEditingController _usernameController = TextEditingController(text: 'admin');
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _signupUsernameController = TextEditingController();
  final TextEditingController _signupPasswordController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _storeNameController = TextEditingController();
  bool _unlocked = false;
  bool _signupMode = false;
  bool _busy = false;
  String _accountType = AccountType.customer;

  @override
  void initState() {
    super.initState();
    _unlocked = widget.store.activeUser != null;
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _signupUsernameController.dispose();
    _signupPasswordController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _storeNameController.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    final tr = AppLocalizations.of(context);
    setState(() => _busy = true);
    final ok = await widget.store.login(_usernameController.text, _passwordController.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      setState(() => _unlocked = true);
    } else {
      _passwordController.clear();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.text('wrong_pin'))));
    }
  }

  Future<void> _signup() async {
    setState(() => _busy = true);
    try {
      await widget.store.registerAccount(
        fullName: _nameController.text,
        username: _signupUsernameController.text,
        password: _signupPasswordController.text,
        accountType: _accountType,
        phone: _phoneController.text,
        email: _emailController.text,
        storeName: _storeNameController.text,
      );
      await widget.store.login(_signupUsernameController.text, _signupPasswordController.text);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _unlocked = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked || widget.store.activeUser != null) return widget.child;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _signupMode ? _signupForm(context) : _loginForm(context),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _loginForm(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return Column(
      key: const ValueKey('login'),
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircleAvatar(radius: 32, child: Icon(Icons.lock_outline, size: 32)),
        const SizedBox(height: 16),
        Text('تسجيل الدخول', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text('ادخل بحسابك للانتقال تلقائياً إلى لوحة حسابك حسب نوع المستخدم.', textAlign: TextAlign.center),
        const SizedBox(height: 20),
        TextField(controller: _usernameController, autofocus: true, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'Username / phone')),
        const SizedBox(height: 12),
        TextField(controller: _passwordController, obscureText: true, decoration: const InputDecoration(labelText: 'Password'), onSubmitted: (_) => _unlock()),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _busy ? null : _unlock, icon: const Icon(Icons.login), label: Text(_busy ? '...' : tr.text('login')))),
        TextButton(onPressed: _busy ? null : () => setState(() => _signupMode = true), child: const Text('ليس لدي حساب، إنشاء حساب جديد')),
      ],
    );
  }

  Widget _signupForm(BuildContext context) {
    final isMerchant = _accountType == AccountType.merchant;
    return SingleChildScrollView(
      key: const ValueKey('signup'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircleAvatar(radius: 32, child: Icon(Icons.person_add_alt_1, size: 32)),
          const SizedBox(height: 16),
          Text('إنشاء حساب جديد', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('اختر نوع الاستخدام. حساب المشرف لا يتم إنشاؤه من التسجيل العام.', textAlign: TextAlign.center),
          const SizedBox(height: 16),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: AccountType.customer, label: Text('زبون'), icon: Icon(Icons.shopping_bag_outlined)),
              ButtonSegment(value: AccountType.merchant, label: Text('تاجر'), icon: Icon(Icons.storefront)),
              ButtonSegment(value: AccountType.driver, label: Text('دليفري'), icon: Icon(Icons.delivery_dining)),
            ],
            selected: {_accountType},
            onSelectionChanged: (value) => setState(() => _accountType = value.first),
          ),
          const SizedBox(height: 16),
          TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'الاسم الكامل')),
          const SizedBox(height: 12),
          TextField(controller: _signupUsernameController, decoration: const InputDecoration(labelText: 'Username / phone')),
          const SizedBox(height: 12),
          TextField(controller: _signupPasswordController, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
          const SizedBox(height: 12),
          TextField(controller: _phoneController, decoration: const InputDecoration(labelText: 'رقم الهاتف')),
          const SizedBox(height: 12),
          TextField(controller: _emailController, decoration: const InputDecoration(labelText: 'Email اختياري')),
          if (isMerchant) ...[
            const SizedBox(height: 12),
            TextField(controller: _storeNameController, decoration: const InputDecoration(labelText: 'اسم المتجر')),
          ],
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _busy ? null : _signup, icon: const Icon(Icons.person_add_alt_1), label: Text(_busy ? '...' : 'إنشاء الحساب'))),
          TextButton(onPressed: _busy ? null : () => setState(() => _signupMode = false), child: const Text('لدي حساب سابق')),
        ],
      ),
    );
  }
}
