import crypto from 'crypto';
import { sql, sendError } from '../_db.js';

function getAdminSecret() {
  return process.env.ADMIN_JWT_SECRET || '';
}

function verifyAdminToken(token) {
  const secret = getAdminSecret();
  if (!secret) return false;
  const parts = String(token || '').split('.');
  if (parts.length !== 2) return false;
  const [payloadB64, signature] = parts;
  const expected = crypto
    .createHmac('sha256', secret)
    .update(payloadB64)
    .digest('base64url');
  try {
    if (!crypto.timingSafeEqual(Buffer.from(signature), Buffer.from(expected))) return false;
  } catch (_) {
    return false;
  }
  try {
    const payload = JSON.parse(Buffer.from(payloadB64, 'base64url').toString('utf8'));
    if (payload?.type !== 'platform_admin') return false;
    if (String(payload?.namespace || '') !== 'ventio') return false;
    if (Number(payload?.exp || 0) < Math.floor(Date.now() / 1000)) return false;
    return true;
  } catch (_) {
    return false;
  }
}

function assertAdmin(req) {
  const header = req.headers.authorization || req.headers.Authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7).trim() : '';
  if (!verifyAdminToken(token)) {
    const err = new Error('Admin access is required. Sign in as admin@ventio.');
    err.statusCode = 401;
    throw err;
  }
}

function bodyOf(req) {
  if (req.body && typeof req.body === 'object') return req.body;
  if (typeof req.body === 'string' && req.body.trim()) return JSON.parse(req.body);
  return {};
}

function cleanSlug(input) {
  return String(input || '')
    .trim()
    .toLowerCase()
    .replace(/\s+/g, '')
    .replace(/[^a-z0-9_-]/g, '');
}

function cleanSimple(input) {
  return String(input || '').trim().toLowerCase().replace(/\s+/g, '');
}

function requireText(value, label) {
  const text = String(value || '').trim();
  if (!text) {
    const err = new Error(`${label} is required.`);
    err.statusCode = 400;
    throw err;
  }
  return text;
}

async function ensureTables() {
  await sql`alter table app_accounts add column if not exists namespace_slug text not null default ''`;
  await sql`alter table app_accounts add column if not exists account_type text not null default 'store_owner'`;
  await sql`alter table app_stores add column if not exists slug text`;
  await sql`alter table app_stores add column if not exists cloud_sync_enabled boolean not null default false`;
  await sql`update app_stores set slug = lower(regexp_replace(name, '[^a-zA-Z0-9_-]+', '', 'g')) where slug is null or slug = ''`;
  await sql`alter table app_stores alter column slug set not null`;
  await sql`create unique index if not exists app_stores_slug_key on app_stores(slug)`;
}

async function listSubscribers(res) {
  const rows = await sql`
    select
      a.id as account_id,
      a.username,
      a.namespace_slug,
      a.full_name,
      a.account_type,
      a.status as account_status,
      a.created_at as account_created_at,
      s.id as store_id,
      s.slug as store_slug,
      s.name as store_name,
      s.status as store_status,
      s.cloud_sync_enabled,
      sub.id as subscription_id,
      sub.plan,
      sub.status as subscription_status,
      sub.trial_ends_at,
      sub.devices_limit,
      coalesce(dev.device_count, 0) as device_count,
      dev.last_seen_at
    from app_accounts a
    left join app_stores s on s.owner_account_id = a.id
    left join app_subscriptions sub on sub.store_id = s.id
    left join (
      select store_id, count(*)::int as device_count, max(last_seen_at) as last_seen_at
      from store_devices
      group by store_id
    ) dev on dev.store_id = s.id
    where coalesce(a.namespace_slug, '') <> 'ventio'
    order by a.created_at desc
    limit 500
  `;

  const summaryRows = await sql`
    select
      count(*)::int as accounts,
      count(distinct s.id)::int as stores,
      count(*) filter (where sub.status = 'trial')::int as trial_subscriptions,
      count(*) filter (where sub.status = 'active')::int as active_subscriptions,
      count(*) filter (where sub.trial_ends_at is not null and sub.trial_ends_at < now())::int as expired_trials
    from app_accounts a
    left join app_stores s on s.owner_account_id = a.id
    left join app_subscriptions sub on sub.store_id = s.id
    where coalesce(a.namespace_slug, '') <> 'ventio'
  `;

  return res.status(200).json({ ok: true, subscribers: rows, summary: summaryRows[0] || {} });
}

