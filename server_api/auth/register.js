import crypto from 'crypto';
import { sql, sendError } from '../_db.js';

function normalizeUsername(value) {
  return String(value || '').trim().toLowerCase();
}

function randomId(prefix) {
  return `${prefix}_${crypto.randomBytes(12).toString('hex')}`;
}

function hashPassword(password) {
  const salt = crypto.randomBytes(16).toString('hex');
  const hash = crypto.pbkdf2Sync(String(password), salt, 120000, 32, 'sha256').toString('hex');
  return `pbkdf2_sha256$120000$${salt}$${hash}`;
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
    const fullName = String(body.fullName || body.full_name || 'Administrator').trim() || 'Administrator';
    const storeName = String(body.storeName || body.store_name || 'My Store').trim() || 'My Store';
    const trialDays = Math.min(Math.max(Number(body.trialDays || body.trial_days || 14), 1), 365);

    if (username.length < 3) return res.status(400).json({ ok: false, error: 'Username must be at least 3 characters.' });
    if (password.trim().length < 6) return res.status(400).json({ ok: false, error: 'Password must be at least 6 characters.' });

    const existing = await sql`select id from app_accounts where username = ${username} limit 1`;
    if (existing.length) return res.status(409).json({ ok: false, error: 'Username already exists.' });

    const accountId = randomId('acct');
    const storeId = randomId('store');
    const subscriptionId = randomId('sub');
    const passwordHash = hashPassword(password);
    const trialEndsAt = new Date(Date.now() + trialDays * 24 * 60 * 60 * 1000).toISOString();

    await sql`
      insert into app_accounts (id, username, password_hash, full_name)
      values (${accountId}, ${username}, ${passwordHash}, ${fullName})
    `;
    await sql`
      insert into app_stores (id, owner_account_id, name)
      values (${storeId}, ${accountId}, ${storeName})
    `;
    await sql`
      insert into app_subscriptions (id, store_id, plan, status, trial_ends_at, devices_limit)
      values (${subscriptionId}, ${storeId}, 'trial', 'trial', ${trialEndsAt}, 2)
    `;

    return res.status(201).json({
      ok: true,
      message: 'Trial account created.',
      accountId,
      storeId,
      subscriptionStatus: 'trial',
      trialEndsAt,
      devicesLimit: 2,
    });
  } catch (error) {
    return sendError(res, error);
  }
}
