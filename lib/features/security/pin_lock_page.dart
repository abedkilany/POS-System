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
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _fullNameController = TextEditingController(text: 'Administrator');
  final TextEditingController _confirmPasswordController = TextEditingController();
  bool _unlocked = false;
  bool _savingSetup = false;

  @override
  void initState() {
    super.initState();
    _unlocked = widget.store.activeUser != null;
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _fullNameController.dispose();
    _confirmPasswordController.dispose();
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

  Future<void> _completeInitialSetup() async {
    final password = _passwordController.text.trim();
    if (password != _confirmPasswordController.text.trim()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Passwords do not match.')));
      return;
    }
    setState(() => _savingSetup = true);
    try {
      await widget.store.completeInitialAdminSetup(
        fullName: _fullNameController.text,
        username: _usernameController.text,
        password: password,
      );
      if (mounted) setState(() => _unlocked = true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _savingSetup = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked || widget.store.activeUser != null) return widget.child;

    if (widget.store.needsInitialAdminSetup) {
      return _InitialAdminSetupCard(
        fullNameController: _fullNameController,
        usernameController: _usernameController,
        passwordController: _passwordController,
        confirmPasswordController: _confirmPasswordController,
        saving: _savingSetup,
        onSubmit: _completeInitialSetup,
      );
    }

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
                  Text('Ventio Login', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(tr.text('signin_hint'), textAlign: TextAlign.center),
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
                      label: Text(tr.text('login')),
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

class _InitialAdminSetupCard extends StatelessWidget {
  const _InitialAdminSetupCard({
    required this.fullNameController,
    required this.usernameController,
    required this.passwordController,
    required this.confirmPasswordController,
    required this.saving,
    required this.onSubmit,
  });

  final TextEditingController fullNameController;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final TextEditingController confirmPasswordController;
  final bool saving;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircleAvatar(radius: 34, child: Icon(Icons.verified_user_outlined, size: 34)),
                  const SizedBox(height: 16),
                  Text('Welcome to Ventio', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  const Text(
                    'Create your private admin account before using the app. The default admin password will be removed.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: fullNameController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Admin name'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: usernameController,
                    autofocus: true,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'New username'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'New password'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmPasswordController,
                    obscureText: true,
                    onSubmitted: (_) => onSubmit(),
                    decoration: const InputDecoration(labelText: 'Confirm password'),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: saving ? null : onSubmit,
                      icon: saving
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.check_circle_outline),
                      label: const Text('Start using Ventio'),
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
