import { neon } from '@neondatabase/serverless';

if (!process.env.DATABASE_URL) {
  throw new Error('DATABASE_URL is not configured. Add it in Vercel Environment Variables.');
}

export const sql = neon(process.env.DATABASE_URL);

function hasValidDeploymentToken(req) {
  const expected = process.env.CLOUD_SYNC_TOKEN || '';
  const header = req.headers.authorization || req.headers.Authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7).trim() : '';
  return Boolean(expected && token === expected);
}

export function assertSyncToken(req) {
  if (hasValidDeploymentToken(req)) return;

  // Sync V2: paired Clients authenticate with their device-scoped token.
  // The concrete role/transport/revoked check happens in assertDeviceAllowed()
  // after the endpoint knows storeId/branchId. This must work even when
  // REQUIRE_DEVICE_TOKEN_AUTH is not set, otherwise Clients can pair but then
  // remain Cloud offline because they do not have the deployment token.
  const deviceId = String(req.headers['x-device-id'] || req.headers['X-Device-Id'] || '').trim();
  const deviceToken = String(req.headers['x-device-token'] || req.headers['X-Device-Token'] || '').trim();
  if (deviceId && deviceToken) return;

  const expected = process.env.CLOUD_SYNC_TOKEN || '';
  if (!expected) {
    const err = new Error('CLOUD_SYNC_TOKEN is not configured. Refusing unauthenticated cloud sync.');
    err.statusCode = 500;
    throw err;
  }
  const err = new Error('Invalid or missing cloud sync token. Pair this device with the Host or use the Host deployment token.');
  err.statusCode = 401;
  throw err;
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
  await sql`alter table store_devices add column if not exists revoked boolean not null default false`;
}

export async function assertDeviceAllowed(req, { storeId, branchId = 'main', allowedRoles = [], allowedTransports = [] } = {}) {
  const deviceId = String(req.headers['x-device-id'] || req.headers['X-Device-Id'] || '').trim();
  const deviceToken = String(req.headers['x-device-token'] || req.headers['X-Device-Token'] || '').trim();

  // Deployment-token Host calls remain backward compatible unless strict mode is
  // enabled. Device-token calls are always validated so paired Clients can sync
  // without the shared Cloud token.
  const strictDeviceAuth = (process.env.REQUIRE_DEVICE_TOKEN_AUTH || '').toLowerCase() === 'true';
  const usingDeploymentToken = hasValidDeploymentToken(req);
  const usingDeviceToken = Boolean(deviceId && deviceToken);
  if (!strictDeviceAuth && usingDeploymentToken) return;
  if (!strictDeviceAuth && !usingDeviceToken) return;

  if (!deviceId || !deviceToken) {
    const err = new Error('Missing device credentials. Pair this device again.');
    err.statusCode = 401;
    throw err;
  }
  await ensureDeviceAuthColumns();
  const rows = await sql`
    select device_id, role, transport, revoked, device_token
    from store_devices
    where store_id = ${storeId}
      and branch_id = ${branchId}
      and device_id = ${deviceId}
    limit 1
  `;
  if (!rows.length || rows[0].revoked === true || String(rows[0].device_token || '') !== deviceToken) {
    const err = new Error('Device is not authorized or has been revoked.');
    err.statusCode = 403;
    throw err;
  }
  const role = String(rows[0].role || '');
  const transport = String(rows[0].transport || '');
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

export function sendError(res, error) {
  const status = error.statusCode || 500;
  res.status(status).json({ ok: false, error: error.message || String(error) });
}
