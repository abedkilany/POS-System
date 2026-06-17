import {
  sql,
  assertAccountOrDevice,
  assertDeviceAllowed,
  assertStoreAllowed,
  ensureDeviceAuthColumns,
  sendError,
} from '../_db.js';

function asIso(value) {
  if (!value) return null;
  return value instanceof Date ? value.toISOString() : new Date(value).toISOString();
}

function safeIso(value) {
  if (!value) return null;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return null;
  return date.toISOString();
}

function normalizeTransport(value) {
  const v = String(value || '').trim().toLowerCase();
  return v === 'lan' || v === 'cloud' ? v : '';
}

async function ensureDeviceTable() {
  await sql`
    create table if not exists store_devices (
      store_id text not null,
      branch_id text not null default 'main',
      device_id text not null,
      device_name text default '',
      platform text default '',
      role text default '',
      transport text default '',
      app_version text default '',
      store_epoch integer not null default 1,
      revoked boolean not null default false,
      suspended boolean not null default false,
      wipe_pending boolean not null default false,
      wipe_requested_at timestamptz,
      device_token text default '',
      host_device_id text default '',
      active_transport text default '',
      last_sync_transport text default '',
      last_applied_cursor timestamptz,
      last_ack_cursor timestamptz,
      last_applied_sequence bigint not null default 0,
      last_ack_sequence bigint not null default 0,
      last_ack_at timestamptz,
      online boolean not null default false,
      last_seen_at timestamptz not null default now(),
      updated_at timestamptz not null default now(),
      primary key (store_id, branch_id, device_id)
    )
  `;
  await ensureDeviceAuthColumns();
  await sql`alter table store_devices add column if not exists host_device_id text default ''`;
  await sql`
    create index if not exists idx_store_devices_latest
    on store_devices (store_id, branch_id, last_seen_at desc)
  `;
}

function rowToDevice(row) {
  return {
    storeId: row.store_id,
    branchId: row.branch_id,
    deviceId: row.device_id,
    deviceName: row.device_name || '',
    platform: row.platform || '',
    role: row.role || '',
    transport: row.transport || '',
    activeTransport: row.active_transport || row.transport || '',
    lastSyncTransport: row.last_sync_transport || row.transport || '',
    appVersion: row.app_version || '',
    hostDeviceId: row.host_device_id || '',
    storeEpoch: row.store_epoch || 1,
    revoked: row.revoked === true,
    suspended: row.suspended === true,
    wipePending: row.wipe_pending === true,
    online: row.online === true,
    lastAppliedCursor: asIso(row.last_applied_cursor),
    lastAckCursor: asIso(row.last_ack_cursor),
    lastAppliedSequence: Number(row.last_applied_sequence || 0),
    lastAckSequence: Number(row.last_ack_sequence || 0),
    lastAckAt: asIso(row.last_ack_at),
    lastSeenAt: asIso(row.last_seen_at),
  };
}

