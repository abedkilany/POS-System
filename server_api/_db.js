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

const ACCESS_TOKEN_TTL_SECONDS = 15 * 60;
const REFRESH_TOKEN_TTL_SECONDS = 30 * 24 * 60 * 60;

function requiredSecret(name) {
  const value = String(process.env[name] || '').trim();
  if (!value) {
    const error = new Error(`${name} must be configured.`);
    error.statusCode = 500;
    throw error;
  }
  return value;
}

export function accountSigningSecret() {
  return requiredSecret('ACCOUNT_JWT_SECRET');
}

export function adminSigningSecret() {
  return requiredSecret('ADMIN_JWT_SECRET');
}

export async function ensureAuthSessionsTable() {
  await sql`
    create table if not exists auth_sessions (
      id text primary key,
      account_id text not null,
      refresh_token_hash text not null unique,
      expires_at timestamptz not null,
      revoked_at timestamptz,
      created_at timestamptz not null default now(),
      last_used_at timestamptz
    )
  `;
  await sql`create index if not exists idx_auth_sessions_account on auth_sessions (account_id, revoked_at, expires_at)`;
}

function hashRefreshToken(token) {
  return crypto.createHash('sha256').update(String(token || ''), 'utf8').digest('hex');
}

function signToken(payload, secret) {
  const payloadB64 = Buffer.from(JSON.stringify(payload)).toString('base64url');
  const signature = crypto.createHmac('sha256', secret).update(payloadB64).digest('base64url');
  return `${payloadB64}.${signature}`;
}

export async function createAuthSession({
  accountId,
  username,
  namespace,
  storeId = '',
  branchId = '',
  accountType = 'store_owner',
}) {
  await ensureAuthSessionsTable();
  const sessionId = `ses_${crypto.randomBytes(18).toString('hex')}`;
  const refreshToken = `ref_${crypto.randomBytes(32).toString('base64url')}`;
  const now = Math.floor(Date.now() / 1000);
  const accountIsPlatform = String(namespace || '') === 'ventio' || accountType === 'platform_admin';
  const common = {
    sessionId,
    accountId,
    username,
    namespace,
    storeId,
    branchId,
    exp: now + ACCESS_TOKEN_TTL_SECONDS,
  };
  const accountToken = signToken({
    ...common,
    type: accountIsPlatform ? 'platform_admin' : 'store_account',
  }, accountSigningSecret());
  const adminToken = accountIsPlatform
    ? signToken({ ...common, type: 'platform_admin' }, adminSigningSecret())
    : '';
  const expiresAt = new Date((now + REFRESH_TOKEN_TTL_SECONDS) * 1000).toISOString();
  await sql`
    insert into auth_sessions (id, account_id, refresh_token_hash, expires_at, last_used_at)
    values (${sessionId}, ${accountId}, ${hashRefreshToken(refreshToken)}, ${expiresAt}, now())
  `;
  return { accountToken, adminToken, refreshToken, sessionId };
}

export async function findRefreshSession(refreshToken) {
  const token = String(refreshToken || '').trim();
  if (!token) return null;
  await ensureAuthSessionsTable();
  const rows = await sql`
    select id, account_id, expires_at, revoked_at
    from auth_sessions
    where refresh_token_hash = ${hashRefreshToken(token)}
      and revoked_at is null
      and expires_at > now()
    limit 1
  `;
  return rows[0] || null;
}

export async function revokeAuthSession(sessionId) {
  const id = String(sessionId || '').trim();
  if (!id) return;
  await ensureAuthSessionsTable();
  await sql`update auth_sessions set revoked_at = coalesce(revoked_at, now()) where id = ${id}`;
}

export async function revokeAllAuthSessions(accountId) {
  const id = String(accountId || '').trim();
  if (!id) return;
  await ensureAuthSessionsTable();
  await sql`update auth_sessions set revoked_at = coalesce(revoked_at, now()) where account_id = ${id} and revoked_at is null`;
}

export async function isAuthSessionActive(sessionId, accountId) {
  const id = String(sessionId || '').trim();
  if (!id) return false;
  await ensureAuthSessionsTable();
  const rows = await sql`
    select id
    from auth_sessions
    where id = ${id}
      and account_id = ${String(accountId || '')}
      and revoked_at is null
      and expires_at > now()
    limit 1
  `;
  return rows.length > 0;
}

