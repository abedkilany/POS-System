import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../app_brand.dart';
import '../../data/app_store.dart';
import '../../models/app_identity.dart';
import '../sync_unified/unified_pairing_lifecycle.dart';
import 'account_auth_service.dart';
import 'direct_device_identity.dart';
import 'direct_sync_settings.dart';
import 'sync_diagnostics_log.dart';

class DirectPairingCodeResult {
  const DirectPairingCodeResult({
    required this.ok,
    required this.message,
    this.code = '',
    this.expiresAt,
    this.storeId = '',
    this.branchId = 'main',
    this.hostDeviceId = '',
  });

  final bool ok;
  final String message;
  final String code;
  final DateTime? expiresAt;
  final String storeId;
  final String branchId;
  final String hostDeviceId;
}

class DirectPairingClaimResult {
  const DirectPairingClaimResult({
    required this.ok,
    required this.message,
    this.identity,
  });

  final bool ok;
  final String message;
  final AppIdentity? identity;
}

/// Control-plane pairing for Direct.
///
/// The VPS only brokers a short-lived pairing code and device credentials.
/// Actual store data is transferred through the Direct peer channel.
class DirectPeerPairingService {
  DirectPeerPairingService(this.store, {http.Client? client})
      : _client = client ?? http.Client();

  final AppStore store;
  final http.Client _client;

  String _newCode() {
    const alphabet =
        'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';
    final random = Random.secure();
    return List.generate(16, (_) => alphabet[random.nextInt(alphabet.length)])
        .join();
  }

