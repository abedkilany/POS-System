import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';
import '../../data/app_store.dart';
import '../../models/app_user.dart';

class PinLockPage extends StatefulWidget {
  const PinLockPage({super.key, required this.store, required this.child, this.onLocalConnectionDone});

  final AppStore store;
  final Widget child;
  final Future<void> Function()? onLocalConnectionDone;

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
  final TextEditingController _localHostController = TextEditingController(text: '192.168.1.100');
  final TextEditingController _localPortController = TextEditingController(text: '8787');
  final TextEditingController _localStoreIdController = TextEditingController();
  final TextEditingController _localTokenController = TextEditingController();
  bool _unlocked = false;
  bool _signupMode = false;
  bool _localConnectMode = false;
  bool _busy = false;

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
    _localHostController.dispose();
    _localPortController.dispose();
    _localStoreIdController.dispose();
    _localTokenController.dispose();
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
        phone: _phoneController.text,
        email: _emailController.text,
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


  Future<void> _connectLocalStore() async {
    setState(() => _busy = true);
    try {
      await widget.store.connectLocalStoreWithoutPlatformAccount(
        hostIp: _localHostController.text,
        storeId: _localStoreIdController.text,
        storeToken: _localTokenController.text,
        port: int.tryParse(_localPortController.text.trim()) ?? 8787,
      );
      await widget.onLocalConnectionDone?.call();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _unlocked = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم الاتصال محلياً وربط الجهاز بالمتجر.')));
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
                child: _localConnectMode ? _localConnectionForm(context) : (_signupMode ? _signupForm(context) : _loginForm(context)),
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
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: [
            TextButton(
              onPressed: _busy ? null : () => setState(() { _signupMode = true; _localConnectMode = false; }),
              child: const Text('إنشاء حساب جديد'),
            ),
            TextButton.icon(
              onPressed: _busy ? null : () => setState(() { _localConnectMode = true; _signupMode = false; }),
              icon: const Icon(Icons.settings_ethernet, size: 18),
              label: const Text('اتصال بإعدادات داخلية'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _signupForm(BuildContext context) {
    return SingleChildScrollView(
      key: const ValueKey('signup'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircleAvatar(radius: 32, child: Icon(Icons.person_add_alt_1, size: 32)),
          const SizedBox(height: 16),
          Text('إنشاء حساب منصة', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('الحساب المركزي يحتاج فقط الاسم، اسم المستخدم، الهاتف/الإيميل، وكلمة المرور. نوع الاستخدام وإعدادات المتجر تتم لاحقاً من داخل الحساب.', textAlign: TextAlign.center),
          const SizedBox(height: 16),
          TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'الاسم الكامل')),
          const SizedBox(height: 12),
          TextField(controller: _signupUsernameController, decoration: const InputDecoration(labelText: 'اسم المستخدم')),
          const SizedBox(height: 12),
          TextField(controller: _phoneController, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الهاتف')),
          const SizedBox(height: 12),
          TextField(controller: _emailController, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email اختياري')),
          const SizedBox(height: 12),
          TextField(controller: _signupPasswordController, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _busy ? null : _signup, icon: const Icon(Icons.person_add_alt_1), label: Text(_busy ? '...' : 'إنشاء الحساب'))),
          TextButton(onPressed: _busy ? null : () => setState(() { _signupMode = false; _localConnectMode = false; }), child: const Text('لدي حساب سابق')),
        ],
      ),
    );
  }

  Widget _localConnectionForm(BuildContext context) {
    return SingleChildScrollView(
      key: const ValueKey('local_connection'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircleAvatar(radius: 32, child: Icon(Icons.lan_outlined, size: 32)),
          const SizedBox(height: 16),
          Text('اتصال محلي بمتجر موجود', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('استخدم هذا الخيار للأجهزة الداخلية بدون إنشاء حساب أونلاين. أدخل IP الهوست و Store ID و Store Token ثم تتم المزامنة من الجهاز الرئيسي.', textAlign: TextAlign.center),
          const SizedBox(height: 16),
          TextField(controller: _localHostController, decoration: const InputDecoration(labelText: 'Host IP', hintText: '192.168.1.100')),
          const SizedBox(height: 12),
          TextField(controller: _localPortController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Port', hintText: '8787')),
          const SizedBox(height: 12),
          TextField(controller: _localStoreIdController, decoration: const InputDecoration(labelText: 'Store ID')),
          const SizedBox(height: 12),
          TextField(controller: _localTokenController, obscureText: true, decoration: const InputDecoration(labelText: 'Store Token')),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy ? null : _connectLocalStore,
              icon: const Icon(Icons.sync),
              label: Text(_busy ? '...' : 'اتصال ومزامنة'),
            ),
          ),
          TextButton(
            onPressed: _busy ? null : () => setState(() { _localConnectMode = false; _signupMode = false; }),
            child: const Text('رجوع لتسجيل الدخول'),
          ),
        ],
      ),
    );
  }

}
