import '../../models/app_identity.dart';
import '../../models/app_user.dart';
import '../../models/product_costing.dart';
import '../../models/store_profile.dart';

abstract class BusinessSessionContext {
  String get deviceId;
  AppIdentity get appIdentity;
  StoreProfile get storeProfile;
  AppUser? get activeUser;
  String get currentRole;
  InventoryCostingMethod get inventoryCostingMethod;
  bool hasPermission(String permission);
  void requirePermission(String permission);
  Future<void> refreshAfterDatabaseChange(String key);
}
