import crypto from 'crypto';
import { sql, sendError } from '../_db.js';

function normalizePart(value) {
  return String(value || '').trim().toLowerCase();
}

function randomId(prefix) {
  return `${prefix}_${crypto.randomBytes(12).toString('hex')}`;
}

function ventioId(prefix) {
  return `${prefix}-${crypto.randomBytes(3).toString('hex').toUpperCase()}`;
}

function hashPassword(password) {
  const salt = crypto.randomBytes(16).toString('hex');
  const hash = crypto.pbkdf2Sync(String(password), salt, 120000, 32, 'sha256').toString('hex');
  return `pbkdf2_sha256$120000$${salt}$${hash}`;
}

function createAccountToken({ accountId, username, storeSlug, storeId, branchId }) {
  const secret = process.env.ACCOUNT_JWT_SECRET || process.env.ADMIN_JWT_SECRET || '';
  if (!secret) return '';
  const payload = {
    type: 'store_account',
    accountId,
    username,
    namespace: storeSlug,
    storeId,
    branchId,
    exp: Math.floor(Date.now() / 1000) + 30 * 24 * 60 * 60,
  };
  const payloadB64 = Buffer.from(JSON.stringify(payload)).toString('base64url');
  const signature = crypto.createHmac('sha256', secret).update(payloadB64).digest('base64url');
  return `${payloadB64}.${signature}`;
}

function isValidSlug(value) {
  return /^[a-z0-9][a-z0-9_-]{2,31}$/.test(value);
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
      slug text,
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

  await sql`alter table app_accounts add column if not exists namespace_slug text not null default ''`;
  await sql`alter table app_accounts add column if not exists account_type text not null default 'store_owner'`;
  await sql`alter table app_stores add column if not exists slug text`;
  await sql`alter table app_stores add column if not exists branch_id text not null default 'BR-MAIN'`;
  await sql`alter table app_stores add column if not exists cloud_sync_enabled boolean not null default false`;

  await sql`
    update app_stores
    set slug = lower(regexp_replace(coalesce(nullif(name, ''), id), '[^a-zA-Z0-9_-]+', '', 'g'))
    where slug is null or trim(slug) = ''
  `;
  await sql`update app_stores set slug = id where slug is null or trim(slug) = ''`;
  await sql`
    update app_accounts a
    set namespace_slug = s.slug
    from app_stores s
    where s.owner_account_id = a.id
      and (a.namespace_slug is null or trim(a.namespace_slug) = '')
  `;

  await sql`alter table app_stores alter column slug set not null`;
  await sql`alter table app_accounts alter column namespace_slug set not null`;
  await sql`alter table app_accounts drop constraint if exists app_accounts_username_key`;
  await sql`create unique index if not exists app_stores_slug_key on app_stores (slug)`;
  await sql`create unique index if not exists app_accounts_username_namespace_key on app_accounts (username, namespace_slug)`;
}

export default async function handler(req, res) {
  try {
    await ensureTables();
    if (req.method !== 'POST') return res.status(405).json({ ok: false, error: 'Method not allowed' });

    const body = req.body || {};
    const username = normalizePart(body.username);
    const password = String(body.password || '');
    const fullName = String(body.fullName || body.full_name || 'Administrator').trim() || 'Administrator';
    const storeNameInput = String(body.storeName || body.store_name || '').trim();
    const storeSlug = normalizePart(storeNameInput);
    const trialDays = Math.min(Math.max(Number(body.trialDays || body.trial_days || 14), 1), 365);

    if (username.includes('@')) return res.status(400).json({ ok: false, error: 'Use username only during registration. Online login will be username@store.' });
    if (!isValidSlug(username)) return res.status(400).json({ ok: false, error: 'Username must be 3-32 characters: letters, numbers, underscore, or hyphen. No spaces.' });
    if (!isValidSlug(storeSlug)) return res.status(400).json({ ok: false, error: 'Store name must be 3-32 characters: letters, numbers, underscore, or hyphen. No spaces.' });
    if (storeSlug === 'ventio') return res.status(400).json({ ok: false, error: 'This store name is reserved.' });
    if (password.trim().length < 6) return res.status(400).json({ ok: false, error: 'Password must be at least 6 characters.' });

    const existingStore = await sql`select id from app_stores where slug = ${storeSlug} limit 1`;
    if (existingStore.length) return res.status(409).json({ ok: false, error: 'Store name already exists.' });

    const existingAccount = await sql`select id from app_accounts where username = ${username} and namespace_slug = ${storeSlug} limit 1`;
    if (existingAccount.length) return res.status(409).json({ ok: false, error: 'Username already exists for this store.' });

    const accountId = randomId('acct');
    const storeId = ventioId('ST');
    const branchId = ventioId('BR');
    const subscriptionId = randomId('sub');
    const passwordHash = hashPassword(password);
    const trialEndsAt = new Date(Date.now() + trialDays * 24 * 60 * 60 * 1000).toISOString();
    const accountToken = createAccountToken({ accountId, username, storeSlug, storeId, branchId });

    await sql`
      insert into app_accounts (id, username, namespace_slug, password_hash, full_name, account_type)
      values (${accountId}, ${username}, ${storeSlug}, ${passwordHash}, ${fullName}, 'store_owner')
    `;
    await sql`
      insert into app_stores (id, owner_account_id, branch_id, slug, name)
      values (${storeId}, ${accountId}, ${branchId}, ${storeSlug}, ${storeNameInput || storeSlug})
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
      branchId,
      username,
      storeSlug,
      storeName: storeNameInput || storeSlug,
      loginName: `${username}@${storeSlug}`,
      subscriptionStatus: 'trial',
      trialEndsAt,
      devicesLimit: 2,
      accountToken,
      cloudSyncEnabled: false,
    });
  } catch (error) {
    return sendError(res, error);
  }
}
