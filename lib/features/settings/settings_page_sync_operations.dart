// ignore_for_file: invalid_use_of_protected_member
part of 'settings_page.dart';

extension _SyncOperations on _UnifiedSyncSettingsCardState {
  Future<void> _syncNow() => _run(() async {
        widget.store.requirePermission(AppPermission.syncManage);
        final identity = widget.store.appIdentity;
        final lan = LanSyncSettings.load();
        final hostLanEnabled = identity.isHost &&
            (_lanEnabledForHost || (lan.setupComplete && lan.isHost));
        final hostDirectEnabled = identity.isHost && _effectiveDirectEnabled;
        final messages = <String>[];
        if (identity.activeSyncTransportNormalized == 'direct') {
          final result =
              await UnifiedSyncFactory.directEngine(widget.store).syncNow(
            onProgress: (value, label) {
              if (mounted) {
                setState(() {
                  _status =
                      'Direct: ${localizeRuntimeMessage(label, tr)} ${(value * 100).round()}%';
                  _statusProgress = value;
                });
              }
            },
          );
          if (!result.ok) {
            throw StateError(localizeRuntimeMessage(result.message, tr));
          }
          messages.add('Direct: ${tr.text('sync_completed')}');
        } else if (hostDirectEnabled ||
            (!identity.isHost &&
                identity.activeSyncTransportNormalized == 'direct')) {
          final result = await _directEngine(enabled: true).syncNow(
            onProgress: (value, label) {
              if (mounted) {
                setState(() {
                  _status =
                      '${tr.text('connection_direct')}: ${localizeRuntimeMessage(label, tr)} ${(value * 100).round()}%';
                  _statusProgress = value;
                });
              }
            },
          );
          if (!result.ok) {
            throw StateError(localizeRuntimeMessage(result.message, tr));
          }
          messages.add(
              '${tr.text('connection_direct')}: ${tr.text('sync_completed')}');
        }
        if (identity.isClient &&
            identity.activeSyncTransportNormalized == 'lan') {
          final result = await _lanEngine().syncNow(
            onProgress: (value, label) {
              if (mounted) {
                setState(() {
                  _status =
                      '${tr.text('connection_lan')}: ${localizeRuntimeMessage(label, tr)} ${(value * 100).round()}%';
                  _statusProgress = value;
                });
              }
            },
          );
          if (!result.ok) {
            throw StateError(localizeRuntimeMessage(result.message, tr));
          }
          messages.add(
              '${tr.text('connection_lan')}: ${tr.text('sync_completed')}');
        } else if (hostLanEnabled) {
          messages.add(
              '${tr.text('connection_lan')}: ${tr.text('lan_host_running')}');
        }
        if (messages.isEmpty) {
          setState(() => _status = tr.text('no_sync_mode_enabled'));
        } else {
          setState(() {
            _status = messages.join(' • ');
            _statusProgress = 1.0;
          });
        }
      });

  String _shortDeviceLabel(String deviceId, {String name = ''}) {
    final trimmedName = name.trim();
    if (trimmedName.isNotEmpty) return trimmedName;
    final id = deviceId.trim();
    if (id.length <= 8) return id.isEmpty ? tr.text('unknown_client') : id;
    final prefix = id.substring(0, 4);
    final suffix = id.substring(id.length - 4);
    return '${tr.text('client_label')} $prefix…$suffix';
  }

