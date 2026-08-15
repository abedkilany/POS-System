import crypto from 'crypto';
import { sql, sendError, adminSigningSecret, isAuthSessionActive } from '../_db.js';

function bodyOf(req) {
  if (req.body && typeof req.body === 'object') return req.body;
  if (typeof req.body === 'string' && req.body.trim()) return JSON.parse(req.body);
  return {};
}

async function verifyAdminToken(token) {
  const parts = String(token || '').split('.');
  if (parts.length !== 2) return false;
  const [payloadB64, signature] = parts;
  const expected = crypto.createHmac('sha256', adminSigningSecret())
    .update(payloadB64).digest('base64url');
  try {
    if (!crypto.timingSafeEqual(Buffer.from(signature), Buffer.from(expected))) return false;
    const payload = JSON.parse(Buffer.from(payloadB64, 'base64url').toString('utf8'));
    return payload?.type === 'platform_admin' &&
      String(payload?.namespace || '') === 'ventio' &&
      Number(payload?.exp || 0) >= Math.floor(Date.now() / 1000) &&
      await isAuthSessionActive(payload.sessionId, payload.accountId);
  } catch (_) {
    return false;
  }
}

function requireAdmin(req) {
  const header = req.headers.authorization || req.headers.Authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7).trim() : '';
  return verifyAdminToken(token);
}

function hashCode(code) {
  return crypto.createHash('sha256').update(String(code), 'utf8').digest('hex');
}

function resetCode() {
  return crypto.randomBytes(9).toString('base64url').replace(/[-_]/g, '').slice(0, 12).toUpperCase();
}

function hashPassword(password) {
  const iterations = 120000;
  const salt = crypto.randomBytes(16).toString('hex');
  const hash = crypto.pbkdf2Sync(String(password), salt, iterations, 32, 'sha256').toString('hex');
  return `pbkdf2_sha256$${iterations}$${salt}$${hash}`;
}

export async function ensurePasswordResetTables() {
  await sql`
    create table if not exists password_reset_grants (
      id text primary key,
      account_id text not null references app_accounts(id) on delete cascade,
      code_hash text not null unique,
      reason text not null default '',
      created_by text not null default '',
      created_at timestamptz not null default now(),
      expires_at timestamptz not null,
      used_at timestamptz
    )
  `;
  await sql`create index if not exists idx_password_reset_grants_active on password_reset_grants(account_id, used_at, expires_at)`;
}

export default async function handler(req, res) {
  try {
    if (req.method !== 'POST') return res.status(405).json({ ok: false, error: 'Method not allowed.' });
    if (!(await requireAdmin(req))) return res.status(401).json({ ok: false, error: 'Admin access is required.' });
    await ensurePasswordResetTables();
    const body = bodyOf(req);
    const accountId = String(body.accountId || body.account_id || '').trim();
    const reason = String(body.reason || '').trim().slice(0, 500);
    if (!accountId) return res.status(400).json({ ok: false, error: 'Account id is required.' });

    const rows = await sql`
      select a.id, a.username, a.namespace_slug, a.account_type,
             s.id as store_id, s.slug as store_slug, s.name as store_name
      from app_accounts a
      left join app_stores s on s.owner_account_id = a.id
      where a.id = ${accountId}
      limit 1
    `;
    if (!rows.length) return res.status(404).json({ ok: false, error: 'Account was not found.' });
    if (String(rows[0].account_type || '') === 'platform_admin') {
      return res.status(403).json({ ok: false, error: 'Platform admin password resets are not issued here.' });
    }

    const code = resetCode();
    const grantId = `rst_${crypto.randomBytes(16).toString('hex')}`;
    await sql`update password_reset_grants set used_at = now() where account_id = ${accountId} and used_at is null`;
    await sql`
      insert into password_reset_grants(id, account_id, code_hash, reason, created_by, expires_at)
      values (${grantId}, ${accountId}, ${hashCode(code)}, ${reason}, 'platform_admin', now() + interval '15 minutes')
    `;
    return res.status(200).json({
      ok: true,
      message: 'Password reset permission created.',
      resetCode: code,
      expiresAt: new Date(Date.now() + 15 * 60 * 1000).toISOString(),
      accountId: rows[0].id,
      username: rows[0].username || '',
      storeSlug: rows[0].store_slug || rows[0].namespace_slug || '',
      storeName: rows[0].store_name || '',
    });
  } catch (error) {
    return sendError(res, error);
  }
}

