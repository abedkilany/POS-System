import 'package:flutter_test/flutter_test.dart';
import 'package:ventio/core/services/permission_service.dart';
import 'package:ventio/models/app_user.dart';
import 'package:ventio/models/user_role.dart';

void main() {
  const service = PermissionService();

  test('combines role and user grants, then applies explicit denials', () {
    const user = AppUser(
      id: 'u1',
      fullName: 'User',
      username: 'user',
      passwordHash: '',
      roleId: 'operator',
      extraPermissions: <String>{'reports.export', 'sales.create'},
      deniedPermissions: <String>{'sales.create'},
    );
    const roles = <UserRole>[
      UserRole(
        id: 'operator',
        name: 'Operator',
        permissions: <String>{'sales.create', 'sales.view'},
      ),
    ];

    expect(
      service.hasPermission(
        user: user,
        roles: roles,
        permission: 'sales.view',
      ),
      isTrue,
    );
    expect(
      service.hasPermission(
        user: user,
        roles: roles,
        permission: 'reports.export',
      ),
      isTrue,
    );
    expect(
      service.hasPermission(
        user: user,
        roles: roles,
        permission: 'sales.create',
      ),
      isFalse,
    );
    expect(
      () => service.requirePermission(
        user: user,
        roles: roles,
        permission: 'sales.create',
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'You do not have permission: sales.create',
        ),
      ),
    );
  });

  test('keeps the built-in admin role privileged during role hydration', () {
    const user = AppUser(
      id: 'admin-user',
      fullName: 'Admin',
      username: 'admin',
      passwordHash: '',
      roleId: 'admin',
    );
    expect(
      service.hasPermission(
        user: user,
        roles: const <UserRole>[],
        permission: 'database.manage',
      ),
      isTrue,
    );
    expect(
      service.hasPermission(
        user: null,
        roles: const <UserRole>[],
        permission: 'database.manage',
      ),
      isFalse,
    );
  });
}
