import '../../models/app_user.dart';
import '../../models/user_role.dart';

/// Computes effective permissions from the active user and its assigned role.
class PermissionService {
  const PermissionService();

  bool hasPermission({
    required AppUser? user,
    required Iterable<UserRole> roles,
    required String permission,
  }) {
    if (user == null) return false;
    UserRole? role;
    for (final candidate in roles) {
      if (candidate.id == user.roleId) {
        role = candidate;
        break;
      }
    }
    if (user.roleId == 'admin' || role?.isAdmin == true) return true;
    final effective = <String>{
      ...?role?.permissions,
      ...user.extraPermissions,
    };
    effective.removeAll(user.deniedPermissions);
    return effective.contains(permission);
  }

  void requirePermission({
    required AppUser? user,
    required Iterable<UserRole> roles,
    required String permission,
  }) {
    if (!hasPermission(user: user, roles: roles, permission: permission)) {
      throw StateError('You do not have permission: $permission');
    }
  }
}
