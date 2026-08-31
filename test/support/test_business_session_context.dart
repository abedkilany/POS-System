import 'package:ventio/core/repositories/business_session_context.dart';
import 'package:ventio/models/app_identity.dart';
import 'package:ventio/models/app_user.dart';
import 'package:ventio/models/product_costing.dart';
import 'package:ventio/models/store_profile.dart';
import 'package:ventio/models/user_role.dart';

class TestBusinessSessionContext implements BusinessSessionContext {
  TestBusinessSessionContext({Set<String>? permissions})
      : permissions = permissions ?? AppPermission.all.toSet(),
        _identity = AppIdentity.defaults(
          deviceId: 'TEST-DEVICE',
          platform: AppPlatformType.windows,
          detectedDeviceName: 'Test Device',
        );

  final Set<String> permissions;
  final AppIdentity _identity;

  @override
  String get deviceId => _identity.deviceId;

  @override
  AppIdentity get appIdentity => _identity;

  @override
  StoreProfile get storeProfile => StoreProfile.defaults;

  @override
  AppUser? get activeUser => null;

  @override
  String get currentRole => 'test';

  @override
  InventoryCostingMethod get inventoryCostingMethod => InventoryCostingMethod.batch;

  @override
  bool hasPermission(String permission) => permissions.contains(permission);

  @override
  void requirePermission(String permission) {
    if (!hasPermission(permission)) {
      throw StateError('Permission denied: $permission');
    }
  }

  @override
  Future<void> refreshAfterDatabaseChange(String key) async {}
}
