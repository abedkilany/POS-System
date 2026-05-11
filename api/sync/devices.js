import { sql, assertSyncToken, assertStoreAllowed, sendError } from '../_db.js';

function asIso(value) {
  return value instanceof Date ? value.toISOString() : new Date(value).toISOString();
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
      last_seen_at timestamptz not null default now(),
      updated_at timestamptz not null default now(),
      primary key (store_id, branch_id, device_id)
    )
  `;
  await sql`
    create index if not exists idx_store_devices_latest
    on store_devices (store_id, branch_id, last_seen_at desc)
  `;
}

export default async function handler(req, res) {
  try {
    assertSyncToken(req);
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
      const transport = String(body.transport || '').trim();
      const appVersion = String(body.appVersion || body.app_version || '').trim();
      const storeEpoch = Number(body.storeEpoch || body.store_epoch || 1);

      const rows = await sql`
        insert into store_devices (
          store_id, branch_id, device_id, device_name, platform, role, transport, app_version, store_epoch, last_seen_at, updated_at
        ) values (
          ${storeId}, ${branchId}, ${deviceId}, ${deviceName}, ${platform}, ${role}, ${transport}, ${appVersion}, ${storeEpoch}, now(), now()
        )
        on conflict (store_id, branch_id, device_id) do update set
          device_name = excluded.device_name,
          platform = excluded.platform,
          role = excluded.role,
          transport = excluded.transport,
          app_version = excluded.app_version,
          store_epoch = greatest(store_devices.store_epoch, excluded.store_epoch),
          last_seen_at = now(),
          updated_at = now()
        returning store_id, branch_id, device_id, device_name, platform, role, transport, app_version, store_epoch, revoked, last_seen_at
      `;
      const row = rows[0];
      return res.status(200).json({
        ok: true,
        device: {
          storeId: row.store_id,
          branchId: row.branch_id,
          deviceId: row.device_id,
          deviceName: row.device_name || '',
          platform: row.platform || '',
          role: row.role || '',
          transport: row.transport || '',
          appVersion: row.app_version || '',
          storeEpoch: row.store_epoch || 1,
          revoked: row.revoked === true,
          lastSeenAt: asIso(row.last_seen_at),
        },
      });
    }

    if (req.method === 'GET') {
      const storeId = String(req.query.store_id || req.query.storeId || '').trim();
      const branchId = String(req.query.branch_id || req.query.branchId || 'main').trim() || 'main';
      if (!storeId) return res.status(400).json({ ok: false, error: 'store_id is required.' });
      assertStoreAllowed(storeId);
      const rows = await sql`
        select store_id, branch_id, device_id, device_name, platform, role, transport, app_version, store_epoch, revoked, last_seen_at
        from store_devices
        where store_id = ${storeId}
          and branch_id = ${branchId}
        order by last_seen_at desc
        limit 100
      `;
      return res.status(200).json({
        ok: true,
        devices: rows.map((row) => ({
          storeId: row.store_id,
          branchId: row.branch_id,
          deviceId: row.device_id,
          deviceName: row.device_name || '',
          platform: row.platform || '',
          role: row.role || '',
          transport: row.transport || '',
          appVersion: row.app_version || '',
          storeEpoch: row.store_epoch || 1,
          revoked: row.revoked === true,
          lastSeenAt: asIso(row.last_seen_at),
        })),
        serverTime: new Date().toISOString(),
      });
    }

    return res.status(405).json({ ok: false, error: 'Method not allowed' });
  } catch (error) {
    sendError(res, error);
  }
}
