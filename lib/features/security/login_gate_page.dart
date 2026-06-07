import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/utils/responsive.dart';
import '../../core/sync_unified/sync_unified.dart';
import '../../data/app_store.dart';
import '../settings/sync_setup_page.dart';

class LoginGatePage extends StatefulWidget {
  const LoginGatePage({super.key, required this.store, required this.child});

  final AppStore store;
  final Widget child;

  @override
  State<LoginGatePage> createState() => _LoginGatePageState();
}

class _LoginGatePageState extends State<LoginGatePage> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _fullNameController =
      TextEditingController(text: 'Administrator');
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _savingSetup = false;
  bool _loggingIn = false;
  bool _rememberLogin = false;
  bool _showRegister = false;
  bool _showPassword = false;
  bool _checkingSuspension = false;

  @override
  void initState() {
    super.initState();
    _rememberLogin = widget.store.rememberLogin;
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _fullNameController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _checkSuspensionStatus() async {
    if (!widget.store.appIdentity.isClient) return;
    final tr = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _checkingSuspension = true);
    try {
      final identity = widget.store.appIdentity;
      final active = identity.activeSyncTransportNormalized;
      final result = active == 'cloud'
          ? await UnifiedSyncFactory.cloudEngine(widget.store).syncNow()
          : await UnifiedSyncFactory.lanEngine(widget.store).syncNow();
      if (!mounted) return;
      if (result.ok && !widget.store.isSuspendedByHost) {
        messenger.showSnackBar(SnackBar(content: Text(tr.text('client_resume_detected'))));
        setState(() {});
      } else {
        messenger.showSnackBar(SnackBar(content: Text(result.message.isEmpty ? tr.text('client_still_suspended') : result.message)));
      }
    } catch (error) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _checkingSuspension = false);
    }
  }

  Future<void> _unlock() async {
    final invalidLoginMessage = AppLocalizations.of(context).text('invalid_login');
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _loggingIn = true);
    final ok = await widget.store.login(
      _usernameController.text,
      _passwordController.text,
      remember: _rememberLogin,
    );

    if (!mounted) return;

    setState(() => _loggingIn = false);

    if (ok) {
      setState(() {});
    } else {
      _passwordController.clear();
      messenger.showSnackBar(SnackBar(content: Text(invalidLoginMessage)));
    }
  }

  Future<void> _completeInitialSetup() async {
    final password = _passwordController.text.trim();

    if (password != _confirmPasswordController.text.trim()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).text('passwords_do_not_match'))),
      );
      return;
    }

    setState(() => _savingSetup = true);

    try {
      await widget.store.completeInitialAdminSetup(
        fullName: _fullNameController.text,
        username: _usernameController.text,
        password: password,
      );

      await widget.store.logout();
      if (mounted) {
        setState(() {
          _showRegister = false;
          _passwordController.clear();
          _confirmPasswordController.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).text('admin_created_sign_in'))),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _savingSetup = false);
    }
  }

  // Returns true when the device has already completed pairing (has a valid
  // deviceToken) but the initial Host snapshot has not yet been applied to
  // local storage (users list is still empty). This state must be shown as a
  // "waiting for store data" screen, NOT as the first-time-setup login screen.
  bool get _isPairedButMissingStoreData {
    final identity = widget.store.appIdentity;
    return identity.isClient &&
        identity.deviceToken.trim().isNotEmpty &&
        widget.store.needsInitialAdminSetup;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.store.activeUser != null) return widget.child;

    // A paired-but-unprovisioned Client must never land on the first-time
    // admin-setup screen or see the "Connect to Store" button — the device is
    // already paired. Show a dedicated waiting/retry screen instead.
    if (_isPairedButMissingStoreData) {
      return _PairedWaitingForDataScreen(store: widget.store);
    }

    if (_showRegister && !kIsWeb && widget.store.needsInitialAdminSetup) {
      return _InitialAdminSetupCard(
        fullNameController: _fullNameController,
        usernameController: _usernameController,
        passwordController: _passwordController,
        confirmPasswordController: _confirmPasswordController,
        saving: _savingSetup,
        onSubmit: _completeInitialSetup,
        onCancel: _savingSetup ? null : () => setState(() => _showRegister = false),
      );
    }

    final tr = AppLocalizations.of(context);

    if (widget.store.isSuspendedByHost) {
      final reason = widget.store.suspendedByHostReason.trim().isEmpty
          ? tr.text('client_suspended_by_host_desc')
          : widget.store.suspendedByHostReason;
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: VentioResponsive.pageInsets(context),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: VentioResponsive.clampToScreen(context, 460, min: 280, horizontalPadding: 32)),
                child: Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: VentioResponsive.pageInsets(context),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircleAvatar(radius: 34, child: Icon(Icons.pause_circle_outline, size: 34)),
                        const SizedBox(height: 16),
                        Text(tr.text('client_suspended_by_host'), style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
                        const SizedBox(height: 8),
                        Text(reason, textAlign: TextAlign.center),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _checkingSuspension ? null : _checkSuspensionStatus,
                            icon: _checkingSuspension ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh),
                            label: Text(tr.text('check_resume_status')),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: VentioResponsive.pageInsets(context),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: VentioResponsive.clampToScreen(context, 420, min: 280, horizontalPadding: 32)),
              child: Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: VentioResponsive.pageInsets(context),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircleAvatar(
                        radius: 32,
                        child: Icon(Icons.lock_outline, size: 32),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        tr.text('ventio_login'),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(tr.text('signin_hint'), textAlign: TextAlign.center),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _usernameController,
                        enabled: !_loggingIn,
                        autofocus: true,
                        textInputAction: TextInputAction.next,
                        decoration:
                            InputDecoration(labelText: tr.text('username')),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _passwordController,
                        enabled: !_loggingIn,
                        obscureText: !_showPassword,
                        decoration: InputDecoration(
                          labelText: tr.text('password'),
                          suffixIcon: IconButton(
                            tooltip: _showPassword
                                ? tr.text('hide_password')
                                : tr.text('show_password'),
                            onPressed: _loggingIn
                                ? null
                                : () => setState(() => _showPassword = !_showPassword),
                            icon: Icon(_showPassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined),
                          ),
                        ),
                        onSubmitted: (_) {
                          if (!_loggingIn) _unlock();
                        },
                      ),
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _rememberLogin,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(tr.text('remember_me')),
                        subtitle: Text(tr.text('remember_me_desc')),
                        onChanged: _loggingIn ? null : (value) => setState(() => _rememberLogin = value ?? false),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _loggingIn ? null : _unlock,
                          icon: _loggingIn ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.login),
                          label: Text(tr.text('login')),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: TextButton(
                          onPressed: _loggingIn ? null : () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(tr.text('password_recovery_not_configured'))),
                            );
                          },
                          child: Text(tr.text('forgot_password')),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (widget.store.needsInitialAdminSetup)
                        Builder(
                          builder: (context) {
                            final canRegisterHere = !kIsWeb;
                            final actions = <Widget>[
                              if (canRegisterHere)
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _loggingIn
                                        ? null
                                        : () => setState(() => _showRegister = true),
                                    icon: const Icon(Icons.person_add_alt_1),
                                    label: Text(tr.text('register')),
                                  ),
                                ),
                              if (canRegisterHere) const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _loggingIn
                                      ? null
                                      : () async {
                                          await Navigator.of(context).push(
                                            MaterialPageRoute<void>(
                                              builder: (_) => SyncSetupPage(
                                                store: widget.store,
                                                onDone: () async {
                                                  // SyncSetupPage calls onDone when pairing is
                                                  // complete. We do NOT pop here because
                                                  // _finishSuccessfulConnection in SyncSetupPage
                                                  // has already removed itself from the stack via
                                                  // this callback. A setState() after the push()
                                                  // call below is all that is needed to re-evaluate
                                                  // the login gate condition.
                                                },
                                              ),
                                            ),
                                          );
                                          if (mounted) setState(() {});
                                        },
                                  icon: const Icon(Icons.link),
                                  label: Text(tr.text('connect_to_store')),
                                ),
                              ),
                            ];
                            return Row(children: actions);
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InitialAdminSetupCard extends StatefulWidget {
  const _InitialAdminSetupCard({
    required this.fullNameController,
    required this.usernameController,
    required this.passwordController,
    required this.confirmPasswordController,
    required this.saving,
    required this.onSubmit,
    required this.onCancel,
  });

  final TextEditingController fullNameController;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final TextEditingController confirmPasswordController;
  final bool saving;
  final VoidCallback onSubmit;
  final VoidCallback? onCancel;

  @override
  State<_InitialAdminSetupCard> createState() => _InitialAdminSetupCardState();
}

