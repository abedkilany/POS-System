import { createHash } from 'crypto';
import {
  sql,
  assertSyncToken,
  assertAccountStoreToken,
  assertCloudSyncEnabled,
  assertStoreAllowed,
  assertDeviceAllowed,
  sendError,
} from '../_db.js';

function asIso(value) {
  return value instanceof Date ? value.toISOString() : new Date(value).toISOString();
}

function normalizeRecoveryKey(value) {
  return String(value || '').trim().toUpperCase();
}

function hashRecoveryKey(value) {
  return createHash('sha256')
    .update(normalizeRecoveryKey(value), 'utf8')
    .digest('hex');
}

async function ensureHeartbeatTable() {
  await sql`
    create table if not exists store_host_heartbeats (
      store_id text not null,
      branch_id text not null default 'main',
      host_device_id text not null,
      host_device_name text default '',
      platform text default '',
      app_version text default '',
      sync_mode text default '',
      last_seen_at timestamptz not null default now(),
      updated_at timestamptz not null default now(),
      primary key (store_id, branch_id, host_device_id)
    )
  `;

  await sql`
    create index if not exists idx_store_host_heartbeats_latest
    on store_host_heartbeats (store_id, branch_id, last_seen_at desc)
  `;

  await sql`
    create table if not exists store_recovery_keys (
      store_id text not null,
      branch_id text not null default 'main',
      recovery_key_hash text not null,
      latest_host_device_id text default '',
      cloud_tenant_id text default '',
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now(),
      primary key (store_id, branch_id)
    )
  `;
}

export default async function handler(req, res) {
  try {
    await ensureHeartbeatTable();

    if (req.method === 'POST') {
      const body = req.body || {};
      const storeId = String(body.storeId || body.store_id || '').trim();
      const branchId = String(body.branchId || body.branch_id || 'main').trim() || 'main';
      const hostDeviceId = String(body.hostDeviceId || body.host_device_id || body.deviceId || '').trim();

      if (!storeId) {
        return res.status(400).json({ ok: false, error: 'storeId is required.' });
      }

      if (!hostDeviceId) {
        return res.status(400).json({ ok: false, error: 'hostDeviceId is required.' });
      }

      assertStoreAllowed(storeId);

      try {
        assertSyncToken(req);
        await assertCloudSyncEnabled(storeId);
      } catch (_) {
        try {
          await assertDeviceAllowed(req, {
            storeId,
            branchId,
            allowedRoles: ['host'],
            allowedTransports: ['cloud'],
            force: true,
          });
          await assertCloudSyncEnabled(storeId);
        } catch (deviceError) {
          assertAccountStoreToken(req, { storeId, branchId });
          await assertCloudSyncEnabled(storeId);
        }
      }

      const hostDeviceName = String(body.hostDeviceName || body.host_device_name || '').trim();
      const platform = String(body.platform || '').trim();
      const appVersion = String(body.appVersion || body.app_version || '').trim();
      const syncMode = String(body.syncMode || body.sync_mode || '').trim();
      const recoveryKey = normalizeRecoveryKey(body.recoveryKey || body.recovery_key);

      const activeRows = await sql`
        select host_device_id, host_device_name, last_seen_at
        from store_host_heartbeats
        where store_id = ${storeId}
          and branch_id = ${branchId}
          and host_device_id <> ${hostDeviceId}
          and last_seen_at > now() - interval '2 minutes'
        order by last_seen_at desc
        limit 1
      `;

      if (activeRows.length) {
        return res.status(409).json({
          ok: false,
          error:
            'Another active Host is already connected for this store. Change this device to CLIENT or turn off the old Host first.',
          activeHostDeviceId: activeRows[0].host_device_id,
          activeHostDeviceName: activeRows[0].host_device_name || '',
          activeHostLastSeenAt: asIso(activeRows[0].last_seen_at),
        });
      }

      const rows = await sql`
        insert into store_host_heartbeats (
          store_id,
          branch_id,
          host_device_id,
          host_device_name,
          platform,
          app_version,
          sync_mode,
          last_seen_at,
          updated_at
        ) values (
          ${storeId},
          ${branchId},
          ${hostDeviceId},
          ${hostDeviceName},
          ${platform},
          ${appVersion},
          ${syncMode},
          now(),
          now()
        )
        on conflict (store_id, branch_id, host_device_id) do update set
          host_device_name = excluded.host_device_name,
          platform = excluded.platform,
          app_version = excluded.app_version,
          sync_mode = excluded.sync_mode,
          last_seen_at = now(),
          updated_at = now()
        returning
          store_id,
          branch_id,
          host_device_id,
          host_device_name,
          platform,
          app_version,
          sync_mode,
          last_seen_at
      `;

      if (recoveryKey) {
        await sql`
          insert into store_recovery_keys (
            store_id,
            branch_id,
            recovery_key_hash,
            latest_host_device_id,
            updated_at
          )
          values (
            ${storeId},
            ${branchId},
            ${hashRecoveryKey(recoveryKey)},
            ${hostDeviceId},
            now()
          )
          on conflict (store_id, branch_id) do update set
            recovery_key_hash = excluded.recovery_key_hash,
            latest_host_device_id = excluded.latest_host_device_id,
            updated_at = now()
        `;
      }

      const row = rows[0];

      return res.status(200).json({
        ok: true,
        storeId: row.store_id,
        branchId: row.branch_id,
        hostDeviceId: row.host_device_id,
        hostDeviceName: row.host_device_name || '',
        platform: row.platform || '',
        appVersion: row.app_version || '',
        syncMode: row.sync_mode || '',
        lastSeenAt: asIso(row.last_seen_at),
      });
    }

    if (req.method === 'GET') {
      const storeId = String(req.query.store_id || req.query.storeId || '').trim();
      const branchId = String(req.query.branch_id || req.query.branchId || 'main').trim() || 'main';

      if (!storeId) {
        return res.status(400).json({ ok: false, error: 'store_id is required.' });
      }

      assertStoreAllowed(storeId);

      await assertSyncTokenOrDevice(req, {
        storeId,
        branchId,
        allowedRoles: ['host', 'client'],
        allowedTransports: ['cloud', 'lan'],
      });

      const rows = await sql`
        select
          store_id,
          branch_id,
          host_device_id,
          host_device_name,
          platform,
          app_version,
          sync_mode,
          last_seen_at
        from store_host_heartbeats
        where store_id = ${storeId}
          and branch_id = ${branchId}
        order by last_seen_at desc
        limit 1
      `;

      if (!rows.length) {
        return res.status(200).json({
          ok: true,
          found: false,
          lastSeenAt: null,
          serverTime: new Date().toISOString(),
        });
      }

      const row = rows[0];

      return res.status(200).json({
        ok: true,
        found: true,
        storeId: row.store_id,
        branchId: row.branch_id,
        hostDeviceId: row.host_device_id,
        hostDeviceName: row.host_device_name || '',
        platform: row.platform || '',
        appVersion: row.app_version || '',
        syncMode: row.sync_mode || '',
        lastSeenAt: asIso(row.last_seen_at),
        serverTime: new Date().toISOString(),
      });
    }

    return res.status(405).json({ ok: false, error: 'Method not allowed' });
  } catch (error) {
    sendError(res, error);
  }
}
