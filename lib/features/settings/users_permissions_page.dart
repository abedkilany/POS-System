
import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/utils/responsive.dart';
import '../../core/services/account_auth_service.dart';
import '../../data/app_store.dart';
import '../../models/app_user.dart';
import '../../models/user_role.dart';

class UsersPermissionsPage extends StatefulWidget {
  const UsersPermissionsPage({super.key, required this.store});

  final AppStore store;

  @override
  State<UsersPermissionsPage> createState() => _UsersPermissionsPageState();
}

class _UsersPermissionsPageState extends State<UsersPermissionsPage> {
  @override
  Widget build(BuildContext context) {
    final tr = AppLocalizations.of(context);
    final store = widget.store;
    return Scaffold(
      appBar: AppBar(title: Text(tr.text('users_permissions'))),
      body: ListView(
        padding: VentioResponsive.pageInsets(context),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.admin_panel_settings_outlined),
              title: Text(tr.text('built_in_admin')),
              subtitle: Text(tr.text('built_in_admin_desc')),
            ),
          ),
          const SizedBox(height: 12),
          _SectionHeader(
            title: tr.text('roles'),
            action: FilledButton.icon(
              onPressed: () => _editRole(),
              icon: const Icon(Icons.add),
              label: Text(tr.text('add_role')),
            ),
          ),
          for (final role in store.roles)
            Card(
              child: ListTile(
                leading: Icon(role.isSystem ? Icons.lock_outline : Icons.badge_outlined),
                title: Text(role.name),
                subtitle: Text(role.isAdmin ? tr.text('all_permissions') : '${role.permissions.length} permissions'),
                trailing: role.isSystem
                    ? null
                    : Wrap(
                        spacing: 8,
                        children: [
                          IconButton(onPressed: () => _editRole(role: role), icon: const Icon(Icons.edit_outlined), tooltip: tr.text('edit')),
                          IconButton(onPressed: () => _deleteRole(role), icon: const Icon(Icons.delete_outline), tooltip: tr.text('delete')),
                        ],
                      ),
              ),
            ),
          const SizedBox(height: 20),
          _SectionHeader(
            title: tr.text('users'),
            action: FilledButton.icon(
              onPressed: store.roles.isEmpty ? null : () => _editUser(),
              icon: const Icon(Icons.person_add_alt),
              label: Text(tr.text('add_user')),
            ),
          ),
          for (final user in store.users)
            Card(
              child: ListTile(
                leading: CircleAvatar(child: Text(user.fullName.isEmpty ? '?' : user.fullName.substring(0, 1).toUpperCase())),
                title: Text('${user.fullName} (${user.username})'),
                subtitle: Text(user.isSystem && user.roleId == 'admin'
                    ? '${store.roleById(user.roleId)?.name ?? user.roleId} • Store Owner • Full Access locked'
                    : '${store.roleById(user.roleId)?.name ?? user.roleId} • ${user.isActive ? tr.text('active') : tr.text('disabled')}'),
                trailing: Wrap(
                  spacing: 8,
                  children: [
                    IconButton(onPressed: () => _editUser(user: user), icon: const Icon(Icons.edit_outlined), tooltip: tr.text('edit')),
                    if (!user.isSystem)
                      IconButton(onPressed: () => _deleteUser(user), icon: const Icon(Icons.delete_outline), tooltip: tr.text('delete')),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }


  String _friendlyErrorMessage(Object error) {
    final raw = error.toString().trim();
    var message = raw;
    const prefixes = <String>[
      'Bad state: ',
      'Exception: ',
      'Invalid argument(s): ',
    ];
    for (final prefix in prefixes) {
      if (message.startsWith(prefix)) {
        message = message.substring(prefix.length).trim();
      }
    }
    if (message.contains('Cloud owner re-authentication required') ||
        message.contains('Connect to the cloud account before editing') ||
        message.contains('Online account session is missing')) {
      return 'يجب تأكيد الحساب السحابي قبل تعديل المدير الأساسي.';
    }
    if (message.contains('Cloud rejected the Store Owner update')) {
      return 'فشل تحديث المدير الأساسي على السحابة. لم يتم حفظ أي تعديل محلي.';
    }
    if (message.contains('Store Owner must always keep Full Access')) {
      return 'المدير الأساسي يجب أن يبقى بصلاحيات كاملة ولا يمكن تعطيله.';
    }
    if (message.contains('Store Owner permissions are locked')) {
      return 'صلاحيات المدير الأساسي مقفلة ولا يمكن تعديلها.';
    }
    return message.isEmpty ? 'حدث خطأ أثناء حفظ المستخدم.' : message;
  }

  Future<void> _editRole({UserRole? role}) async {
    final tr = AppLocalizations.of(context);
    final nameController = TextEditingController(text: role?.name ?? '');
    final permissions = Set<String>.from(role?.permissions ?? const <String>{});
    final dialogWidth = VentioResponsive.modalMaxWidth(context, 820);

    final result = await showDialog<UserRole>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          insetPadding: EdgeInsets.symmetric(
            horizontal: VentioResponsive.pagePadding(context),
            vertical: 24,
          ),
          constraints: BoxConstraints(maxWidth: dialogWidth),
          title: Text(role == null ? tr.text('add_role') : tr.text('edit_role')),
          content: SizedBox(
            width: dialogWidth,
            child: ResponsiveDialogBox(
              maxWidth: dialogWidth,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    TextField(controller: nameController, decoration: InputDecoration(labelText: tr.text('role_name'))),
                    const SizedBox(height: 16),
                    for (final permission in AppPermission.all)
                      CheckboxListTile(
                        value: permissions.contains(permission),
                        title: Text(AppPermission.labels[permission] ?? permission),
                        subtitle: Text(permission),
                        onChanged: (value) {
                          setDialogState(() {
                            if (value == true) {
                              permissions.add(permission);
                            } else {
                              permissions.remove(permission);
                            }
                          });
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(tr.text('cancel'))),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  UserRole(
                    id: role?.id ?? '',
                    name: nameController.text,
                    permissions: permissions,
                    createdAt: role?.createdAt,
                    updatedAt: role?.updatedAt,
                  ),
                );
              },
              child: Text(tr.text('save')),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    try {
      await widget.store.addOrUpdateRole(result);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_friendlyErrorMessage(e))),
        );
      }
    }
  }