class _InitialAdminSetupCardState extends State<_InitialAdminSetupCard> {
  bool _showPassword = false;
  bool _showConfirmPassword = false;

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: VentioResponsive.pageInsets(context),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: VentioResponsive.clampToScreen(context, 460, min: 280, horizontalPadding: 32)),
              child: Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: VentioResponsive.pageInsets(context),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircleAvatar(
                        radius: 34,
                        child: Icon(Icons.verified_user_outlined, size: 34),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        tr.text('welcome_to_ventio'),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        tr.text('create_admin_desc'),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: widget.fullNameController,
                        enabled: !widget.saving,
                        textInputAction: TextInputAction.next,
                        decoration:
                            InputDecoration(labelText: tr.text('admin_name')),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: widget.usernameController,
                        enabled: !widget.saving,
                        autofocus: true,
                        textInputAction: TextInputAction.next,
                        decoration:
                            InputDecoration(labelText: tr.text('new_username')),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: widget.passwordController,
                        enabled: !widget.saving,
                        obscureText: !_showPassword,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: tr.text('new_password'),
                          suffixIcon: IconButton(
                            tooltip: _showPassword
                                ? tr.text('hide_password')
                                : tr.text('show_password'),
                            onPressed: widget.saving
                                ? null
                                : () => setState(() => _showPassword = !_showPassword),
                            icon: Icon(_showPassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: widget.confirmPasswordController,
                        enabled: !widget.saving,
                        obscureText: !_showConfirmPassword,
                        onSubmitted: (_) {
                          if (!widget.saving) widget.onSubmit();
                        },
                        decoration: InputDecoration(
                          labelText: tr.text('confirm_password'),
                          suffixIcon: IconButton(
                            tooltip: _showConfirmPassword
                                ? tr.text('hide_password')
                                : tr.text('show_password'),
                            onPressed: widget.saving
                                ? null
                                : () => setState(() => _showConfirmPassword = !_showConfirmPassword),
                            icon: Icon(_showConfirmPassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: widget.saving ? null : widget.onCancel,
                              child: Text(tr.text('back_to_login')),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: widget.saving ? null : widget.onSubmit,
                              icon: widget.saving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.check_circle_outline),
                              label: Text(tr.text('register_admin')),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown when this Client device has already paired (has a deviceToken) but
/// the Host snapshot has not yet arrived. The user can retry the download
/// without losing their pairing or being forced to re-enter the pairing code.
class _PairedWaitingForDataScreen extends StatefulWidget {
  const _PairedWaitingForDataScreen({required this.store});
  final AppStore store;

  @override
  State<_PairedWaitingForDataScreen> createState() =>
      _PairedWaitingForDataScreenState();
}

class _PairedWaitingForDataScreenState
    extends State<_PairedWaitingForDataScreen> {
  bool _retrying = false;
  String _statusMessage = '';
  bool _statusIsError = false;

  Future<void> _retryDownload() async {
    if (_retrying) return;
    setState(() {
      _retrying = true;
      _statusMessage = '';
      _statusIsError = false;
    });
    try {
      final identity = widget.store.appIdentity;
      final transport = identity.activeSyncTransportNormalized;
      final result = transport == 'cloud'
          ? await UnifiedSyncFactory.cloudEngine(widget.store).syncNow()
          : await UnifiedSyncFactory.lanEngine(widget.store).syncNow();
      if (!mounted) return;
      if (result.ok && !widget.store.needsInitialAdminSetup) {
        // Data arrived — rebuild triggers LoginGatePage to show login form.
        setState(() {});
      } else {
        setState(() {
          _statusMessage = result.message.trim().isNotEmpty
              ? result.message
              : AppLocalizations.of(context)
                  .text('device_connected_waiting_store_data');
          _statusIsError = !result.ok;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _statusMessage = error.toString();
          _statusIsError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final color = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: VentioResponsive.pageInsets(context),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: VentioResponsive.clampToScreen(context, 460,
                    min: 280, horizontalPadding: 32),
              ),
              child: Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: VentioResponsive.pageInsets(context),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 34,
                        backgroundColor: color.secondaryContainer,
                        child: Icon(Icons.cloud_download_outlined,
                            size: 34, color: color.onSecondaryContainer),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        tr.text('device_connected_waiting_store_data'),
                        style: Theme.of(context).textTheme.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        tr.text('pairing_state_refresh_failed'),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      if (_statusMessage.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _statusIsError
                                ? color.errorContainer
                                : color.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _statusMessage,
                            style: TextStyle(
                              color: _statusIsError
                                  ? color.onErrorContainer
                                  : color.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _retrying ? null : _retryDownload,
                          icon: _retrying
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : const Icon(Icons.refresh),
                          label: Text(tr.text('check_resume_status')),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}