  String _formatShortDateTime(DateTime? value) {
    if (value == null) return tr.text('never');
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  String _peerSyncStatus(HostPeerSyncState? peer) {
    if (peer == null) return tr.text('connection_state_not_configured');
    if (peer.lastAckSequence > 0 ||
        peer.lastAckCursor != null ||
        peer.lastAppliedHostCursor != null) {
      return tr.text('synced');
    }
    return tr.text('sync_pending');
  }

  Future<void> _testPairedClientConnections() => _run(() async {
        setState(() {
          _status = tr.text('testing_paired_clients');
          _statusProgress = 0.15;
        });
        final identity = widget.store.appIdentity;
        final lan = LanSyncSettings.load();
        final direct = VpsControlPlaneSettings.load();
        final peerStates = <String, HostPeerSyncState>{
          for (final state in SyncDeviceStateStore.loadPeerStates())
            state.deviceId: state,
        };
        var controlPlaneReachable = false;
        var directProblem = '';
        var directDevices = const <DirectDeviceStatus>[];
        if (_effectiveDirectEnabled && direct.isConfigured) {
          final directConnection =
              await _directEngine(enabled: true).testConnection();
          controlPlaneReachable = directConnection.ok;
          directProblem = directConnection.ok ? '' : directConnection.message;
          if (controlPlaneReachable) {
            try {
              directDevices = await _controlPlaneService().listDevices(direct);
            } catch (error) {
              controlPlaneReachable = false;
              directProblem = error.toString();
            }
          }
        }
        final directById = <String, DirectDeviceStatus>{
          for (final device in directDevices)
            if (device.deviceId.trim().isNotEmpty)
              device.deviceId.trim(): device,
        };
        // Phase 3: Host Registry is the single source of truth for
        // Monitoring/Test Connection device discovery. Direct devices and peer
        // states are used only as status overlays for registered Clients.
        final registryById = <String, HostRegistryDevice>{
          for (final entry in lan.hostRegistry.entries)
            if (entry.key.trim().isNotEmpty && entry.value.isActive)
              entry.key.trim(): entry.value,
        };
        final ids = registryById.keys.toSet()..remove(identity.deviceId);

        if (ids.isEmpty) {
          setState(() {
            _status = tr.text('no_paired_clients_found');
            _statusProgress = 1.0;
          });
          return;
        }

        final lines = <String>[];
        var ready = 0;
        for (final id in ids) {
          final registryDevice = registryById[id];
          final directDevice = directById[id];
          final peer = peerStates[id];
          final lanToken = lan.pairedDevices[id]?.trim().isNotEmpty == true
              ? lan.pairedDevices[id]!.trim()
              : ((registryDevice?.source != 'direct_pairing_claim' &&
                      registryDevice?.deviceToken.trim().isNotEmpty == true)
                  ? registryDevice!.deviceToken.trim()
                  : '');
          final parts = <String>[];
          if (directDevice != null) {
            if (directDevice.revoked) {
              parts.add(tr.text('direct_unauthorized'));
            } else if (directDevice.online || directDevice.isOnline) {
              parts.add(tr.text('direct_active'));
            } else {
              parts.add(tr.text('direct_pending'));
            }
          } else if (_effectiveDirectEnabled && direct.isConfigured) {
            parts.add(controlPlaneReachable
                ? tr.text('direct_not_configured')
                : '${tr.text('direct_error')}${directProblem.isEmpty ? '' : ': $directProblem'}');
          }
          if (lanToken.isNotEmpty) {
            parts.add(tr.text('lan_active'));
          } else if (_lanEnabledForHost || (lan.setupComplete && lan.isHost)) {
            parts.add(tr.text('lan_not_configured'));
          }
          final peerSynced = peer != null &&
              (peer.lastAckSequence > 0 ||
                  peer.lastAckCursor != null ||
                  peer.lastAppliedHostCursor != null);
          final syncStatus = _peerSyncStatus(peer);
          if (peerSynced &&
              ((directDevice != null &&
                      !directDevice.revoked &&
                      (directDevice.online || directDevice.isOnline)) ||
                  lanToken.isNotEmpty)) {
            ready++;
          }
          parts.add(syncStatus);
          parts.add(
              '${tr.text('last_sync')}: ${_formatShortDateTime(peer?.lastAckCursor ?? peer?.lastAppliedHostCursor ?? peer?.updatedAt)}');
          final label = _shortDeviceLabel(id,
              name:
                  registryDevice?.deviceName ?? directDevice?.deviceName ?? '');
          lines.add('$label → ${parts.join(' | ')}');
        }

        final total = ids.length;
        setState(() {
          _status = '${tr.format('paired_clients_ready', {
                'ready': ready,
                'total': total
              })} • ${lines.join(' • ')}';
          _statusProgress = 1.0;
        });
      });

  // ignore: unused_element

  Future<void> _testDirectConnection() => _run(() async {
        setState(() {
          _status = tr.text('testing_direct_connection');
          _statusProgress = 0.25;
        });
        final result = await UnifiedSyncFactory.directEngine(widget.store)
            .testConnection();
        if (!result.ok) {
          throw StateError(localizeRuntimeMessage(result.message, tr));
        }
        setState(() {
          _status = 'Direct: ${localizeRuntimeMessage(result.message, tr)}';
          _statusProgress = 1.0;
        });
      });

  Future<void> _testHostConnection() => _run(() async {
        final lan = LanSyncSettings.load();
        final host = _lanHostController.text.trim().isEmpty
            ? lan.host
            : _lanHostController.text.trim();
        setState(() {
          _status = tr.text('testing_lan_connection');
          _statusProgress = 0.25;
        });
        final result =
            await _lanEngine(lan.copyWith(host: host, port: _lanPort))
                .testConnection();
        if (!result.ok) {
          throw StateError(localizeRuntimeMessage(result.message, tr));
        }
        setState(() {
          _status = '${tr.text('connection_lan')}: ${tr.text('connection_ok')}';
          _statusProgress = 1.0;
        });
      });
}
