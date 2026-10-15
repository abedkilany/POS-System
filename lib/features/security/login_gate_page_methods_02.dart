// ignore_for_file: invalid_use_of_protected_member
part of 'login_gate_page.dart';

extension _LoginGatePageStatePart2 on _LoginGatePageState {
  Future<void> _openSupportPasswordReset() async {
    final cache = _authCache ?? AccountAuthCache.load();
    final suggestedLogin = _usernameController.text.trim().contains('@')
        ? _usernameController.text.trim().toLowerCase()
        : (cache?.loginName.trim().isNotEmpty == true
            ? cache!.loginName.trim().toLowerCase()
            : _usernameController.text.trim().toLowerCase());
    final loginController = TextEditingController(text: suggestedLogin);
    final codeController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmController = TextEditingController();
    String? error;
    final draft = await showDialog<_PasswordResetDraft>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title:
              Text(AppLocalizations.of(context).text('password_reset_title')),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppLocalizations.of(context).text('password_reset_help'),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: loginController,
                  decoration: InputDecoration(
                    labelText:
                        AppLocalizations.of(context).text('account_login_name'),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: codeController,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context)
                        .text('password_reset_code'),
                  ),
                  textCapitalization: TextCapitalization.characters,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: newPasswordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context)
                        .text('account_new_password'),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: confirmController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context)
                        .text('account_confirm_new_password'),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(AppLocalizations.of(context).text('cancel')),
            ),
            FilledButton(
              onPressed: () {
                final loginName = loginController.text.trim().toLowerCase();
                final password = newPasswordController.text;
                if (!loginName.contains('@')) {
                  setDialogState(() => error = AppLocalizations.of(context)
                      .text('password_reset_login_required'));
                  return;
                }
                if (codeController.text.trim().isEmpty || password.length < 6) {
                  setDialogState(() => error = AppLocalizations.of(context)
                      .text('password_reset_fields_required'));
                  return;
                }
                if (password != confirmController.text) {
                  setDialogState(() => error = AppLocalizations.of(context)
                      .text('password_reset_passwords_do_not_match'));
                  return;
                }
                Navigator.of(dialogContext).pop(_PasswordResetDraft(
                  loginName: loginName,
                  code: codeController.text.trim().toUpperCase(),
                  password: password,
                ));
              },
              child: Text(
                  AppLocalizations.of(context).text('password_reset_submit')),
            ),
          ],
        ),
      ),
    );
    loginController.dispose();
    codeController.dispose();
    newPasswordController.dispose();
    if (draft == null || !mounted) return;
    setState(() => _loggingIn = true);
    try {
      final result = await AccountAuthService().confirmSupportPasswordReset(
        loginName: draft.loginName,
        resetCode: draft.code,
        newPassword: draft.password,
      );
      if (!mounted) return;
      if (!result.ok) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(result.message)));
        return;
      }
      final localUsername = draft.loginName.split('@').first;
      await widget.store.applySupportPasswordResetToLocalUser(
        username: localUsername,
        newPassword: draft.password,
      );
      if (!mounted) return;
      _usernameController.text = localUsername;
      _passwordController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                AppLocalizations.of(context).text('password_reset_success'))),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _loggingIn = false);
    }
  }

  Future<void> _completeInitialSetup() async {
    final password = _passwordController.text.trim();
    final username = _normalizeLoginPart(_usernameController.text);
    final storeName = _normalizeLoginPart(_storeNameController.text);

    if (!_isValidLoginPart(username)) {
      _showAuthMessage(
          'Username must be 3-32 characters: letters, numbers, underscore, or hyphen. No spaces.');
      return;
    }
    if (username.contains('@')) {
      _showAuthMessage(
          'Register with username only. Online login will become username@store.');
      return;
    }
    if (!_isValidLoginPart(storeName)) {
      _showAuthMessage(
          'Store name must be 3-32 characters: letters, numbers, underscore, or hyphen. No spaces.');
      return;
    }
    if (storeName == 'ventio') {
      _showAuthMessage(
          'ventio is reserved for platform accounts. Choose another store name.');
      return;
    }

    if (password != _confirmPasswordController.text.trim()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                AppLocalizations.of(context).text('passwords_do_not_match'))),
      );
      return;
    }

    final tr = AppLocalizations.of(context);
    setState(() => _savingSetup = true);

    try {
      final onlineResult = await AccountAuthService().register(
        username: username,
        password: password,
        fullName: 'Administrator',
        storeName: storeName,
      );
      if (!onlineResult.ok) {
        throw StateError(onlineResult.message.isEmpty
            ? tr.text('online_register_failed')
            : onlineResult.message);
      }
      final cached = await AccountAuthService.cacheOnlineResult(
        onlineResult,
        mode: 'registered_local',
      );
      _setAuthCache(cached);
      await widget.store.recoverOnlineStoreOwnerIdentity(
        storeId: onlineResult.storeId,
        branchId: onlineResult.branchId,
        storeName:
            onlineResult.storeName.isEmpty ? storeName : onlineResult.storeName,
        username: username,
        password: password,
        // Registration provisions the local owner account, but the user must
        // still sign in explicitly. Avoid publishing a short-lived session
        // that would briefly reveal the dashboard before logout completes.
        activateUser: false,
      );

      await widget.store.logout();
      if (mounted) {
        setState(() {
          _showRegister = false;
          _passwordController.clear();
          _confirmPasswordController.clear();
        });
        final message = tr.format('trial_created_sign_in', {
          'days': '14',
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
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

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    var size = bytes.toDouble();
    var unitIndex = 0;
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex += 1;
    }
    return '${size.toStringAsFixed(size >= 10 || unitIndex == 0 ? 0 : 1)} ${units[unitIndex]}';
  }

  String _formatDateTime(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(value.day)}/${two(value.month)}/${value.year} ${two(value.hour)}:${two(value.minute)}';
  }

  String _releaseSubtitle(AppLocalizations tr, WindowsReleaseItem item) {
    final parts = <String>[];
    if (item.version != null && item.version!.isNotEmpty) {
      final build = item.build == null ? '' : ' build ${item.build}';
      parts.add('${tr.text('version')}: ${item.version}$build');
    }
    final sizeBytes = item.sizeBytes;
    if (sizeBytes != null && sizeBytes > 0) parts.add(_formatBytes(sizeBytes));
    if (item.publishedAt != null) parts.add(_formatDateTime(item.publishedAt!));
    return parts.isEmpty ? item.name : parts.join(' • ');
  }

  Future<void> _showWindowsInstallerReleases() async {
    final tr = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(tr.text('windows_installer_versions')),
        content: const SizedBox(
          width: 360,
          child: Center(
            heightFactor: 1.5,
            child: CircularProgressIndicator(),
          ),
        ),
      ),
    );

    List<WindowsReleaseItem> releases;
    Object? error;
    try {
      releases = await WindowsReleaseCatalogService().fetchReleases();
    } catch (e) {
      releases = const <WindowsReleaseItem>[];
      error = e;
    }
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr.text('windows_installer_versions')),
        content: SizedBox(
          width: 520,
          child: releases.isEmpty
              ? Text(error == null
                  ? tr.text('no_windows_installers_found')
                  : tr.text('could_not_load_windows_installers'))
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 420),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: releases.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = releases[index];
                      return ListTile(
                        leading:
                            const Icon(Icons.download_for_offline_outlined),
                        title: Text(item.name),
                        subtitle: Text(_releaseSubtitle(tr, item)),
                        trailing: FilledButton.icon(
                          onPressed: () {
                            WindowsReleaseCatalogService().download(item);
                          },
                          icon: const Icon(Icons.download_outlined),
                          label: Text(tr.text('download')),
                        ),
                      );
                    },
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(tr.text('close')),
          ),
        ],
      ),
    );
  }
}