async function updateSubscriber(req, res) {
  const body = bodyOf(req);
  const accountId = requireText(body.accountId || body.account_id, 'Account id');
  const accountRows = await sql`
    select a.id, a.account_type, s.id as store_id, s.slug as store_slug, sub.id as subscription_id
    from app_accounts a
    left join app_stores s on s.owner_account_id = a.id
    left join app_subscriptions sub on sub.store_id = s.id
    where a.id = ${accountId}
    limit 1
  `;
  if (!accountRows.length) return res.status(404).json({ ok: false, error: 'Subscriber was not found.' });
  if (String(accountRows[0].account_type || '') === 'platform_admin') {
    return res.status(403).json({ ok: false, error: 'Platform admin accounts cannot be edited here.' });
  }
  const storeId = String(accountRows[0].store_id || '');
  const subscriptionId = String(accountRows[0].subscription_id || '');

  const username = cleanSimple(body.username);
  const fullName = String(body.fullName ?? body.full_name ?? '').trim();
  const accountStatus = cleanSimple(body.accountStatus ?? body.account_status ?? 'active') || 'active';
  const storeName = requireText(body.storeName ?? body.store_name, 'Store name');
  const storeSlug = cleanSlug(body.storeSlug ?? body.store_slug ?? storeName);
  const storeStatus = cleanSimple(body.storeStatus ?? body.store_status ?? 'active') || 'active';
  const plan = cleanSimple(body.plan || 'trial') || 'trial';
  const subscriptionStatus = cleanSimple(body.subscriptionStatus ?? body.subscription_status ?? 'trial') || 'trial';
  const devicesLimit = Math.max(1, Number.parseInt(String(body.devicesLimit ?? body.devices_limit ?? '2'), 10) || 2);
  const cloudSyncEnabled = body.cloudSyncEnabled === true || body.cloud_sync_enabled === true;
  const trialEndsAtRaw = String(body.trialEndsAt ?? body.trial_ends_at ?? '').trim();

  if (!username) return res.status(400).json({ ok: false, error: 'Username is required.' });
  if (!storeSlug) return res.status(400).json({ ok: false, error: 'Store slug is invalid.' });
  if (storeSlug === 'ventio') return res.status(400).json({ ok: false, error: 'ventio is reserved for platform accounts.' });

  const userDuplicate = await sql`
    select id from app_accounts
    where username = ${username} and namespace_slug = ${storeSlug} and id <> ${accountId}
    limit 1
  `;
  if (userDuplicate.length) return res.status(409).json({ ok: false, error: 'This username already exists for the selected store.' });

  const storeDuplicate = await sql`
    select id from app_stores
    where slug = ${storeSlug} and id <> ${storeId}
    limit 1
  `;
  if (storeDuplicate.length) return res.status(409).json({ ok: false, error: 'Store name is already used by another subscriber.' });

  await sql`
    update app_accounts
    set username = ${username},
        namespace_slug = ${storeSlug},
        full_name = ${fullName},
        status = ${accountStatus},
        updated_at = now()
    where id = ${accountId}
  `;
  if (storeId) {
    await sql`
      update app_stores
      set name = ${storeName}, slug = ${storeSlug}, status = ${storeStatus}, cloud_sync_enabled = ${cloudSyncEnabled}, updated_at = now()
      where id = ${storeId}
    `;
  }
  if (subscriptionId) {
    if (trialEndsAtRaw) {
      await sql`
        update app_subscriptions
        set plan = ${plan}, status = ${subscriptionStatus}, devices_limit = ${devicesLimit}, trial_ends_at = ${trialEndsAtRaw}::timestamptz, updated_at = now()
        where id = ${subscriptionId}
      `;
    } else {
      await sql`
        update app_subscriptions
        set plan = ${plan}, status = ${subscriptionStatus}, devices_limit = ${devicesLimit}, trial_ends_at = null, updated_at = now()
        where id = ${subscriptionId}
      `;
    }
  }
  return res.status(200).json({ ok: true, message: 'Subscriber updated.' });
}

async function deleteSubscriber(req, res) {
  const body = bodyOf(req);
  const accountId = requireText(body.accountId || body.account_id, 'Account id');
  const rows = await sql`
    select a.id, a.account_type, s.id as store_id
    from app_accounts a
    left join app_stores s on s.owner_account_id = a.id
    where a.id = ${accountId}
    limit 1
  `;
  if (!rows.length) return res.status(404).json({ ok: false, error: 'Subscriber was not found.' });
  if (String(rows[0].account_type || '') === 'platform_admin') {
    return res.status(403).json({ ok: false, error: 'Platform admin accounts cannot be deleted here.' });
  }
  const storeId = String(rows[0].store_id || '');
  if (storeId) {
    await sql`delete from bootstrap_snapshot_sections where store_id = ${storeId}`;
    await sql`delete from bootstrap_snapshot_jobs where store_id = ${storeId}`;
    await sql`delete from cloud_change_requests where store_id = ${storeId}`;
    await sql`delete from cloud_sync_sequences where store_id = ${storeId}`;
    await sql`delete from device_pairing_codes where store_id = ${storeId}`;
    await sql`delete from entity_snapshots where store_id = ${storeId}`;
    await sql`delete from host_transfer_requests where store_id = ${storeId}`;
    await sql`delete from store_devices where store_id = ${storeId}`;
    await sql`delete from store_host_heartbeats where store_id = ${storeId}`;
    await sql`delete from store_recovery_keys where store_id = ${storeId}`;
    await sql`delete from sync_events where store_id = ${storeId}`;
    await sql`delete from unified_snapshot_chunks where store_id = ${storeId}`;
  }
  await sql`delete from app_accounts where id = ${accountId}`;
  return res.status(200).json({ ok: true, message: 'Subscriber deleted.' });
}

export default async function handler(req, res) {
  try {
    await ensureTables();
    assertAdmin(req);
    if (req.method === 'GET') return listSubscribers(res);
    if (req.method === 'PATCH' || req.method === 'PUT') return updateSubscriber(req, res);
    if (req.method === 'DELETE') return deleteSubscriber(req, res);
    return res.status(405).json({ ok: false, error: 'Method not allowed' });
  } catch (error) {
    return sendError(res, error);
  }
}
