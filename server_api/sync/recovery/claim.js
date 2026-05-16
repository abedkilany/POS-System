import { randomBytes, createHash, timingSafeEqual } from 'crypto';
import { sql, assertStoreAllowed, sendError } from '../../_db.js';

function asIso(value) {
  return value instanceof Date ? value.toISOString() : new Date(value).toISOString();
}

function normalize(value) {
  return String(value || '').trim().toUpperCase();
}

function hashRecoveryKey(value) {
  return createHash('sha256').update(normalize(value), 'utf8').digest('hex');
}

function safeEqualHex(a, b) {
  const left = Buffer.from(String(a || ''), 'hex');
  const right = Buffer.from(String(b || ''), 'hex');
  return left.length === right.length && timingSafeEqual(left, right);
}

function makeDeviceToken() {
  return `device_${Date.now()}_${randomBytes(24).toString('base64url')}`;
}

async function ensureRecoveryTables() {
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
  await sql`
    create table if not exists store_devices (
      store_id text not null,
      branch_id text not null default 'main',
      device_id text not null,
      device_name text default '',
      platform text default '',
      app_version text default '',
      role text not null default 'client',
      transport text not null default 'cloud',
      store_epoch integer not null default 1,
      device_token text default '',
      revoked boolean not null default false,
      last_seen_at timestamptz not null default now(),
      updated_at timestamptz not null default now(),
      primary key (store_id, branch_id, device_id)
    )
  `;
}

export default async function handler(req, res) {
  try {
    await ensureRecoveryTables();
    if (req.method !== 'POST') return res.status(405).json({ ok: false, error: 'Method not allowed' });

    const body = req.body || {};
    const storeId = normalize(body.storeId || body.store_id);
    const requestedBranchId = normalize(body.branchId || body.branch_id);
    const branchId = requestedBranchId || '';
    const recoveryKey = normalize(body.recoveryKey || body.recovery_key);
    const deviceId = String(body.deviceId || body.device_id || '').trim();
    const deviceName = String(body.deviceName || body.device_name || '').trim();
    const platform = String(body.platform || '').trim();
    const appVersion = String(body.appVersion || body.app_version || '').trim();

    if (!storeId || !storeId.startsWith('ST-')) return res.status(400).json({ ok: false, error: 'A valid Store ID is required.' });
    if (!recoveryKey) return res.status(400).json({ ok: false, error: 'Recovery Key is required.' });
    if (!deviceId) return res.status(400).json({ ok: false, error: 'deviceId is required.' });
    assertStoreAllowed(storeId);

    const rows = branchId
      ? await sql`
          select store_id, branch_id, recovery_key_hash, latest_host_device_id, cloud_tenant_id
          from store_recovery_keys
          where store_id = ${storeId}
            and branch_id = ${branchId}
          limit 1
        `
      : await sql`
          select store_id, branch_id, recovery_key_hash, latest_host_device_id, cloud_tenant_id
          from store_recovery_keys
          where store_id = ${storeId}
          order by updated_at desc
          limit 1
        `;
    if (!rows.length) {
      return res.status(404).json({ ok: false, error: 'No recovery record was found for this Store ID and Branch ID. A Host must publish its Recovery Key to Cloud first.' });
    }

    const recoveredBranchId = rows[0].branch_id || 'main';
    const expectedHash = rows[0].recovery_key_hash || '';
    if (!safeEqualHex(expectedHash, hashRecoveryKey(recoveryKey))) {
      return res.status(403).json({ ok: false, error: 'Invalid Recovery Key for this Store ID.' });
    }

    const deviceToken = makeDeviceToken();
    const cloudTenantId = rows[0].cloud_tenant_id || '';
    await sql`
      insert into store_devices (
        store_id, branch_id, device_id, device_name, platform, app_version, role, transport, device_token, revoked, last_seen_at, updated_at
      ) values (
        ${storeId}, ${recoveredBranchId}, ${deviceId}, ${deviceName}, ${platform}, ${appVersion}, 'host', 'cloud', ${deviceToken}, false, now(), now()
      )
      on conflict (store_id, branch_id, device_id) do update set
        device_name = excluded.device_name,
        platform = excluded.platform,
        app_version = excluded.app_version,
        role = 'host',
        transport = 'cloud',
        device_token = excluded.device_token,
        revoked = false,
        last_seen_at = now(),
        updated_at = now()
    `;
    await sql`
      update store_recovery_keys
      set latest_host_device_id = ${deviceId}, updated_at = now()
      where store_id = ${storeId} and branch_id = ${recoveredBranchId}
    `;

    return res.status(200).json({
      ok: true,
      storeId,
      branchId: recoveredBranchId,
      hostDeviceId: deviceId,
      deviceToken,
      cloudTenantId,
      recoveredAt: asIso(new Date()),
    });
  } catch (error) {
    sendError(res, error);
  }
}