export default async function handler(req, res) {
  try {
    await ensureDeviceTable();

    if (req.method === 'POST') {
      const body = req.body || {};
      const storeId = String(body.storeId || body.store_id || '').trim();
      const branchId = String(body.branchId || body.branch_id || 'main').trim() || 'main';
      const deviceId = String(body.deviceId || body.device_id || '').trim();
      if (!storeId) return res.status(400).json({ ok: false, error: 'storeId is required.' });
      if (!deviceId) return res.status(400).json({ ok: false, error: 'deviceId is required.' });
      assertStoreAllowed(storeId);

      const deviceName = String(body.deviceName || body.device_name || '').trim();
      const platform = String(body.platform || '').trim();
      const role = String(body.role || '').trim();
      const transport = normalizeTransport(body.transport) || String(body.transport || '').trim();
      const activeTransport = normalizeTransport(body.activeTransport || body.active_transport) || transport;
      const lastSyncTransport = normalizeTransport(body.lastSyncTransport || body.last_sync_transport) || activeTransport || transport;
      const appVersion = String(body.appVersion || body.app_version || '').trim();
      const hostDeviceId = String(body.hostDeviceId || body.host_device_id || '').trim();
      const deviceToken = String(body.deviceToken || body.device_token || req.headers['x-device-token'] || '').trim();
      const storeEpoch = Number(body.storeEpoch || body.store_epoch || 1);
      const lastAppliedCursor = safeIso(body.lastAppliedCursor || body.last_applied_cursor);
      const lastAckCursor = safeIso(body.lastAckCursor || body.last_ack_cursor || lastAppliedCursor);
      const lastAppliedSequence = Math.max(Number(body.lastAppliedSequence || body.last_applied_sequence || 0), 0);
      const lastAckSequence = Math.max(Number(body.lastAckSequence || body.last_ack_sequence || lastAppliedSequence || 0), 0);

      // Hosts can register with their account session. Paired Clients update
      // only themselves with their device-scoped token.
      let usedDeviceAuth = false;
      try {
        await assertDeviceAllowed(req, {
          storeId,
          branchId,
          allowedRoles: ['host', 'client'],
          allowedTransports: ['cloud'],
          force: true,
        });
        usedDeviceAuth = true;
      } catch (deviceError) {
        if (String(role || '').trim() !== 'host' || activeTransport !== 'cloud') {
          throw deviceError;
        }
        await assertAccountOrDevice(req, {
          storeId,
          branchId,
          allowedRoles: ['host'],
          allowedTransports: ['cloud'],
        });
      }
      if (usedDeviceAuth) {
        const headerDeviceId = String(req.headers['x-device-id'] || req.headers['X-Device-Id'] || '').trim();
        if (headerDeviceId !== deviceId) {
          return res.status(403).json({ ok: false, error: 'Device credentials cannot update another device.' });
        }
      }

      const rows = await sql`
        insert into store_devices (
          store_id, branch_id, device_id, device_name, platform, role, transport, active_transport, last_sync_transport,
          app_version, store_epoch, device_token, host_device_id, last_applied_cursor, last_ack_cursor, last_applied_sequence, last_ack_sequence, last_ack_at, online, last_seen_at, updated_at
        ) values (
          ${storeId}, ${branchId}, ${deviceId}, ${deviceName}, ${platform}, ${role}, ${transport}, ${activeTransport}, ${lastSyncTransport},
          ${appVersion}, ${storeEpoch}, ${deviceToken}, ${hostDeviceId}, ${lastAppliedCursor}::timestamptz, ${lastAckCursor}::timestamptz, ${lastAppliedSequence}, ${lastAckSequence}, now(), true, now(), now()
        )
        on conflict (store_id, branch_id, device_id) do update set
          device_name = excluded.device_name,
          platform = excluded.platform,
          role = excluded.role,
          transport = case when excluded.transport <> '' then excluded.transport else store_devices.transport end,
          active_transport = case when excluded.active_transport <> '' then excluded.active_transport else store_devices.active_transport end,
          last_sync_transport = case when excluded.last_sync_transport <> '' then excluded.last_sync_transport else store_devices.last_sync_transport end,
          app_version = excluded.app_version,
          store_epoch = greatest(store_devices.store_epoch, excluded.store_epoch),
          device_token = case when excluded.device_token <> '' then excluded.device_token else store_devices.device_token end,
          host_device_id = case when excluded.host_device_id <> '' then excluded.host_device_id else store_devices.host_device_id end,
          last_applied_cursor = greatest(coalesce(store_devices.last_applied_cursor, 'epoch'::timestamptz), coalesce(excluded.last_applied_cursor, store_devices.last_applied_cursor, 'epoch'::timestamptz)),
          last_ack_cursor = greatest(coalesce(store_devices.last_ack_cursor, 'epoch'::timestamptz), coalesce(excluded.last_ack_cursor, store_devices.last_ack_cursor, 'epoch'::timestamptz)),
          last_applied_sequence = greatest(coalesce(store_devices.last_applied_sequence, 0), coalesce(excluded.last_applied_sequence, 0)),
          last_ack_sequence = greatest(coalesce(store_devices.last_ack_sequence, 0), coalesce(excluded.last_ack_sequence, 0)),
          last_ack_at = case when excluded.last_ack_cursor is not null then now() else store_devices.last_ack_at end,
          online = true,
          last_seen_at = now(),
          updated_at = now()
        returning store_id, branch_id, device_id, device_name, platform, role, transport, active_transport, last_sync_transport,
          app_version, host_device_id, store_epoch, revoked, suspended, wipe_pending, online, last_applied_cursor, last_ack_cursor, last_applied_sequence, last_ack_sequence, last_ack_at, last_seen_at
      `;
      return res.status(200).json({ ok: true, device: rowToDevice(rows[0]) });
    }

    if (req.method === 'GET') {
      const storeId = String(req.query.store_id || req.query.storeId || '').trim();
      const branchId = String(req.query.branch_id || req.query.branchId || 'main').trim() || 'main';
      if (!storeId) return res.status(400).json({ ok: false, error: 'store_id is required.' });
      assertStoreAllowed(storeId);
      await assertAccountOrDevice(req, { storeId, branchId, allowedRoles: ['host'], allowedTransports: ['cloud'] });
      const rows = await sql`
        select store_id, branch_id, device_id, device_name, platform, role, transport, active_transport, last_sync_transport,
          app_version, host_device_id, store_epoch, revoked, suspended, wipe_pending, online, last_applied_cursor, last_ack_cursor, last_applied_sequence, last_ack_sequence, last_ack_at, last_seen_at
        from store_devices
        where store_id = ${storeId}
          and branch_id = ${branchId}
        order by last_seen_at desc
        limit 100
      `;
      return res.status(200).json({ ok: true, devices: rows.map(rowToDevice), serverTime: new Date().toISOString() });
    }

    return res.status(405).json({ ok: false, error: 'Method not allowed' });
  } catch (error) {
    sendError(res, error);
  }
}
