import crypto from 'crypto';
import { neon } from '@neondatabase/serverless';
import pg from 'pg';

if (!process.env.DATABASE_URL) {
  throw new Error('DATABASE_URL is not configured.');
}

const databaseUrl = process.env.DATABASE_URL;
const isLocalDatabase =
  databaseUrl.includes('@localhost') ||
  databaseUrl.includes('@127.0.0.1');

let sql;

if (isLocalDatabase) {
  const { Pool } = pg;
  const pool = new Pool({ connectionString: databaseUrl });

  sql = async (strings, ...values) => {
    let text = '';
    for (let i = 0; i < strings.length; i++) {
      text += strings[i];
      if (i < values.length) text += `$${i + 1}`;
    }
    const result = await pool.query(text, values);
    return result.rows;
  };
} else {
  sql = neon(databaseUrl);
}

export { sql };

export function assertStoreAllowed(storeId) {
  const allowed = (process.env.CLOUD_SYNC_STORE_ID || '').trim();
  if (allowed && storeId !== allowed) {
    const err = new Error('This deployment is not allowed to access the requested store_id.');
    err.statusCode = 403;
    throw err;
  }
}

function accountSecret() {
  const configuredSecret =
    process.env.ACCOUNT_JWT_SECRET || process.env.ADMIN_JWT_SECRET || '';
  if (configuredSecret.trim()) return configuredSecret;
  if ((process.env.NODE_ENV || '').toLowerCase() === 'production') {
    throw new Error(
      'ACCOUNT_JWT_SECRET or ADMIN_JWT_SECRET must be configured in production.',
    );
  }
  return process.env.DATABASE_URL || 'ventio-platform-admin-secret';
}

export function verifyAccountToken(token) {
  const secret = accountSecret();
  if (!secret) return null;
  const parts = String(token || '').split('.');
  if (parts.length !== 2) return null;
  const [payloadB64, signature] = parts;
  const expected = crypto.createHmac('sha256', secret).update(payloadB64).digest('base64url');
  try {
    const a = Buffer.from(signature);
    const b = Buffer.from(expected);
    if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return null;
  } catch (_) {
    return null;
  }
  try {
    const payload = JSON.parse(Buffer.from(payloadB64, 'base64url').toString('utf8'));
    if (payload?.type !== 'store_account') return null;
    if (Number(payload?.exp || 0) < Math.floor(Date.now() / 1000)) return null;
    return payload;
  } catch (_) {
    return null;
  }
}

export function accountTokenFromRequest(req) {
  const header = req.headers.authorization || req.headers.Authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7).trim() : '';
  return verifyAccountToken(token);
}

export function assertAccountStoreToken(req, { storeId, branchId = '' } = {}) {
  const payload = accountTokenFromRequest(req);
  if (!payload) {
    const err = new Error('Invalid or missing account session.');
    err.statusCode = 401;
    throw err;
  }
  if (storeId && String(payload.storeId || '') !== String(storeId)) {
    const err = new Error('This account is not allowed to access the requested store_id.');
    err.statusCode = 403;
    throw err;
  }
  if (branchId && String(payload.branchId || '') !== String(branchId)) {
    const err = new Error('This account is not allowed to access the requested branch_id.');
    err.statusCode = 403;
    throw err;
  }
  return payload;
}

export async function ensureCloudSyncAccessColumn() {
  await sql`alter table app_stores add column if not exists cloud_sync_enabled boolean not null default false`;
}

export async function assertCloudSyncEnabled(storeId) {
  await ensureCloudSyncAccessColumn();
  const rows = await sql`
    select cloud_sync_enabled
    from app_stores
    where id = ${storeId}
    limit 1
  `;
  if (!rows.length || rows[0].cloud_sync_enabled !== true) {
    const err = new Error('Cloud Sync is not enabled for this store.');
    err.statusCode = 403;
    throw err;
  }
}

async function ensureStoreDevicesTableForLimits() {
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
}

export async function getClientDeviceLimitStatus(storeId, { excludeDeviceId = '' } = {}) {
  await sql`
    create table if not exists app_subscriptions (
      id text primary key,
      store_id text not null,
      plan text not null default 'trial',
      status text not null default 'trial',
      trial_ends_at timestamptz,
      devices_limit integer not null default 2,
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now()
    )
  `;
  await ensureStoreDevicesTableForLimits();
  await ensureDeviceAuthColumns();
  const limitRows = await sql`
    select coalesce(max(devices_limit), 0)::int as devices_limit
    from app_subscriptions
    where store_id = ${storeId}
  `;
  const allowed = Math.max(Number(limitRows[0]?.devices_limit || 0), 0);
  const linkedRows = excludeDeviceId
    ? await sql`
        select count(*)::int as linked
        from store_devices
        where store_id = ${storeId}
          and role = 'client'
          and revoked = false
          and device_id <> ${excludeDeviceId}
      `
    : await sql`
        select count(*)::int as linked
        from store_devices
        where store_id = ${storeId}
          and role = 'client'
          and revoked = false
      `;
  const linked = Math.max(Number(linkedRows[0]?.linked || 0), 0);
  return {
    allowed,
    linked,
    available: Math.max(allowed - linked, 0),
    limitReached: linked >= allowed,
  };
}

