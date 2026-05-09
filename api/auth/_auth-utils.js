import crypto from 'crypto';

export const PUBLIC_ACCOUNT_TYPES = new Set(['platform_user', 'customer']);

export function normalizeUsername(value) {
  return String(value || '').trim().toLowerCase();
}

export function roleForAccountType(accountType) {
  if (accountType === 'customer') return 'customer';
  if (accountType === 'driver') return 'driver';
  if (accountType === 'merchant') return 'store_owner';
  if (accountType === 'app_admin') return 'platform_admin';
  return 'platform_user';
}

export function hashPassword(password) {
  const salt = crypto.randomBytes(12).toString('base64url');
  return hashPasswordWithSalt(password, salt);
}

export function hashPasswordWithSalt(password, salt) {
  let digest = Buffer.from(`store_manager_pro|local_pin_v2|${salt}|${String(password || '').trim()}`, 'utf8');
  for (let i = 0; i < 12000; i += 1) {
    digest = crypto.createHash('sha256').update(digest).digest();
  }
  return `sha256salt:${salt}:${digest.toString('base64url')}`;
}

export function verifyPassword(password, storedHash) {
  const parts = String(storedHash || '').split(':');
  if (parts.length !== 3 || parts[0] !== 'sha256salt') return false;
  return hashPasswordWithSalt(password, parts[1]) === storedHash;
}

export function publicUser(row) {
  if (!row) return null;
  return {
    id: row.id,
    fullName: row.full_name,
    username: row.username,
    roleId: row.role_id,
    accountType: row.account_type,
    phone: row.phone || '',
    email: row.email || '',
    primaryStoreId: row.primary_store_id || '',
    extraPermissions: [],
    deniedPermissions: [],
    isActive: row.is_active !== false,
    isSystem: row.is_system === true,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    lastLoginAt: row.last_login_at || null,
  };
}


const SESSION_TTL_MS = 1000 * 60 * 60 * 24 * 14;

function sessionSecret() {
  return process.env.AUTH_SESSION_SECRET || process.env.CLOUD_SYNC_TOKEN || 'dev-secret-change-me';
}

export function issueSessionToken(userId) {
  const issuedAt = Date.now().toString();
  const nonce = crypto.randomBytes(12).toString('base64url');
  const body = `${userId}.${issuedAt}.${nonce}`;
  const sig = crypto.createHmac('sha256', sessionSecret()).update(body).digest('base64url');
  return `${body}.${sig}`;
}

export function verifySessionToken(token) {
  const parts = String(token || '').trim().split('.');
  if (parts.length !== 4) return null;
  const [userId, issuedAt, nonce, sig] = parts;
  const issued = Number(issuedAt);
  if (!userId || !nonce || !Number.isFinite(issued)) return null;
  if (Date.now() - issued > SESSION_TTL_MS) return null;
  const body = `${userId}.${issuedAt}.${nonce}`;
  const expected = crypto.createHmac('sha256', sessionSecret()).update(body).digest('base64url');
  try {
    if (!crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(expected))) return null;
  } catch (_) {
    return null;
  }
  return { userId, issuedAt: issued };
}

export async function requireAuth(req, sql) {
  const auth = String(req.headers?.authorization || '');
  const token = auth.toLowerCase().startsWith('bearer ') ? auth.slice(7).trim() : '';
  const session = verifySessionToken(token);
  if (!session) {
    const error = new Error('Authentication required.');
    error.statusCode = 401;
    throw error;
  }
  const rows = await sql`select * from app_users where id = ${session.userId} and is_active = true limit 1`;
  if (!rows.length) {
    const error = new Error('Authenticated user not found or inactive.');
    error.statusCode = 401;
    throw error;
  }
  return rows[0];
}

export async function requireStoreAccess(req, sql, storeId, allowedRoles = ['owner','manager','orders_staff']) {
  const user = await requireAuth(req, sql);
  if (user.account_type === 'app_admin') return { user, member: null };
  const rows = await sql`
    select * from store_members
    where store_id = ${storeId} and user_id = ${user.id} and is_active = true
    limit 1
  `;
  const member = rows[0] || null;
  if (!member || !allowedRoles.includes(member.role)) {
    const error = new Error('You do not have access to this store.');
    error.statusCode = 403;
    throw error;
  }
  return { user, member };
}

export function sendAuthError(res, status, message) {
  res.status(status).json({ ok: false, error: message });
}

export function sendCaughtError(res, error) {
  res.status(error.statusCode || 500).json({ ok: false, error: error.message || String(error) });
}


export function hashStoreToken(token) {
  const secret = process.env.STORE_TOKEN_SECRET || process.env.AUTH_SESSION_SECRET || process.env.CLOUD_SYNC_TOKEN || 'dev-secret-change-me';
  return crypto.createHmac('sha256', secret).update(String(token || '').trim()).digest('base64url');
}

export function issueStoreToken() {
  return `st_${crypto.randomBytes(24).toString('base64url')}`;
}