  Future<void> _deleteRole(UserRole role) async {
    final tr = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr.text('confirm_delete')),
        content: Text('${tr.text('delete_confirm_message')} ${role.name}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(tr.text('cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: Text(tr.text('delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.store.deleteRole(role.id);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_friendlyErrorMessage(e))),
        );
      }
    }
  }

  Future<void> _editUser({AppUser? user}) async {
    final tr = AppLocalizations.of(context);
    final isStoreOwner = user?.isSystem == true && user?.roleId == 'admin';
    final nameController = TextEditingController(text: user?.fullName ?? '');
    final usernameController = TextEditingController(text: user?.username ?? '');
    final passwordController = TextEditingController();
    String roleId = user?.roleId ?? widget.store.roles.first.id;
    bool isActive = user?.isActive ?? true;
    final extra = Set<String>.from(user?.extraPermissions ?? const <String>{});
    final denied = Set<String>.from(user?.deniedPermissions ?? const <String>{});
    final dialogWidth = VentioResponsive.modalMaxWidth(context, 900);

    final result = await showDialog<_UserEditResult>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          insetPadding: EdgeInsets.symmetric(
            horizontal: VentioResponsive.pagePadding(context),
            vertical: 24,
          ),
          constraints: BoxConstraints(maxWidth: dialogWidth),
          title: Text(user == null ? tr.text('add_user') : tr.text('edit_user')),
          content: SizedBox(
            width: dialogWidth,
            child: ResponsiveDialogBox(
              maxWidth: dialogWidth,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    TextField(controller: nameController, decoration: InputDecoration(labelText: tr.text('full_name'))),
                    const SizedBox(height: 12),
                    TextField(controller: usernameController, decoration: InputDecoration(labelText: tr.text('username'))),
                    const SizedBox(height: 12),
                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      decoration: InputDecoration(labelText: user == null ? tr.text('password') : tr.text('new_password_keep_current')),
                    ),
                    const SizedBox(height: 12),
                    if (isStoreOwner)
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.lock_outline),
                          title: Text(tr.text('store_owner_protected_account')),
                          subtitle: Text(tr.text('store_owner_protected_account_desc')),
                        ),
                      ),
                    if (isStoreOwner) const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: roleId,
                      decoration: InputDecoration(labelText: tr.text('role')),
                      items: [
                        for (final role in widget.store.roles) DropdownMenuItem(value: role.id, child: Text(role.name)),
                      ],
                      onChanged: isStoreOwner ? null : (value) => setDialogState(() => roleId = value ?? roleId),
                    ),
                    SwitchListTile(
                      value: isActive,
                      title: Text(tr.text('active')),
                      onChanged: user?.isSystem == true ? null : (value) => setDialogState(() => isActive = value),
                    ),
                    const Divider(),
                    Align(alignment: AlignmentDirectional.centerStart, child: Text(tr.text('user_specific_overrides'), style: const TextStyle(fontWeight: FontWeight.bold))),
                    for (final permission in AppPermission.all)
                      ListTile(
                        title: Text(AppPermission.labels[permission] ?? permission),
                        subtitle: Text(permission),
                        trailing: DropdownButton<String>(
                          value: denied.contains(permission) ? 'deny' : extra.contains(permission) ? 'allow' : 'inherit',
                          items: [
                            DropdownMenuItem(value: 'inherit', child: Text(tr.text('inherit'))),
                            DropdownMenuItem(value: 'allow', child: Text(tr.text('allow'))),
                            DropdownMenuItem(value: 'deny', child: Text(tr.text('deny'))),
                          ],
                          onChanged: isStoreOwner ? null : (value) {
                            setDialogState(() {
                              extra.remove(permission);
                              denied.remove(permission);
                              if (value == 'allow') extra.add(permission);
                              if (value == 'deny') denied.add(permission);
                            });
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(tr.text('cancel'))),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  _UserEditResult(
                    user: AppUser(
                      id: user?.id ?? '',
                      fullName: nameController.text,
                      username: usernameController.text,
                      passwordHash: user?.passwordHash ?? '',
                      roleId: isStoreOwner ? 'admin' : roleId,
                      extraPermissions: isStoreOwner ? const <String>{} : extra,
                      deniedPermissions: isStoreOwner ? const <String>{} : denied,
                      isActive: isStoreOwner ? true : isActive,
                      isSystem: user?.isSystem ?? false,
                      createdAt: user?.createdAt,
                      updatedAt: user?.updatedAt,
                      lastLoginAt: user?.lastLoginAt,
                    ),
                    password: passwordController.text.trim().isEmpty ? null : passwordController.text.trim(),
                  ),
                );
              },
              child: Text(tr.text('save')),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    await _saveUserEditResult(result, isStoreOwner: isStoreOwner);
  }

  bool _isCloudAuthRequired(Object error) {
    final message = error.toString();
    return message.contains('Cloud owner re-authentication required') ||
        message.contains('Online account session is missing') ||
        message.contains('Connect to the cloud account before editing');
  }

  Future<void> _saveUserEditResult(
    _UserEditResult result, {
    required bool isStoreOwner,
    bool alreadyAskedCloudAuth = false,
  }) async {
    try {
      await widget.store.addOrUpdateUser(result.user, password: result.password);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isStoreOwner
                ? 'تم تحديث المدير الأساسي على السحابة والمحلي بنجاح.'
                : 'تم حفظ المستخدم بنجاح.'),
          ),
        );
      }
    } catch (e) {
      if (isStoreOwner && !alreadyAskedCloudAuth && _isCloudAuthRequired(e)) {
        final authenticated = await _showCloudReauthDialog(result.user.username);
        if (authenticated == true && mounted) {
          await _saveUserEditResult(
            result,
            isStoreOwner: isStoreOwner,
            alreadyAskedCloudAuth: true,
          );
          return;
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_friendlyErrorMessage(e))),
        );
      }
    }
  }

  String _defaultCloudLoginName(String localUsername) {
    final cache = AccountAuthCache.load();
    if ((cache?.loginName.trim().isNotEmpty ?? false)) {
      return cache!.loginName.trim().toLowerCase();
    }
    final username = localUsername.trim().toLowerCase();
    final storeSlug = cache?.storeSlug.trim().toLowerCase() ?? '';
    if (storeSlug.isNotEmpty && !username.contains('@')) {
      return '$username@$storeSlug';
    }
    return username;
  }

  Future<bool?> _showCloudReauthDialog(String localUsername) async {
    final tr = AppLocalizations.of(context);
    final loginController = TextEditingController(text: _defaultCloudLoginName(localUsername));
    final passwordController = TextEditingController();
    bool isSubmitting = false;
    String? errorMessage;

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(tr.isArabic ? 'تأكيد الحساب السحابي' : 'Confirm cloud account'),
          content: SizedBox(
            width: VentioResponsive.modalMaxWidth(context, 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tr.isArabic
                      ? 'جلسة السحابة غير متاحة أو منتهية. أدخل حساب المدير الأساسي السحابي للمتابعة دون مغادرة الصفحة.'
                      : 'The cloud session is unavailable or expired. Enter the primary cloud admin account to continue without leaving this page.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: loginController,
                  decoration: InputDecoration(labelText: tr.isArabic ? 'الحساب السحابي' : 'Cloud account'),
                  enabled: !isSubmitting,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: InputDecoration(labelText: tr.isArabic ? 'كلمة المرور الحالية' : 'Current password'),
                  enabled: !isSubmitting,
                ),
                if (errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    errorMessage!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSubmitting ? null : () => Navigator.pop(dialogContext, false),
              child: Text(tr.isArabic ? 'إلغاء' : 'Cancel'),
            ),
            FilledButton(
              onPressed: isSubmitting
                  ? null
                  : () async {
                      final loginName = loginController.text.trim().toLowerCase();
                      final password = passwordController.text;
                      if (loginName.isEmpty || password.trim().isEmpty) {
                        setDialogState(() => errorMessage = tr.isArabic ? 'أدخل الحساب وكلمة المرور.' : 'Enter the account and password.');
                        return;
                      }
                      setDialogState(() {
                        isSubmitting = true;
                        errorMessage = null;
                      });
                      try {
                        final result = await AccountAuthService().login(
                          username: loginName,
                          password: password,
                        );
                        if (!result.ok) {
                          setDialogState(() {
                            isSubmitting = false;
                            errorMessage = result.message.isEmpty
                                ? (tr.isArabic ? 'فشل تسجيل الدخول إلى السحابة.' : 'Cloud login failed.')
                                : result.message;
                          });
                          return;
                        }
                        await AccountAuthService.cacheOnlineResult(
                          result,
                          mode: 'online',
                        );
                        if (dialogContext.mounted) Navigator.pop(dialogContext, true);
                      } catch (error) {
                        setDialogState(() {
                          isSubmitting = false;
                          errorMessage = _friendlyErrorMessage(error);
                        });
                      }
                    },
              child: isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(tr.isArabic ? 'تأكيد' : 'Confirm'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteUser(AppUser user) async {
    final tr = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr.text('confirm_delete')),
        content: Text('${tr.text('delete_confirm_message')} ${user.fullName} (${user.username})?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(tr.text('cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: Text(tr.text('delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.store.deleteUser(user.id);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_friendlyErrorMessage(e))),
        );
      }
    }
  }
}

class _UserEditResult {
  const _UserEditResult({required this.user, this.password});
  final AppUser user;
  final String? password;
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.action});

  final String title;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
        action,
      ],
    );
  }
}
