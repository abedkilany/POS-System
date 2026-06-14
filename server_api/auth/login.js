import crypto from 'crypto';
import { sql, sendError } from '../_db.js';

function normalizeUsername(value) {
  return String(value || '').trim().toLowerCase();
}

function verifyPassword(password, encoded) {
  const parts = String(encoded || '').split('$');
  if (parts.length !== 4 || parts[0] !== 'pbkdf2_sha256') return false;
  const iterations = Number(parts[1]);
  const salt = parts[2];
  const expected = parts[3];
  const actual = crypto.pbkdf2Sync(String(password), salt, iterations, 32, 'sha256').toString('hex');
  return crypto.timingSafeEqual(Buffer.from(actual, 'hex'), Buffer.from(expected, 'hex'));
}

async function ensureTables() {
  await sql`
    create table if not exists app_accounts (
      id text primary key,
      username text not null unique,
      password_hash text not null,
      full_name text not null default '',
      status text not null default 'active',
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now()
    )
  `;
  await sql`
    create table if not exists app_stores (
      id text primary key,
      owner_account_id text not null references app_accounts(id) on delete cascade,
      name text not null default 'My Store',
      status text not null default 'active',
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now()
    )
  `;
  await sql`
    create table if not exists app_subscriptions (
      id text primary key,
      store_id text not null references app_stores(id) on delete cascade,
      plan text not null default 'trial',
      status text not null default 'trial',
      trial_ends_at timestamptz,
      devices_limit integer not null default 2,
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now()
    )
  `;
}

export default async function handler(req, res) {
  try {
    await ensureTables();
    if (req.method !== 'POST') return res.status(405).json({ ok: false, error: 'Method not allowed' });

    const body = req.body || {};
    const username = normalizeUsername(body.username);
    const password = String(body.password || '');
    if (!username || !password) return res.status(400).json({ ok: false, error: 'Username and password are required.' });

    const rows = await sql`
      select a.id as account_id, a.password_hash, a.status as account_status,
             s.id as store_id, sub.status as subscription_status,
             sub.trial_ends_at, sub.devices_limit
      from app_accounts a
      left join app_stores s on s.owner_account_id = a.id
      left join app_subscriptions sub on sub.store_id = s.id
      where a.username = ${username}
      order by s.created_at asc
      limit 1
    `;
    if (!rows.length) return res.status(401).json({ ok: false, error: 'Invalid username or password.' });
    const row = rows[0];
    if (row.account_status !== 'active') return res.status(403).json({ ok: false, error: 'Account is not active.' });
    if (!verifyPassword(password, row.password_hash)) return res.status(401).json({ ok: false, error: 'Invalid username or password.' });

    return res.status(200).json({
      ok: true,
      message: 'Online account verified.',
      accountId: row.account_id,
      storeId: row.store_id || '',
      subscriptionStatus: row.subscription_status || '',
      trialEndsAt: row.trial_ends_at ? new Date(row.trial_ends_at).toISOString() : null,
      devicesLimit: Number(row.devices_limit || 0) || null,
    });
  } catch (error) {
    return sendError(res, error);
  }
}
