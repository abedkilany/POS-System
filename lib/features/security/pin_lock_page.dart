import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';
import '../../data/app_store.dart';

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
  bool _unlocked = false;

  @override
  void initState() {
    super.initState();
    _unlocked = widget.store.activeUser != null;
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    final tr = AppLocalizations.of(context);
    final ok = await widget.store.login(_usernameController.text, _passwordController.text);
    if (ok) {
      setState(() => _unlocked = true);
    } else {
      _passwordController.clear();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.text('wrong_pin'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked || widget.store.activeUser != null) return widget.child;

    final tr = AppLocalizations.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircleAvatar(radius: 32, child: Icon(Icons.lock_outline, size: 32)),
                  const SizedBox(height: 16),
                  Text('User Login', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  const Text('Sign in with your username and password. Default first login: admin / admin123', textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _usernameController,
                    autofocus: true,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Username'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Password'),
                    onSubmitted: (_) => _unlock(),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _unlock,
                      icon: const Icon(Icons.login),
                      label: const Text('Login'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
