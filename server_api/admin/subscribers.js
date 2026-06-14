import crypto from 'crypto';
import { sql, sendError } from '../_db.js';

function base64url(input) {
  return Buffer.from(input).toString('base64url');
}

function getAdminSecret() {
  return process.env.ADMIN_JWT_SECRET || process.env.CLOUD_SYNC_TOKEN || '';
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
    if (!crypto.timingSafeEqual(Buffer.from(signature), Buffer.from(expected))) {
      return false;
    }
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

async function ensureTables() {
  await sql`alter table app_accounts add column if not exists namespace_slug text not null default ''`;
  await sql`alter table app_accounts add column if not exists account_type text not null default 'store_owner'`;
  await sql`alter table app_stores add column if not exists slug text`;
}

export default async function handler(req, res) {
  try {
    await ensureTables();
    assertAdmin(req);
    if (req.method !== 'GET') return res.status(405).json({ ok: false, error: 'Method not allowed' });

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

    return res.status(200).json({
      ok: true,
      subscribers: rows,
      summary: summaryRows[0] || {},
    });
  } catch (error) {
    return sendError(res, error);
  }
}
