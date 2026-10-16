import '../../models/app_identity.dart';
import '../../models/app_user.dart';
import '../../models/user_role.dart';

/// Session-local cache state. SQLite remains authoritative.
class SecurityState {
  String currentRole = 'admin';
  String deviceId = '';
  final List<UserRole> roles = [];
  final List<AppUser> users = [];
  AppUser? activeUser;
  bool rememberLogin = false;
  DateTime? sensitiveAuthorizationExpiresAt;
  String sensitiveAuthorizationUserId = '';
  final Set<String> sensitiveAuthorizationActions = <String>{};
  final Map<String, List<DateTime>> failedLoginAttempts =
      <String, List<DateTime>>{};
  final Map<String, DateTime> loginBlockedUntil = <String, DateTime>{};
  AppIdentity? appIdentity;
}
