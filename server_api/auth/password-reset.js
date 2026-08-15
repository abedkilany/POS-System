import crypto from 'crypto';
import { sql, sendError } from '../_db.js';
import { ensurePasswordResetTables } from '../admin/password-reset.js';

function bodyOf(req) {
  if (req.body && typeof req.body === 'object') return req.body;
  if (typeof req.body === 'string' && req.body.trim()) return JSON.parse(req.body);
  return {};
}

function hashCode(code) {
  return crypto.createHash('sha256').update(String(code), 'utf8').digest('hex');
}

function hashPassword(password) {
  const iterations = 120000;
  const salt = crypto.randomBytes(16).toString('hex');
  const hash = crypto.pbkdf2Sync(String(password), salt, iterations, 32, 'sha256').toString('hex');
  return `pbkdf2_sha256$${iterations}$${salt}$${hash}`;
}

function parseLoginName(value) {
  const parts = String(value || '').trim().toLowerCase().split('@');
  if (parts.length !== 2 || !parts[0] || !parts[1]) return null;
  return { username: parts[0], storeSlug: parts[1] };
}

export default async function handler(req, res) {
  try {
    if (req.method !== 'POST') return res.status(405).json({ ok: false, error: 'Method not allowed.' });
    await ensurePasswordResetTables();
    const body = bodyOf(req);
    const loginName = parseLoginName(body.loginName || body.login_name);
    const code = String(body.resetCode || body.reset_code || '').trim().toUpperCase();
    const newPassword = String(body.newPassword || body.new_password || '');
    if (!loginName || !code || !newPassword) {
      return res.status(400).json({ ok: false, error: 'Login name, reset code, and new password are required.' });
    }
    if (newPassword.length < 6) return res.status(400).json({ ok: false, error: 'New password must be at least 6 characters.' });

    const rows = await sql`
      select g.id as grant_id, a.id, a.username, a.account_type,
             s.id as store_id, s.branch_id, s.slug as store_slug, s.name as store_name
      from password_reset_grants g
      join app_accounts a on a.id = g.account_id
      left join app_stores s on s.owner_account_id = a.id
      where g.code_hash = ${hashCode(code)}
        and g.used_at is null
        and g.expires_at > now()
        and a.username = ${loginName.username}
        and coalesce(a.namespace_slug, s.slug, '') = ${loginName.storeSlug}
      limit 1
    `;
    if (!rows.length) return res.status(400).json({ ok: false, error: 'The reset code is invalid or expired.' });

    const consumed = await sql`
      update password_reset_grants set used_at = now()
      where id = ${rows[0].grant_id} and used_at is null and expires_at > now()
      returning id
    `;
    if (!consumed.length) return res.status(400).json({ ok: false, error: 'The reset code is invalid or expired.' });

    await sql`update app_accounts set password_hash = ${hashPassword(newPassword)}, updated_at = now() where id = ${rows[0].id}`;
    await sql`update auth_sessions set revoked_at = now() where account_id = ${rows[0].id} and revoked_at is null`;
    return res.status(200).json({
      ok: true,
      message: 'Password reset successfully.',
      accountId: rows[0].id,
      storeId: rows[0].store_id || '',
      branchId: rows[0].branch_id || '',
      username: rows[0].username || '',
      storeSlug: rows[0].store_slug || loginName.storeSlug,
      storeName: rows[0].store_name || '',
      loginName: `${rows[0].username}@${rows[0].store_slug || loginName.storeSlug}`,
      accountType: rows[0].account_type || 'store_owner',
    });
  } catch (error) {
    return sendError(res, error);
  }
}

