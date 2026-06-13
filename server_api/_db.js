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

export function assertSyncToken(req) {
  const expected = process.env.CLOUD_SYNC_TOKEN || '';
  if (!expected) {
    const err = new Error('CLOUD_SYNC_TOKEN is not configured. Refusing unauthenticated cloud sync.');
    err.statusCode = 500;
    throw err;
  }
  const header = req.headers.authorization || req.headers.Authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7).trim() : '';
  if (token !== expected) {
    const err = new Error('Invalid or missing cloud sync token.');
    err.statusCode = 401;
    throw err;
  }
}

export function assertStoreAllowed(storeId) {
  const allowed = (process.env.CLOUD_SYNC_STORE_ID || '').trim();
  if (allowed && storeId !== allowed) {
    const err = new Error('This sync token is not allowed to access the requested store_id.');
    err.statusCode = 403;
    throw err;
  }
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
  if (!force && (process.env.REQUIRE_DEVICE_TOKEN_AUTH || '').toLowerCase() !== 'true') return;
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


export async function assertSyncTokenOrDevice(req, options = {}) {
  try {
    assertSyncToken(req);
    return;
  } catch (authError) {
    await assertDeviceAllowed(req, { ...options, force: true });
  }
}

export function sendError(res, error) {
  const status = error.statusCode || 500;
  res.status(status).json({ ok: false, error: error.message || String(error) });
}