  Map<String, String> _headers() {
    final identity = store.appIdentity;
    final accountCache = AccountAuthCache.load();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (!identity.isClient &&
          (accountCache?.accountToken.trim().isNotEmpty ?? false))
        'Authorization': 'Bearer ${accountCache!.accountToken.trim()}',
      'X-Device-Id': store.deviceId,
      'X-Device-Token': identity.deviceToken,
      'X-Device-Role': identity.deviceRole.name,
      'X-Sync-Transport': 'direct',
      'X-Store-Id': identity.storeId,
      'X-Branch-Id': identity.branchId,
    };
  }

  Future<DirectPairingCodeResult> createPairingCode(
    DirectSyncSettings settings, {
    int ttlMinutes = 5,
  }) async {
    final identity = store.appIdentity;
    if (!identity.isHost || settings.apiBaseUrl.trim().isEmpty) {
      return const DirectPairingCodeResult(
        ok: false,
        message: 'Direct pairing service is not ready yet.',
      );
    }
    try {
      final directIdentity = await DirectDeviceIdentity.loadOrCreate();
      final response = await _client
          .post(
            _endpoint(settings, '/api/sync/pairing/create'),
            headers: _headers(),
            body: jsonEncode({
              'storeId': identity.storeId,
              'branchId': identity.branchId,
              'hostDeviceId': store.deviceId,
              'hostDeviceName': identity.deviceName,
              'transport': 'direct',
              'code': _newCode(),
              'ttlMinutes': ttlMinutes,
              'recoveryKey': identity.recoveryKey,
              'devicePublicKey': directIdentity.publicKeyEncoded,
            }),
          )
          .timeout(const Duration(seconds: 10));
      final decoded = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return DirectPairingCodeResult(
          ok: false,
          message: _serverMessage(response, decoded, 'Direct pairing failed.'),
        );
      }
      final ok = decoded['ok'] == true;
      return DirectPairingCodeResult(
        ok: ok,
        message: ok
            ? 'Direct pairing code created.'
            : (decoded['error']?.toString() ?? 'Direct pairing failed.'),
        code: decoded['code']?.toString() ?? '',
        expiresAt: DateTime.tryParse(decoded['expiresAt']?.toString() ?? ''),
        storeId: decoded['storeId']?.toString() ?? identity.storeId,
        branchId: decoded['branchId']?.toString() ?? identity.branchId,
        hostDeviceId: decoded['hostDeviceId']?.toString() ?? identity.deviceId,
      );
    } catch (error) {
      return DirectPairingCodeResult(
        ok: false,
        message: 'Direct pairing failed: $error',
      );
    }
  }

  Future<DirectPairingClaimResult> claimPairingCode(
    DirectSyncSettings settings,
    String code, {
    void Function(double value, String label)? onProgress,
  }) async {
    final current = store.appIdentity;
    if (current.isHost) {
      return const DirectPairingClaimResult(
        ok: false,
        message: 'Host devices cannot claim Direct pairing codes.',
      );
    }
    if (settings.apiBaseUrl.trim().isEmpty) {
      return const DirectPairingClaimResult(
        ok: false,
        message: 'Direct API URL is required.',
      );
    }
    var registered = false;
    onProgress?.call(0.08, 'Connecting to Direct pairing service...');
    try {
      final directIdentity = await DirectDeviceIdentity.loadOrCreate();
      final response = await _client
          .post(
            _endpoint(settings, '/api/sync/pairing/claim'),
            headers: _headers(),
            body: jsonEncode({
              'code': code.trim(),
              'deviceId': store.deviceId,
              'deviceName': current.deviceName,
              'platform': current.platform.name,
              'appVersion': AppBrand.version,
              'devicePublicKey': directIdentity.publicKeyEncoded,
            }),
          )
          .timeout(const Duration(seconds: 10));
      final decoded = _decode(response.body);
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          decoded['ok'] != true) {
        SyncDiagnosticsLog.add(
            '[DIRECT_PAIRING] claim rejected status=${response.statusCode} '
            'message=${_serverMessage(response, decoded, 'Pairing claim failed.')}');
        return DirectPairingClaimResult(
          ok: false,
          message: _serverMessage(
            response,
            decoded,
            'Pairing claim failed.',
          ),
        );
      }

      final claim = UnifiedPairingClaimPayload(
        storeId: decoded['storeId']?.toString() ?? current.storeId,
        branchId: decoded['branchId']?.toString() ?? current.branchId,
        hostDeviceId:
            decoded['hostDeviceId']?.toString() ?? current.hostDeviceId,
        deviceToken: decoded['deviceToken']?.toString() ?? current.deviceToken,
        transport: 'direct',
      );
      final mismatch = UnifiedPairingLifecycle.validateSameStoreClaim(
        current,
        claim,
        label: 'Direct pairing code',
      );
      if (mismatch != null) {
        return DirectPairingClaimResult(ok: false, message: mismatch);
      }
      final hostPublicKey =
          decoded['hostDevicePublicKey']?.toString().trim() ?? '';
      if (hostPublicKey.isNotEmpty &&
          !await DirectDeviceIdentity.verifyOrTrustPeer(
            deviceId: claim.hostDeviceId,
            publicKeyEncoded: hostPublicKey,
          )) {
        return const DirectPairingClaimResult(
          ok: false,
          message: 'The Host device identity changed unexpectedly.',
        );
      }
      final identity = UnifiedPairingLifecycle.buildClientIdentity(
        current,
        claim: claim,
        syncMode: SyncMode.directConnected,
        activeTransport: 'direct',
      );
      onProgress?.call(0.22, 'Registering this Direct device...');
      await store.updateAppIdentityDuringSetup(identity);
      registered = true;
      final existing = DirectSyncSettings.load();
      await existing
          .copyWith(
            apiBaseUrl: settings.apiBaseUrl,
            peerDeviceId: claim.hostDeviceId,
            setupComplete: true,
          )
          .save();
      onProgress?.call(1.0, 'Direct device paired successfully.');
      return DirectPairingClaimResult(
        ok: true,
        message: 'Device paired successfully. Please sign in.',
        identity: store.appIdentity,
      );
    } catch (error) {
      SyncDiagnosticsLog.add(
          '[DIRECT_PAIRING] claim failed registered=$registered error=$error');
      return DirectPairingClaimResult(
        ok: false,
        message: registered
            ? 'Device registered, but Direct setup is incomplete: $error'
            : 'Could not connect this device. Check the pairing code and try again.',
        identity: registered ? store.appIdentity : null,
      );
    }
  }

  Uri _endpoint(DirectSyncSettings settings, String path) {
    final base = settings.apiBaseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse('$base${path.startsWith('/') ? path : '/$path'}');
  }

  Map<String, dynamic> _decode(String body) {
    try {
      final value = jsonDecode(body);
      return value is Map
          ? Map<String, dynamic>.from(value)
          : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  String _serverMessage(
      http.Response response, Map<String, dynamic> decoded, String fallback) {
    final message =
        (decoded['error'] ?? decoded['message'] ?? '').toString().trim();
    return message.isNotEmpty ? message : '$fallback ${response.statusCode}';
  }

  void dispose() => _client.close();
}
