import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppLocalizations {
  AppLocalizations(this.locale);

  final Locale locale;

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static AppLocalizations of(BuildContext context) {
    final localizations =
        Localizations.of<AppLocalizations>(context, AppLocalizations);
    assert(localizations != null, 'AppLocalizations not found in widget tree.');
    return localizations!;
  }

  late Map<String, dynamic> _localizedStrings;

  Future<void> load() async {
    final jsonString = await rootBundle
        .loadString('assets/translations/${locale.languageCode}.json');
    _localizedStrings = json.decode(jsonString) as Map<String, dynamic>;
  }

  String text(String key) {
    return _localizedStrings[key] as String? ?? key;
  }

  String format(String key, Map<String, Object?> values) {
    var template = text(key);
    values.forEach((name, value) {
      template = template.replaceAll('{$name}', value?.toString() ?? '');
    });
    return template;
  }

  bool get isArabic => locale.languageCode == 'ar';

  TextDirection get textDirection =>
      isArabic ? TextDirection.rtl : TextDirection.ltr;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => ['en', 'ar'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async {
    final appLocalizations = AppLocalizations(locale);
    await appLocalizations.load();
    return appLocalizations;
  }

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppLocalizations> old) =>
      false;
}

String localizeRuntimeMessage(String message, AppLocalizations tr) {
  var value = message.trim();
  if (value.isEmpty) return value;

  final exact = <String, String>{
    'Initial Store data is downloading from the Host.':
        'initial_store_data_downloading',
    'Initial Store data downloaded.': 'initial_store_data_downloaded',
    'Store recovered.': 'store_recovered',
    'Store identity recovered.': 'store_identity_recovered',
    'Recover Store Identity first.': 'recover_store_identity_first',
    'Requesting a fresh Host snapshot...': 'requesting_fresh_host_snapshot',
    'Verifying rebuilt local data...': 'verifying_rebuilt_local_data',
    'Cleaning up local records...': 'cleaning_up_local_records',
    'Cloud rebuild completed.': 'cloud_rebuild_completed',
    'Pairing code created.': 'pairing_code_created',
    'Pairing code failed.': 'pairing_code_failed',
    'Pairing code expired or already used. Ask the Host device for a new code.':
        'pairing_code_expired_or_used',
    'Device paired successfully. Please sign in.': 'device_paired_sign_in',
    'Device paired successfully. Login data downloaded. Please sign in; remaining Store data will continue downloading.':
        'device_paired_login_downloaded',
    'Device paired successfully. Waiting for Host login data. Keep the Host online; Store data will download automatically.':
        'device_paired_waiting_host_login',
    'Device paired successfully. Initial Store data will download automatically when the Host is online.':
        'device_paired_initial_download_auto',
    'Device suspended in Cloud.': 'device_suspended_cloud',
    'Device resumed in Cloud.': 'device_resumed_cloud',
    'Device revoked.': 'device_revoked',
    'Device heartbeat updated.': 'device_heartbeat_updated',
    'Only Clients can request Host transfer.': 'only_clients_host_transfer',
    'Host transfer request sent.': 'host_transfer_request_sent',
    'Only Hosts can approve Host transfer.': 'only_hosts_approve_transfer',
    'Host transfer approved in Cloud.': 'host_transfer_approved_cloud',
    'Host transfer activated in Cloud.': 'host_transfer_activated_cloud',
    'Cloud API connection is healthy.': 'cloud_api_connection_healthy',
    'Cloud Connected/Ready for Sync.': 'cloud_connected_ready_sync',
    'No other active Host was found.': 'no_other_active_host',
    'Host heartbeat updated.': 'host_heartbeat_updated',
    'Host heartbeat is fresh.': 'host_heartbeat_fresh',
    'No host heartbeat was found.': 'no_host_heartbeat_found',
    'Host heartbeat is stale.': 'host_heartbeat_stale',
    'Rejected by Host.': 'rejected_by_host',
    'Preparing Host cloud snapshot queue...':
        'preparing_host_cloud_snapshot_queue',
    'Sending Host heartbeat...': 'sending_host_heartbeat',
    'Registering Host device...': 'registering_host_device',
    'Checking Client requests...': 'checking_client_requests',
    'Uploading authoritative Host changes...':
        'uploading_authoritative_host_changes',
    'Registering Client device...': 'registering_client_device',
    'Cleaning up after Cloud sync...': 'cleaning_up_after_cloud_sync',
    'Host is still uploading store data. Download will continue automatically.':
        'host_still_uploading_store_data',
    'Cloud API URL and token are required.': 'cloud_api_url_token_required',
    'Cloud Sync is not enabled for this store.':
        'cloud_sync_not_enabled_for_store',
    'Cloud Sync is not ready yet.': 'cloud_sync_not_ready_yet',
    'Only the Host can create pairing codes.': 'only_host_create_pairing_codes',
    'Only the Host can check pairing code status.':
        'only_host_check_pairing_status',
    'Unauthorized/Token invalid: this Client has no saved device token. Pair this device again.':
        'unauthorized_token_invalid_client',
    'Heartbeat is only sent by a cloud-enabled Host device.':
        'heartbeat_only_cloud_host',
    'Cloud is not the active/configured sync transport for this device.':
        'cloud_not_active_transport',
    'Host devices do not pull authoritative Cloud changes.':
        'host_devices_no_pull_cloud',
    'Cloud event log gap detected. Snapshot repair is required.':
        'cloud_event_log_gap_snapshot_required',
    'Cloud pull pagination failed: missing next cursor.':
        'cloud_pull_pagination_missing_cursor',
    'File save was cancelled.': 'file_save_cancelled',
    'Connection is healthy.': 'connection_is_healthy',
    'LAN pairing completed.': 'lan_pairing_completed',
    'Initial clone completed.': 'initial_clone_completed',
    'Pull completed.': 'pull_completed',
    'No LAN changes to push.': 'no_lan_changes_to_push',
    'LAN sync is not available in the web build. Use Cloud Sync/API instead.':
        'lan_sync_web_unavailable',
    'LAN pairing is not available in the web build.':
        'lan_pairing_web_unavailable',
    'LAN initial clone is not available in the web build.':
        'lan_initial_clone_web_unavailable',
    'LAN pull is not available in the web build.': 'lan_pull_web_unavailable',
    'LAN push is not available in the web build.': 'lan_push_web_unavailable',
    'LAN repair is not available in the web build. Use Cloud Sync/API instead.':
        'lan_repair_web_unavailable',
  };
  final key = exact[value];
  if (key != null) return tr.text(key);

  if (value.contains('Cloud Sync is not enabled for this store.')) {
    return value.replaceFirst(
      'Cloud Sync is not enabled for this store.',
      tr.text('cloud_sync_not_enabled_for_store'),
    );
  }
  if (value.contains('Cloud Sync is not ready yet.')) {
    return value.replaceFirst(
      'Cloud Sync is not ready yet.',
      tr.text('cloud_sync_not_ready_yet'),
    );
  }

  String prefixed(String englishPrefix, String key) {
    if (value.startsWith('$englishPrefix: ')) {
      return '${tr.text(key)}: ${value.substring(englishPrefix.length + 2)}';
    }
    if (value.startsWith('$englishPrefix. ')) {
      return '${tr.text(key)}. ${value.substring(englishPrefix.length + 2)}';
    }
    if (value.startsWith(englishPrefix)) {
      final rest = value.substring(englishPrefix.length).trimLeft();
      return rest.isEmpty ? tr.text(key) : '${tr.text(key)} $rest';
    }
    return '';
  }

  for (final item in <String, String>{
    'Pairing code failed': 'pairing_code_failed',
    'Device revoke failed': 'device_revoked_failed',
    'Device heartbeat failed': 'device_heartbeat_failed',
    'Host transfer request failed': 'host_transfer_request_failed',
    'Host transfer approval failed': 'host_transfer_approval_failed',
    'Host transfer activation failed': 'host_transfer_activation_failed',
    'Cloud API connection failed': 'cloud_api_connection_failed',
    'Cloud Server Unreachable': 'cloud_server_unreachable',
    'Host Offline': 'host_offline',
    'Sync Not Ready': 'sync_not_ready',
    'Host heartbeat failed': 'host_heartbeat_failed',
    'Cloud push failed': 'cloud_push_failed',
    'Cloud pull failed': 'cloud_pull_failed',
    'Cloud sync failed': 'cloud_sync_failed',
    'Connection failed': 'connection_failed',
    'Initial clone failed': 'initial_clone_failed',
    'Pull failed': 'pull_failed',
    'LAN push failed': 'lan_push_failed',
    'LAN pull failed': 'lan_pull_failed',
    'Sync failed': 'sync_failed',
  }.entries) {
    final translated = prefixed(item.key, item.value);
    if (translated.isNotEmpty) return translated;
  }

  final cloudPage =
      RegExp(r'^Pulling Cloud changes page (\d+)\.\.\.$').firstMatch(value);
  if (cloudPage != null) {
    return tr
        .format('pulling_cloud_changes_page', {'page': cloudPage.group(1)});
  }

  if (value.startsWith(
      'Cloud rebuild completed from a requested fresh Host snapshot.')) {
    return '${tr.text('cloud_rebuild_completed_fresh')} ${value.substring('Cloud rebuild completed from a requested fresh Host snapshot.'.length).trim()}'
        .trim();
  }
  if (value.startsWith(
      'Cloud rebuild pulled a fresh Host snapshot, but local verification found problems:')) {
    return '${tr.text('cloud_rebuild_pulled_but_issues')}: ${value.substring('Cloud rebuild pulled a fresh Host snapshot, but local verification found problems:'.length).trim()}';
  }
  if (value.startsWith(
      'Cloud rebuild requested a fresh Host snapshot, but no snapshot was pulled yet. Keep the Host online and retry.')) {
    return '${tr.text('cloud_rebuild_no_snapshot_yet')} ${value.substring('Cloud rebuild requested a fresh Host snapshot, but no snapshot was pulled yet. Keep the Host online and retry.'.length).trim()}'
        .trim();
  }
  if (value.startsWith('Pairing code belongs to a different Store')) {
    return value
        .replaceFirst('Pairing code belongs to a different Store',
            tr.text('pairing_code_different_store'))
        .replaceFirst('Use the current Host pairing code.',
            tr.text('use_current_host_pairing_code'));
  }
  if (value.startsWith('Another active Host is already connected for store')) {
    return value.replaceFirst(
        'Another active Host is already connected for store',
        tr.text('another_active_host_connected'));
  }
  if (value.startsWith('Host cloud push completed.')) {
    return value.replaceFirst(
        'Host cloud push completed.', tr.text('host_cloud_push_completed'));
  }
  if (value.startsWith('Client cloud push completed.')) {
    return value.replaceFirst(
        'Client cloud push completed.', tr.text('client_cloud_push_completed'));
  }
  if (value.startsWith('Cloud pull stopped after')) {
    return value.replaceFirst(
        'Cloud pull stopped after', tr.text('cloud_pull_stopped_max_pages'));
  }
  if (value.startsWith('Cloud pull completed.')) {
    return value.replaceFirst(
        'Cloud pull completed.', tr.text('cloud_pull_completed'));
  }
  if (value.startsWith('Cloud sync completed.')) {
    return value.replaceFirst(
        'Cloud sync completed.', tr.text('cloud_sync_completed'));
  }
  if (value.startsWith('LAN push completed.')) {
    return value.replaceFirst(
        'LAN push completed.', tr.text('lan_push_completed'));
  }
  if (value.startsWith('LAN pull completed.')) {
    return value.replaceFirst(
        'LAN pull completed.', tr.text('lan_pull_completed'));
  }
  if (value.startsWith('Sync completed.')) {
    return value.replaceFirst('Sync completed.', tr.text('sync_completed'));
  }

  if (tr.isArabic) {
    var localized = value
        .replaceAll('Cloud Sync', 'مزامنة الاتصال السحابي')
        .replaceAll('Cloud API', 'واجهة الاتصال السحابي')
        .replaceAll('Cloud', 'اتصال سحابي')
        .replaceAll('LAN Sync', 'مزامنة الشبكة المحلية')
        .replaceAll('LAN', 'شبكة محلية')
        .replaceAll('Host', 'المضيف')
        .replaceAll('Client', 'العميل')
        .replaceAll('Store', 'المتجر');
    if (localized != value) return localized;
  }

  return message;
}
