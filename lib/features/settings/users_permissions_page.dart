
import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';
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
        padding: const EdgeInsets.all(16),
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
                subtitle: Text('${store.roleById(user.roleId)?.name ?? user.roleId} • ${user.isActive ? tr.text('active') : tr.text('disabled')}'),
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

  Future<void> _editRole({UserRole? role}) async {
    final tr = AppLocalizations.of(context);
    final nameController = TextEditingController(text: role?.name ?? '');
    final permissions = Set<String>.from(role?.permissions ?? const <String>{});

    final result = await showDialog<UserRole>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(role == null ? 'Add role' : 'Edit role'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Role name')),
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _deleteRole(UserRole role) async {
    try {
      await widget.store.deleteRole(role.id);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _editUser({AppUser? user}) async {
    final tr = AppLocalizations.of(context);
    final nameController = TextEditingController(text: user?.fullName ?? '');
    final usernameController = TextEditingController(text: user?.username ?? '');
    final passwordController = TextEditingController();
    String roleId = user?.roleId ?? widget.store.roles.first.id;
    bool isActive = user?.isActive ?? true;
    final extra = Set<String>.from(user?.extraPermissions ?? const <String>{});
    final denied = Set<String>.from(user?.deniedPermissions ?? const <String>{});

    final result = await showDialog<_UserEditResult>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(user == null ? 'Add user' : 'Edit user'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Full name')),
                  const SizedBox(height: 12),
                  TextField(controller: usernameController, decoration: const InputDecoration(labelText: 'Username')),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: InputDecoration(labelText: user == null ? 'Password' : 'New password (leave empty to keep current)'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: roleId,
                    decoration: const InputDecoration(labelText: 'Role'),
                    items: [
                      for (final role in widget.store.roles) DropdownMenuItem(value: role.id, child: Text(role.name)),
                    ],
                    onChanged: (value) => setDialogState(() => roleId = value ?? roleId),
                  ),
                  SwitchListTile(
                    value: isActive,
                    title: Text(tr.text('active')),
                    onChanged: user?.isSystem == true ? null : (value) => setDialogState(() => isActive = value),
                  ),
                  const Divider(),
                  const Align(alignment: Alignment.centerLeft, child: Text('User-specific overrides', style: TextStyle(fontWeight: FontWeight.bold))),
                  for (final permission in AppPermission.all)
                    ListTile(
                      title: Text(AppPermission.labels[permission] ?? permission),
                      subtitle: Text(permission),
                      trailing: DropdownButton<String>(
                        value: denied.contains(permission) ? 'deny' : extra.contains(permission) ? 'allow' : 'inherit',
                        items: const [
                          DropdownMenuItem(value: 'inherit', child: Text('Inherit')),
                          DropdownMenuItem(value: 'allow', child: Text('Allow')),
                          DropdownMenuItem(value: 'deny', child: Text('Deny')),
                        ],
                        onChanged: (value) {
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
                      roleId: roleId,
                      extraPermissions: extra,
                      deniedPermissions: denied,
                      isActive: isActive,
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
    try {
      await widget.store.addOrUpdateUser(result.user, password: result.password);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _deleteUser(AppUser user) async {
    try {
      await widget.store.deleteUser(user.id);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
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
