import crypto from 'crypto';
import { accountTokenFromRequest, sql } from '../_db.js';

function sendError(res, error) {
  const status = Number(error?.statusCode || error?.status || 500);
  return res.status(status).json({ ok: false, error: error?.message || 'Request failed.' });
}

function normalizePart(value) {
  return String(value || '').trim().toLowerCase();
}

function isValidUsername(value) {
  return /^[a-z0-9][a-z0-9_-]{2,31}$/.test(value);
}

function hashPassword(password) {
  const iterations = 120000;
  const salt = crypto.randomBytes(16).toString('hex');
  const hash = crypto.pbkdf2Sync(String(password), salt, iterations, 32, 'sha256').toString('hex');
  return `pbkdf2_sha256$${iterations}$${salt}$${hash}`;
}

async function ensureTables() {
  await sql`
    create table if not exists app_accounts (
      id text primary key,
      username text not null,
      namespace_slug text not null default '',
      password_hash text not null,
      full_name text not null default '',
      account_type text not null default 'store_owner',
      status text not null default 'active',
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now()
    )
  `;
  await sql`
    create table if not exists app_stores (
      id text primary key,
      owner_account_id text not null references app_accounts(id) on delete cascade,
      branch_id text not null default 'BR-MAIN',
      slug text not null,
      name text not null default 'My Store',
      status text not null default 'active',
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now()
    )
  `;
  await sql`alter table app_accounts add column if not exists namespace_slug text not null default ''`;
  await sql`alter table app_accounts add column if not exists account_type text not null default 'store_owner'`;
  await sql`create unique index if not exists app_accounts_username_namespace_key on app_accounts (username, namespace_slug)`;
}

export default async function handler(req, res) {
  try {
    await ensureTables();
    if (req.method !== 'PATCH') {
      res.setHeader('Allow', 'PATCH, OPTIONS');
      return res.status(405).json({ ok: false, error: 'Method not allowed.' });
    }

    const payload = accountTokenFromRequest(req);
    if (!payload) {
      return res.status(401).json({ ok: false, error: 'Invalid or missing account session.' });
    }

    const body = req.body || {};
    const username = normalizePart(body.username);
    const fullName = String(body.fullName || body.full_name || '').trim() || 'Administrator';
    const newPassword = String(body.newPassword || body.new_password || '').trim();
    const accountId = String(payload.accountId || '');
    const storeId = String(payload.storeId || '');

    if (!accountId || !storeId) {
      return res.status(401).json({ ok: false, error: 'Owner account session is incomplete.' });
    }
    if (username.includes('@') || !isValidUsername(username)) {
      return res.status(400).json({ ok: false, error: 'Username must be 3-32 characters: letters, numbers, underscore, or hyphen. No spaces.' });
    }
    if (newPassword && newPassword.length < 6) {
      return res.status(400).json({ ok: false, error: 'New password must be at least 6 characters.' });
    }

    const rows = await sql`
      select a.id, a.namespace_slug, a.account_type, a.status, s.id as store_id, s.slug as store_slug,
             s.name as store_name, s.branch_id, s.cloud_sync_enabled
      from app_accounts a
      join app_stores s on s.owner_account_id = a.id
      where a.id = ${accountId}
        and s.id = ${storeId}
      limit 1
    `;
    if (!rows.length) return res.status(404).json({ ok: false, error: 'Owner account was not found.' });
    const row = rows[0];
    if (String(row.status || '') !== 'active') return res.status(403).json({ ok: false, error: 'Owner account is not active.' });
    if (String(row.account_type || '') !== 'store_owner') return res.status(403).json({ ok: false, error: 'Only the Store Owner can update this protected account.' });

    const duplicate = await sql`
      select id from app_accounts
      where username = ${username}
        and namespace_slug = ${String(row.namespace_slug || row.store_slug || '')}
        and id <> ${accountId}
      limit 1
    `;
    if (duplicate.length) return res.status(409).json({ ok: false, error: 'Username already exists for this store.' });

    if (newPassword) {
      await sql`
        update app_accounts
        set username = ${username}, full_name = ${fullName}, password_hash = ${hashPassword(newPassword)},
            account_type = 'store_owner', status = 'active', updated_at = now()
        where id = ${accountId}
      `;
    } else {
      await sql`
        update app_accounts
        set username = ${username}, full_name = ${fullName},
            account_type = 'store_owner', status = 'active', updated_at = now()
        where id = ${accountId}
      `;
    }

    return res.status(200).json({
      ok: true,
      message: 'Store Owner updated successfully.',
      accountId,
      storeId: row.store_id || storeId,
      branchId: row.branch_id || String(payload.branchId || ''),
      username,
      storeSlug: row.store_slug || row.namespace_slug || '',
      storeName: row.store_name || '',
      loginName: `${username}@${row.namespace_slug || row.store_slug || ''}`,
      accountType: 'store_owner',
      cloudSyncEnabled: row.cloud_sync_enabled === true,
    });
  } catch (error) {
    return sendError(res, error);
  }
}