export async function assertClientDeviceSlotAvailable(storeId, { excludeDeviceId = '' } = {}) {
  const status = await getClientDeviceLimitStatus(storeId, { excludeDeviceId });
  if (status.limitReached) {
    const err = new Error('Device limit reached.');
    err.statusCode = 403;
    err.details = status;
    throw err;
  }
  return status;
}

export async function ensureDeviceAuthColumns() {
  await sql`alter table store_devices add column if not exists device_token text default ''`;
  await sql`alter table store_devices add column if not exists host_device_id text default ''`;
  await sql`alter table store_devices add column if not exists revoked boolean not null default false`;
  await sql`alter table store_devices add column if not exists suspended boolean not null default false`;
  await sql`alter table store_devices add column if not exists wipe_pending boolean not null default false`;
  await sql`alter table store_devices add column if not exists wipe_requested_at timestamptz`;
  // Host-authoritative per-device sync state. LAN/Cloud are delivery methods;
  // progress must be tied to the device, not to the transport used last.
  await sql`alter table store_devices add column if not exists active_transport text default ''`;
  await sql`alter table store_devices add column if not exists last_sync_transport text default ''`;
  await sql`alter table store_devices add column if not exists last_applied_cursor timestamptz`;
  await sql`alter table store_devices add column if not exists last_ack_cursor timestamptz`;
  await sql`alter table store_devices add column if not exists last_applied_sequence bigint not null default 0`;
  await sql`alter table store_devices add column if not exists last_ack_sequence bigint not null default 0`;
  await sql`alter table store_devices add column if not exists last_ack_at timestamptz`;
  await sql`alter table store_devices add column if not exists online boolean not null default false`;
}

export async function assertDeviceAllowed(req, { storeId, branchId = 'main', allowedRoles = [], allowedTransports = [], force = false } = {}) {
  // Backward-compatible by default. Set REQUIRE_DEVICE_TOKEN_AUTH=true after all
  // deployed devices have paired and have a device-scoped token.
  const requireDeviceAuth =
    (process.env.NODE_ENV || '').toLowerCase() === 'production' ||
    (process.env.REQUIRE_DEVICE_TOKEN_AUTH || '').toLowerCase() === 'true';
  if (!force && !requireDeviceAuth) return;
  const deviceId = String(req.headers['x-device-id'] || req.headers['X-Device-Id'] || '').trim();
  const deviceToken = String(req.headers['x-device-token'] || req.headers['X-Device-Token'] || '').trim();
  if (!deviceId || !deviceToken) {
    const err = new Error('Missing device credentials. Pair this device again.');
    err.statusCode = 401;
    throw err;
  }
  await ensureDeviceAuthColumns();
  const rows = await sql`
    select device_id, role, transport, active_transport, revoked, suspended, device_token
    from store_devices
    where store_id = ${storeId}
      and branch_id = ${branchId}
      and device_id = ${deviceId}
    limit 1
  `;
  if (!rows.length || rows[0].revoked === true || rows[0].suspended === true || String(rows[0].device_token || '') !== deviceToken) {
    const err = new Error('Device is not authorized, suspended, or has been revoked.');
    err.statusCode = 403;
    throw err;
  }
  const role = String(rows[0].role || '');
  const transport = String(rows[0].transport || rows[0].active_transport || '');
  if (allowedRoles.length && !allowedRoles.includes(role)) {
    const err = new Error(`This endpoint requires role: ${allowedRoles.join(', ')}.`);
    err.statusCode = 403;
    throw err;
  }
  if (allowedTransports.length && !allowedTransports.includes(transport)) {
    const err = new Error(`This endpoint requires transport: ${allowedTransports.join(', ')}.`);
    err.statusCode = 403;
    throw err;
  }
}


export async function assertAccountOrDevice(req, options = {}) {
  const requireCloudAccess = async () => {
    if ((options.allowedTransports || []).includes('cloud') && options.storeId) {
      await assertCloudSyncEnabled(options.storeId);
    }
  };
  const allowedRoles = options.allowedRoles || [];
  const accountCanAuthorize =
    options.allowAccount !== false &&
    (!allowedRoles.length || allowedRoles.includes('host'));
  try {
    if (!accountCanAuthorize) throw new Error('Account authorization is not allowed for this endpoint.');
    assertAccountStoreToken(req, { storeId: options.storeId, branchId: options.branchId || 'main' });
    await requireCloudAccess();
    return { mode: 'account' };
  } catch (_) {
    await assertDeviceAllowed(req, { ...options, force: true });
    await requireCloudAccess();
    return { mode: 'device' };
  }
}

export function sendError(res, error) {
  const status = error.statusCode || 500;
  res.status(status).json({ ok: false, error: error.message || String(error) });
}
