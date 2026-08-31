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
  late Map<String, String> _englishKeysByValue;
  late List<MapEntry<String, String>> _englishTemplates;

  Future<void> load() async {
    final localizedJson = await rootBundle
        .loadString('assets/translations/${locale.languageCode}.json');
    final englishJson = locale.languageCode == 'en'
        ? localizedJson
        : await rootBundle.loadString('assets/translations/en.json');
    _localizedStrings = json.decode(localizedJson) as Map<String, dynamic>;
    final englishStrings = Map<String, dynamic>.from(
        json.decode(englishJson) as Map<String, dynamic>);
    _englishKeysByValue = <String, String>{
      for (final entry in englishStrings.entries)
        if (entry.value is String &&
            !(entry.value as String).contains(RegExp(r'\{[^}]+\}')))
          entry.value as String: entry.key,
    };
    _englishTemplates = englishStrings.entries
        .where((entry) =>
            entry.value is String &&
            (entry.value as String).contains(RegExp(r'\{[^}]+\}')))
        .map((entry) => MapEntry(entry.key, entry.value as String))
        .toList(growable: false)
      ..sort((left, right) => right.value.length.compareTo(left.value.length));
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

  String? localizeEnglishMessage(String message) {
    final exactKey = _englishKeysByValue[message];
    if (exactKey != null) return text(exactKey);

    final placeholderPattern = RegExp(r'\{([A-Za-z_][A-Za-z0-9_]*)\}');
    for (final entry in _englishTemplates) {
      final matches = placeholderPattern.allMatches(entry.value).toList();
      if (matches.isEmpty) continue;
      final expression = StringBuffer('^');
      var cursor = 0;
      for (final match in matches) {
        expression
            .write(RegExp.escape(entry.value.substring(cursor, match.start)));
        expression.write(r'([\s\S]*?)');
        cursor = match.end;
      }
      expression.write(RegExp.escape(entry.value.substring(cursor)));
      expression.write(r'$');
      final runtimeMatch = RegExp(expression.toString()).firstMatch(message);
      if (runtimeMatch == null) continue;
      final values = <String, Object?>{};
      for (var index = 0; index < matches.length; index += 1) {
        values[matches[index].group(1)!] = runtimeMatch.group(index + 1);
      }
      return format(entry.key, values);
    }
    return null;
  }

  bool get isArabic => locale.languageCode == 'ar';

  TextDirection get textDirection =>
      isArabic ? TextDirection.rtl : TextDirection.ltr;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      ['en', 'ar', 'fr'].contains(locale.languageCode);

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
    'Host restored data. Rebuilding this device from the latest snapshot...':
        'host_restored_data_rebuilding_from_snapshot',
    'Preparing LAN sync...': 'preparing_lan_sync',
    'Preparing Direct sync...': 'preparing_direct_sync',
    'Preparing local sync...': 'preparing_local_sync',
    'LAN sync failed while sending local changes.':
        'lan_sync_failed_while_sending_local_changes',
    'Direct sync failed while sending local changes.':
        'direct_sync_failed_while_sending_local_changes',
    'local sync failed while sending local changes.':
        'local_sync_failed_while_sending_local_changes',
    'Pulling authoritative LAN changes...': 'pulling_authoritative_lan_changes',
    'Pulling authoritative Direct changes...':
        'pulling_authoritative_direct_changes',
    'Pulling authoritative local changes...':
        'pulling_authoritative_local_changes',
    'LAN pull failed. Trying snapshot repair...':
        'lan_pull_failed_trying_snapshot_repair',
    'Direct pull failed. Trying snapshot repair...':
        'direct_pull_failed_trying_snapshot_repair',
    'local pull failed. Trying snapshot repair...':
        'local_pull_failed_trying_snapshot_repair',
    'LAN sync completed.': 'lan_sync_completed',
    'Direct sync completed.': 'direct_sync_completed',
    'local sync completed.': 'local_sync_completed',
    'LAN sync completed. Pushed {pushed} change(s), pulled {pulled} change(s).':
        'lan_sync_completed_details',
    'Direct sync completed. Pushed {pushed} change(s), pulled {pulled} change(s).':
        'direct_sync_completed_details',
    'local sync completed. Pushed {pushed} change(s), pulled {pulled} change(s).':
        'local_sync_completed_details',
    'Snapshot: requesting manifest...': 'snapshot_requesting_manifest',
    'Snapshot: rebuilding local envelope...':
        'snapshot_rebuilding_local_envelope',
    'Snapshot: downloading chunk {chunk}/{total}...':
        'snapshot_downloading_chunk',
    'Snapshot: uploading chunk {chunk}/{total}...': 'snapshot_uploading_chunk',
    'Snapshot chunk {chunk}/{total} failed after retry: {error}':
        'snapshot_chunk_failed_after_retry',
    'Snapshot returned chunk {chunk}, expected {expected}.':
        'snapshot_chunk_mismatch',
    'Initial Store data is downloading from the Host.':
        'initial_store_data_downloading',
    'Initial Store data downloaded.': 'initial_store_data_downloaded',
    'Store recovered.': 'store_recovered',
    'Store identity recovered.': 'store_identity_recovered',
    'Recover Store Identity first.': 'recover_store_identity_first',
    'Requesting a fresh Host snapshot...': 'requesting_fresh_host_snapshot',
    'Verifying rebuilt local data...': 'verifying_rebuilt_local_data',
    'Cleaning up local records...': 'cleaning_up_local_records',
    'Direct rebuild completed.': 'direct_rebuild_completed',
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
    'Device suspended in Direct.': 'device_suspended_direct',
    'Device resumed in Direct.': 'device_resumed_direct',
    'Device revoked.': 'device_revoked',
    'Device heartbeat updated.': 'device_heartbeat_updated',
    'Only Clients can request Host transfer.': 'only_clients_host_transfer',
    'Host transfer request sent.': 'host_transfer_request_sent',
    'Only Hosts can approve Host transfer.': 'only_hosts_approve_transfer',
    'Host transfer approved in Direct.': 'host_transfer_approved_direct',
    'Host transfer activated in Direct.': 'host_transfer_activated_direct',
    'VPS API connection is healthy.': 'direct_api_connection_healthy',
    'Direct Connected/Ready for Sync.': 'direct_connected_ready_sync',
    'No other active Host was found.': 'no_other_active_host',
    'Host heartbeat updated.': 'host_heartbeat_updated',
    'Host heartbeat is fresh.': 'host_heartbeat_fresh',
    'No host heartbeat was found.': 'no_host_heartbeat_found',
    'Host heartbeat is stale.': 'host_heartbeat_stale',
    'Rejected by Host.': 'rejected_by_host',
    'Preparing Host direct snapshot queue...':
        'preparing_host_direct_snapshot_queue',
    'Sending Host heartbeat...': 'sending_host_heartbeat',
    'Registering Host device...': 'registering_host_device',
    'Checking Client requests...': 'checking_client_requests',
    'Uploading authoritative Host changes...':
        'uploading_authoritative_host_changes',
    'Registering Client device...': 'registering_client_device',
    'Cleaning up after Direct sync...': 'cleaning_up_after_direct_sync',
    'Host is still uploading store data. Download will continue automatically.':
        'host_still_uploading_store_data',
    'VPS API URL and token are required.': 'direct_api_url_token_required',
    'Direct sync is not enabled for this store.':
        'direct_sync_not_enabled_for_store',
    'Direct sync is not ready yet.': 'direct_sync_not_ready_yet',
    'Only the Host can create pairing codes.': 'only_host_create_pairing_codes',
    'Only the Host can check pairing code status.':
        'only_host_check_pairing_status',
    'Unauthorized/Token invalid: this Client has no saved device token. Pair this device again.':
        'unauthorized_token_invalid_client',
    'Heartbeat is only sent by a Direct-enabled Host device.':
        'heartbeat_only_host',
    'Direct is not the active/configured sync transport for this device.':
        'direct_not_active_transport',
    'Host devices do not pull authoritative Direct changes.':
        'host_devices_no_pull_direct',
    'Direct event log gap detected. Snapshot repair is required.':
        'direct_event_log_gap_snapshot_required',
    'Direct pull pagination failed: missing next cursor.':
        'direct_pull_pagination_missing_cursor',
    'File save was cancelled.': 'file_save_cancelled',
    'Connection is healthy.': 'connection_is_healthy',
    'LAN pairing completed.': 'lan_pairing_completed',
    'Initial clone completed.': 'initial_clone_completed',
    'Pull completed.': 'pull_completed',
    'No LAN changes to push.': 'no_lan_changes_to_push',
    'LAN sync is not available in the web build. Use Direct sync/API instead.':
        'lan_sync_web_unavailable',
    'LAN pairing is not available in the web build.':
        'lan_pairing_web_unavailable',
    'LAN initial clone is not available in the web build.':
        'lan_initial_clone_web_unavailable',
    'LAN pull is not available in the web build.': 'lan_pull_web_unavailable',
    'LAN push is not available in the web build.': 'lan_push_web_unavailable',
    'LAN repair is not available in the web build. Use Direct sync/API instead.':
        'lan_repair_web_unavailable',
    'Sales last 7 days': 'dashboard_sales_last_7_days',
    'Sales last 30 days': 'dashboard_sales_last_30_days',
    'Expenses by type': 'dashboard_expenses_by_type',
    'Top products': 'dashboard_top_products',
    'Top customers': 'dashboard_top_customers',
    'Sales vs profit': 'dashboard_sales_vs_profit',
    'Receivables pressure': 'dashboard_receivables_pressure',
    'Payables pressure': 'dashboard_payables_pressure',
    'Sales': 'sales',
    'Profit': 'profit',
    'Current': 'current',
    'Over 30': 'dashboard_over_30',
    'Low stock': 'low_stock',
    'Open receivables': 'dashboard_open_receivables',
    'Open payables': 'dashboard_open_payables',
    'High expense day': 'dashboard_high_expense_day',
    'Backup attention': 'dashboard_backup_attention',
    'Sync attention': 'dashboard_sync_attention',
    'Blocking conflicts': 'dashboard_blocking_conflicts',
    'Sync paused': 'dashboard_sync_paused',
    'Sync pending': 'sync_pending',
    'Sync ready': 'dashboard_sync_ready',
    'Backup running': 'dashboard_backup_running',
    'Backup needed': 'dashboard_backup_needed',
    'Backup ready': 'dashboard_backup_ready',
    'No successful backup yet': 'dashboard_no_successful_backup',
    'No pending local sync work': 'dashboard_no_pending_sync_work',
  };
  final key = exact[value];
  if (key != null) return tr.text(key);

  final translatedTemplate = tr.localizeEnglishMessage(value);
  if (translatedTemplate != null) return translatedTemplate;

  if (value.contains('Direct sync is not enabled for this store.')) {
    return value.replaceFirst(
      'Direct sync is not enabled for this store.',
      tr.text('direct_sync_not_enabled_for_store'),
    );
  }
  if (value.contains('Direct sync is not ready yet.')) {
    return value.replaceFirst(
      'Direct sync is not ready yet.',
      tr.text('direct_sync_not_ready_yet'),
    );
  }

  final lowStock = RegExp(r'^(\d+) product\(s\) need replenishment(?:: (.*))?$')
      .firstMatch(value);
  if (lowStock != null) {
    return tr.format('dashboard_products_need_replenishment', {
      'count': lowStock.group(1),
      'names': lowStock.group(2) ?? '',
    });
  }
  final receivables =
      RegExp(r'^(.+) across (\d+) invoice\(s\)$').firstMatch(value);
  if (receivables != null) {
    return tr.format('dashboard_receivables_summary', {
      'total': receivables.group(1),
      'count': receivables.group(2),
    });
  }
  final payables = RegExp(r'^(.+) across (\d+) bill\(s\)$').firstMatch(value);
  if (payables != null) {
    return tr.format('dashboard_payables_summary', {
      'total': payables.group(1),
      'count': payables.group(2),
    });
  }
  final highExpense =
      RegExp(r'^(.+) today vs (.+) daily average$').firstMatch(value);
  if (highExpense != null) {
    return tr.format('dashboard_high_expense_summary', {
      'today': highExpense.group(1),
      'average': highExpense.group(2),
    });
  }
  final conflicts =
      RegExp(r'^(\d+) blocking conflict\(s\) need review$').firstMatch(value);
  if (conflicts != null) {
    return tr.format(
        'dashboard_blocking_conflicts_summary', {'count': conflicts.group(1)});
  }
  final pendingChanges =
      RegExp(r'^(\d+) pending change\(s\)$').firstMatch(value);
  if (pendingChanges != null) {
    return tr.format(
        'dashboard_pending_changes', {'count': pendingChanges.group(1)});
  }
  final lastBackup = RegExp(r'^Last backup at (.+)$').firstMatch(value);
  if (lastBackup != null) {
    return tr.format('dashboard_last_backup_at', {'date': lastBackup.group(1)});
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
    'VPS API connection failed': 'direct_api_connection_failed',
    'VPS server Unreachable': 'direct_server_unreachable',
    'Host Offline': 'host_offline',
    'Sync Not Ready': 'sync_not_ready',
    'Host heartbeat failed': 'host_heartbeat_failed',
    'Direct push failed': 'direct_push_failed',
    'Direct pull failed': 'direct_pull_failed',
    'Direct sync failed': 'direct_sync_failed',
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

  final directPage =
      RegExp(r'^Pulling Direct changes page (\d+)\.\.\.$').firstMatch(value);
  if (directPage != null) {
    return tr
        .format('pulling_direct_changes_page', {'page': directPage.group(1)});
  }

  final progressMatch = RegExp(
          r'^(LAN|Direct|local) sync completed\. Pushed (\d+) change\(s\), pulled (\d+) change\(s\)\.$')
      .firstMatch(value);
  if (progressMatch != null) {
    final transport = progressMatch.group(1)!.toLowerCase();
    return tr.format('${transport}_sync_completed_details', {
      'pushed': progressMatch.group(2),
      'pulled': progressMatch.group(3),
    });
  }
  final prepareMatch = RegExp(r'^Preparing (.+) sync\.\.\.$').firstMatch(value);
  if (prepareMatch != null) {
    final transport = prepareMatch.group(1)!.toLowerCase();
    return tr.format('preparing_${transport}_sync', {});
  }
  final pullMatch =
      RegExp(r'^Pulling authoritative (.+) changes\.\.\.$').firstMatch(value);
  if (pullMatch != null) {
    final transport = pullMatch.group(1)!.toLowerCase();
    return tr.format('pulling_authoritative_${transport}_changes', {});
  }
  final failedMatch =
      RegExp(r'^(.+) pull failed\. Trying snapshot repair\.\.\.$')
          .firstMatch(value);
  if (failedMatch != null) {
    final transport = failedMatch.group(1)!.toLowerCase();
    return tr.format('${transport}_pull_failed_trying_snapshot_repair', {});
  }
  final syncDoneMatch = RegExp(r'^(.+) sync completed\.$').firstMatch(value);
  if (syncDoneMatch != null) {
    final transport = syncDoneMatch.group(1)!.toLowerCase();
    return tr.format('${transport}_sync_completed', {});
  }
  final snapshotChunkMatch =
      RegExp(r'^(.+): downloading chunk (\d+)/(\d+)\.\.\.$').firstMatch(value);
  if (snapshotChunkMatch != null) {
    return tr.format('snapshot_downloading_chunk', {
      'chunk': snapshotChunkMatch.group(2),
      'total': snapshotChunkMatch.group(3),
    });
  }
  final snapshotUploadMatch =
      RegExp(r'^(.+): uploading chunk (\d+)/(\d+)\.\.\.$').firstMatch(value);
  if (snapshotUploadMatch != null) {
    return tr.format('snapshot_uploading_chunk', {
      'chunk': snapshotUploadMatch.group(2),
      'total': snapshotUploadMatch.group(3),
    });
  }
  final snapshotRetryMatch =
      RegExp(r'^(.+) chunk (\d+)/(\d+) failed after retry: (.+)$')
          .firstMatch(value);
  if (snapshotRetryMatch != null) {
    return tr.format('snapshot_chunk_failed_after_retry', {
      'chunk': snapshotRetryMatch.group(2),
      'total': snapshotRetryMatch.group(3),
      'error': snapshotRetryMatch.group(4),
    });
  }
  final snapshotMismatchMatch =
      RegExp(r'^(.+) returned chunk (\d+), expected (\d+)\.$')
          .firstMatch(value);
  if (snapshotMismatchMatch != null) {
    return tr.format('snapshot_chunk_mismatch', {
      'chunk': snapshotMismatchMatch.group(2),
      'expected': snapshotMismatchMatch.group(3),
    });
  }

  if (value.startsWith(
      'Direct rebuild completed from a requested fresh Host snapshot.')) {
    return '${tr.text('direct_rebuild_completed_fresh')} ${value.substring('Direct rebuild completed from a requested fresh Host snapshot.'.length).trim()}'
        .trim();
  }
  if (value.startsWith(
      'Direct rebuild pulled a fresh Host snapshot, but local verification found problems:')) {
    return '${tr.text('direct_rebuild_pulled_but_issues')}: ${value.substring('Direct rebuild pulled a fresh Host snapshot, but local verification found problems:'.length).trim()}';
  }
  if (value.startsWith(
      'Direct rebuild requested a fresh Host snapshot, but no snapshot was pulled yet. Keep the Host online and retry.')) {
    return '${tr.text('direct_rebuild_no_snapshot_yet')} ${value.substring('Direct rebuild requested a fresh Host snapshot, but no snapshot was pulled yet. Keep the Host online and retry.'.length).trim()}'
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
  if (value.startsWith('Host direct push completed.')) {
    return value.replaceFirst(
        'Host direct push completed.', tr.text('host_direct_push_completed'));
  }
  if (value.startsWith('Client direct push completed.')) {
    return value.replaceFirst('Client direct push completed.',
        tr.text('client_direct_push_completed'));
  }
  if (value.startsWith('Direct pull stopped after')) {
    return value.replaceFirst(
        'Direct pull stopped after', tr.text('direct_pull_stopped_max_pages'));
  }
  if (value.startsWith('Direct pull completed.')) {
    return value.replaceFirst(
        'Direct pull completed.', tr.text('direct_pull_completed'));
  }
  if (value.startsWith('Direct sync completed.')) {
    return value.replaceFirst(
        'Direct sync completed.', tr.text('direct_sync_completed'));
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
        .replaceAll('Direct sync', 'مزامنة الاتصال السحابي')
        .replaceAll('VPS API', 'واجهة الاتصال السحابي')
        .replaceAll('Direct', 'اتصال سحابي')
        .replaceAll('LAN Sync', 'مزامنة الشبكة المحلية')
        .replaceAll('LAN', 'شبكة محلية')
        .replaceAll('Host', 'المضيف')
        .replaceAll('Client', 'العميل')
        .replaceAll('Store', 'المتجر');
    if (localized != value) return localized;
  }

  return message;
}
