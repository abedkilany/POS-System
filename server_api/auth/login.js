import crypto from 'crypto';
import { sql, sendError } from '../_db.js';

function normalizePart(value) {
  return String(value || '').trim().toLowerCase();
}

function parseLoginName(value) {
  const raw = String(value || '').trim().toLowerCase();
  const parts = raw.split('@');
  if (parts.length !== 2) return null;
  const username = normalizePart(parts[0]);
  const namespaceSlug = normalizePart(parts[1]);
  if (!username || !namespaceSlug) return null;
  return { username, namespaceSlug };
}


function createAdminToken(row) {
  const secret = process.env.ADMIN_JWT_SECRET || process.env.CLOUD_SYNC_TOKEN || '';
  if (!secret) return '';
  if (String(row.account_type || '') !== 'platform_admin') return '';
  if (String(row.namespace_slug || '') !== 'ventio') return '';
  const payload = {
    type: 'platform_admin',
    accountId: row.account_id,
    username: row.username,
    namespace: row.namespace_slug,
    exp: Math.floor(Date.now() / 1000) + 8 * 60 * 60,
  };
  const payloadB64 = Buffer.from(JSON.stringify(payload)).toString('base64url');
  const signature = crypto.createHmac('sha256', secret).update(payloadB64).digest('base64url');
  return `${payloadB64}.${signature}`;
}

function createAccountToken(row) {
  const secret = process.env.ACCOUNT_JWT_SECRET || process.env.ADMIN_JWT_SECRET || process.env.CLOUD_SYNC_TOKEN || '';
  if (!secret) return '';
  if (String(row.account_type || '') === 'platform_admin') return '';
  const payload = {
    type: 'store_account',
    accountId: row.account_id,
    username: row.username,
    namespace: row.namespace_slug,
    storeId: row.store_id || '',
    branchId: row.branch_id || '',
    exp: Math.floor(Date.now() / 1000) + 30 * 24 * 60 * 60,
  };
  const payloadB64 = Buffer.from(JSON.stringify(payload)).toString('base64url');
  const signature = crypto.createHmac('sha256', secret).update(payloadB64).digest('base64url');
  return `${payloadB64}.${signature}`;
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
    const parsed = parseLoginName(body.username || body.loginName || body.login_name);
    const password = String(body.password || '');
    if (!parsed || !password) {
      return res.status(400).json({ ok: false, error: 'Online login must be username@store and password.' });
    }

    const rows = await sql`
      select a.id as account_id, a.username, a.namespace_slug, a.password_hash,
             a.status as account_status, a.account_type,
             s.id as store_id, s.branch_id, s.slug as store_slug, s.name as store_name,
             s.cloud_sync_enabled,
             sub.status as subscription_status, sub.trial_ends_at, sub.devices_limit
      from app_accounts a
      left join app_stores s on s.owner_account_id = a.id and s.slug = a.namespace_slug
      left join app_subscriptions sub on sub.store_id = s.id
      where a.username = ${parsed.username}
        and a.namespace_slug = ${parsed.namespaceSlug}
      order by s.created_at asc
      limit 1
    `;
    if (!rows.length) return res.status(401).json({ ok: false, error: 'Invalid username or password.' });
    const row = rows[0];
    if (row.account_status !== 'active') return res.status(403).json({ ok: false, error: 'Account is not active.' });
    if (!verifyPassword(password, row.password_hash)) return res.status(401).json({ ok: false, error: 'Invalid username or password.' });

    const adminToken = createAdminToken(row);
    const accountToken = createAccountToken(row);

    return res.status(200).json({
      ok: true,
      message: 'Online account verified.',
      accountId: row.account_id,
      storeId: row.store_id || '',
      branchId: row.branch_id || '',
      username: row.username,
      storeSlug: row.store_slug || row.namespace_slug || '',
      storeName: row.store_name || '',
      loginName: `${row.username}@${row.namespace_slug}`,
      accountType: row.account_type || 'store_owner',
      subscriptionStatus: row.subscription_status || '',
      trialEndsAt: row.trial_ends_at ? new Date(row.trial_ends_at).toISOString() : null,
      devicesLimit: Number(row.devices_limit || 0) || null,
      adminToken,
      accountToken,
      cloudSyncEnabled: row.cloud_sync_enabled === true,
    });
  } catch (error) {
    return sendError(res, error);
  }
}
