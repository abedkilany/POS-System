import crypto from 'crypto';

export const PUBLIC_ACCOUNT_TYPES = new Set(['merchant', 'customer', 'driver']);

export function normalizeUsername(value) {
  return String(value || '').trim().toLowerCase();
}

export function roleForAccountType(accountType) {
  if (accountType === 'customer') return 'customer';
  if (accountType === 'driver') return 'driver';
  return 'store_owner';
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
    passwordHash: row.password_hash,
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

export function issueSessionToken(userId) {
  const secret = process.env.AUTH_SESSION_SECRET || process.env.CLOUD_SYNC_TOKEN || 'dev-secret-change-me';
  const issuedAt = Date.now().toString();
  const nonce = crypto.randomBytes(12).toString('base64url');
  const body = `${userId}.${issuedAt}.${nonce}`;
  const sig = crypto.createHmac('sha256', secret).update(body).digest('base64url');
  return `${body}.${sig}`;
}

export function sendAuthError(res, status, message) {
  res.status(status).json({ ok: false, error: message });
}