export async function enforceRateLimit({ key, limit, windowSeconds, message = 'Too many requests. Try again later.' }) {
  const cleanKey = String(key || '').trim();
  if (!cleanKey) return;
  const cleanLimit = Math.max(Number(limit) || 1, 1);
  const cleanWindow = Math.max(Number(windowSeconds) || 60, 1);
  await sql`
    create table if not exists api_rate_limits (
      key text primary key,
      window_started_at timestamptz not null,
      attempts integer not null default 0,
      updated_at timestamptz not null default now()
    )
  `;
  const rows = await sql`
    insert into api_rate_limits (key, window_started_at, attempts, updated_at)
    values (${cleanKey}, now(), 1, now())
    on conflict (key) do update set
      attempts = case
        when api_rate_limits.window_started_at <= now() - make_interval(secs => ${cleanWindow}) then 1
        else api_rate_limits.attempts + 1
      end,
      window_started_at = case
        when api_rate_limits.window_started_at <= now() - make_interval(secs => ${cleanWindow}) then now()
        else api_rate_limits.window_started_at
      end,
      updated_at = now()
    returning attempts
  `;
  if (Number(rows[0]?.attempts || 0) > cleanLimit) {
    const error = new Error(message);
    error.statusCode = 429;
    error.retryAfterSeconds = cleanWindow;
    throw error;
  }
}

export function requestIp(req) {
  const forwarded = String(req.headers['x-forwarded-for'] || '').split(',')[0].trim();
  return forwarded || String(req.socket?.remoteAddress || 'unknown').trim() || 'unknown';
}

export function assertStoreAllowed(storeId) {
  const allowed = (process.env.DIRECT_SYNC_STORE_ID || '').trim();
  if (allowed && storeId !== allowed) {
    const err = new Error('This deployment is not allowed to access the requested store_id.');
    err.statusCode = 403;
    throw err;
  }
}

export function verifyAccountToken(token) {
  const secret = accountSigningSecret();
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
    if (!['store_account', 'platform_admin'].includes(payload?.type)) return null;
    if (!payload?.sessionId) return null;
    if (Number(payload?.exp || 0) < Math.floor(Date.now() / 1000)) return null;
    return payload;
  } catch (_) {
    return null;
  }
}

export async function accountTokenFromRequest(req) {
  const header = req.headers.authorization || req.headers.Authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7).trim() : '';
  const payload = verifyAccountToken(token);
  if (!payload || !(await isAuthSessionActive(payload.sessionId, payload.accountId))) return null;
  return payload;
}

export async function assertAccountStoreToken(req, { storeId, branchId = '' } = {}) {
  const payload = await accountTokenFromRequest(req);
  if (!payload) {
    const err = new Error('Invalid or missing account session.');
    err.statusCode = 401;
    throw err;
  }
  if (payload.type !== 'store_account') {
    const err = new Error('A store account session is required.');
    err.statusCode = 403;
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
  await sql`alter table store_devices add column if not exists device_public_key text default ''`;
}

async function ensureDirectSubscriptionColumn() {
  await sql`
    create table if not exists app_subscriptions (
      id text primary key,
      store_id text not null,
      plan text not null default 'trial',
      status text not null default 'trial',
      trial_ends_at timestamptz,
      devices_limit integer not null default 2,
      direct_sync_enabled boolean not null default false,
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now()
    )
  `;
  await sql`alter table app_subscriptions add column if not exists direct_sync_enabled boolean not null default false`;
}

export async function getDirectSyncEnabled(storeId) {
  await ensureDirectSubscriptionColumn();
  const rows = await sql`
    select coalesce(bool_or(direct_sync_enabled), false) as enabled
    from app_subscriptions
    where store_id = ${storeId}
  `;
  return rows[0]?.enabled === true;
}

export async function assertDirectSyncEnabled(storeId) {
  if (await getDirectSyncEnabled(storeId)) return;
  const err = new Error('Direct Sync is not enabled for this store.');
  err.statusCode = 403;
  throw err;
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
  // Legacy stores may not have an app_subscriptions row yet. Treat those
  // stores as the default trial allowance instead of blocking every claim.
  const limitRows = await sql`
    select coalesce(max(devices_limit), 2)::int as devices_limit
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
  await sql`alter table store_devices add column if not exists device_public_key text default ''`;
  await sql`alter table store_devices add column if not exists host_device_id text default ''`;
  await sql`alter table store_devices add column if not exists revoked boolean not null default false`;
  await sql`alter table store_devices add column if not exists suspended boolean not null default false`;
  await sql`alter table store_devices add column if not exists wipe_pending boolean not null default false`;
  await sql`alter table store_devices add column if not exists wipe_requested_at timestamptz`;
  // Host-authoritative per-device sync state. LAN/Direct are delivery methods;
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
  const allowedRoles = options.allowedRoles || [];
  const accountCanAuthorize =
    options.allowAccount !== false &&
    (!allowedRoles.length || allowedRoles.includes('host'));
  try {
    if (!accountCanAuthorize) throw new Error('Account authorization is not allowed for this endpoint.');
    await assertAccountStoreToken(req, { storeId: options.storeId, branchId: options.branchId || 'main' });
    return { mode: 'account' };
  } catch (_) {
    await assertDeviceAllowed(req, { ...options, force: true });
    return { mode: 'device' };
  }
}

export function sendError(res, error) {
  const status = error.statusCode || 500;
  if (status === 429 && error.retryAfterSeconds) {
    res.setHeader('Retry-After', String(error.retryAfterSeconds));
  }
  res.status(status).json({ ok: false, error: error.message || String(error) });
}
