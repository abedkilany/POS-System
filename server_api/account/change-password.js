import crypto from 'crypto';
import { accountTokenFromRequest, sql } from '../_db.js';

function sendError(res, error) {
  const status = Number(error?.statusCode || error?.status || 500);
  return res.status(status).json({ ok: false, error: error?.message || 'Request failed.' });
}

function verifyPassword(password, encoded) {
  const parts = String(encoded || '').split('$');
  if (parts.length !== 4 || parts[0] !== 'pbkdf2_sha256') return false;
  const iterations = Number(parts[1]);
  const salt = parts[2];
  const expected = parts[3];
  const actual = crypto.pbkdf2Sync(String(password), salt, iterations, 32, 'sha256').toString('hex');
  try {
    const a = Buffer.from(actual, 'hex');
    const b = Buffer.from(expected, 'hex');
    return a.length === b.length && crypto.timingSafeEqual(a, b);
  } catch (_) {
    return false;
  }
}

function hashPassword(password) {
  const iterations = 120000;
  const salt = crypto.randomBytes(16).toString('hex');
  const hash = crypto.pbkdf2Sync(String(password), salt, iterations, 32, 'sha256').toString('hex');
  return `pbkdf2_sha256$${iterations}$${salt}$${hash}`;
}

export default async function handler(req, res) {
  try {
    if (req.method !== 'POST') {
      res.setHeader('Allow', 'POST, OPTIONS');
      return res.status(405).json({ ok: false, error: 'Method not allowed.' });
    }

    const payload = accountTokenFromRequest(req);
    if (!payload) {
      return res.status(401).json({ ok: false, error: 'Invalid or missing account session.' });
    }

    const body = req.body || {};
    const currentPassword = String(body.currentPassword || body.current_password || '');
    const newPassword = String(body.newPassword || body.new_password || '');

    if (!currentPassword || !newPassword) {
      return res.status(400).json({ ok: false, error: 'Current password and new password are required.' });
    }
    if (newPassword.length < 6) {
      return res.status(400).json({ ok: false, error: 'New password must be at least 6 characters.' });
    }
    if (currentPassword === newPassword) {
      return res.status(400).json({ ok: false, error: 'New password must be different from the current password.' });
    }

    const rows = await sql`
      select id, password_hash, status
      from app_accounts
      where id = ${String(payload.accountId || '')}
      limit 1
    `;
    if (!rows.length) {
      return res.status(404).json({ ok: false, error: 'Account was not found.' });
    }
    const row = rows[0];
    if (String(row.status || '') !== 'active') {
      return res.status(403).json({ ok: false, error: 'Account is not active.' });
    }
    if (!verifyPassword(currentPassword, row.password_hash)) {
      return res.status(401).json({ ok: false, error: 'Current password is incorrect.' });
    }

    await sql`
      update app_accounts
      set password_hash = ${hashPassword(newPassword)}, updated_at = now()
      where id = ${String(payload.accountId || '')}
    `;

    return res.status(200).json({ ok: true, message: 'Password changed successfully.' });
  } catch (error) {
    return sendError(res, error);
  }
}
