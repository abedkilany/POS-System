import { randomBytes } from 'crypto';
import {
  sql,
  accountTokenFromRequest,
  assertDirectSyncEnabled,
  assertStoreAllowed,
  enforceRateLimit,
  getClientDeviceLimitStatus,
  requestIp,
  sendError,
} from '../../_db.js';

function normalize(value) {
  return String(value || '').trim().toUpperCase();
}

function makeDeviceToken() {
  return `device_${Date.now()}_${randomBytes(24).toString('base64url')}`;
}

async function ensureDeviceTable() {
  await sql`
    create table if not exists store_devices (
      store_id text not null,
      branch_id text not null default 'main',
      device_id text not null,
      device_name text default '',
      platform text default '',
      role text default '',
      transport text default '',
      app_version text default '',
      store_epoch integer not null default 1,
      revoked boolean not null default false,
      suspended boolean not null default false,
      wipe_pending boolean not null default false,
      device_token text default '',
      host_device_id text default '',
      active_transport text default '',
      last_sync_transport text default '',
      online boolean not null default false,
      last_seen_at timestamptz not null default now(),
      updated_at timestamptz not null default now(),
      primary key (store_id, branch_id, device_id)
    )
  `;
}

export default async function handler(req, res) {
  try {
    if (req.method !== 'POST') {
      res.setHeader('Allow', 'POST, OPTIONS');
      return res.status(405).json({ ok: false, error: 'Method not allowed.' });
    }
    await enforceRateLimit({
      key: `recovery:claim:${requestIp(req)}`,
      limit: 10,
      windowSeconds: 10 * 60,
      message: 'Too many Store recovery attempts. Try again later.',
    });

    const body = req.body || {};
    const storeId = normalize(body.storeId || body.store_id);
    const requestedBranchId = normalize(body.branchId || body.branch_id);
    const deviceId = String(body.deviceId || body.device_id || '').trim();
    const deviceName = String(body.deviceName || body.device_name || '').trim();
    const platform = String(body.platform || '').trim();
    const appVersion = String(body.appVersion || body.app_version || '').trim();
    if (!storeId.startsWith('ST-')) {
      return res.status(400).json({ ok: false, error: 'A valid Store ID is required.' });
    }
    if (!deviceId) {
      return res.status(400).json({ ok: false, error: 'deviceId is required.' });
    }

    assertStoreAllowed(storeId);
    await assertDirectSyncEnabled(storeId);
    const account = await accountTokenFromRequest(req);
    if (!account) {
      return res.status(401).json({ ok: false, error: 'Invalid or missing online account session.' });
    }
    if (account.type !== 'store_account' || String(account.storeId || '') !== storeId) {
      return res.status(403).json({ ok: false, error: 'This account cannot recover the requested Store.' });
    }

    const stores = await sql`
      select s.id, s.branch_id, s.slug, s.name, s.owner_account_id,
             a.username, a.namespace_slug
      from app_stores s
      join app_accounts a on a.id = s.owner_account_id
      where s.id = ${storeId}
        and s.owner_account_id = ${String(account.accountId || '')}
        and (${requestedBranchId} = '' or s.branch_id = ${requestedBranchId})
      limit 1
    `;
    if (!stores.length) {
      return res.status(404).json({ ok: false, error: 'Store was not found for this account.' });
    }
    const store = stores[0];
    const branchId = normalize(store.branch_id || requestedBranchId || 'main');
    await ensureDeviceTable();
    const previousHosts = await sql`
      select device_id from store_devices
      where store_id = ${storeId} and branch_id = ${branchId}
        and role = 'host' and device_id <> ${deviceId}
      order by updated_at desc
      limit 1
    `;
    const oldHostDeviceId = String(previousHosts[0]?.device_id || '');
    const deviceToken = makeDeviceToken();

    await sql`
      update store_devices
      set role = case when role = 'host' then 'client' else role end,
          host_device_id = ${deviceId},
          updated_at = now()
      where store_id = ${storeId} and branch_id = ${branchId}
        and device_id <> ${deviceId}
    `;
    await sql`
      insert into store_devices (
        store_id, branch_id, device_id, device_name, platform, app_version,
        role, transport, active_transport, last_sync_transport, device_token,
        host_device_id, revoked, suspended, wipe_pending, online, last_seen_at, updated_at
      ) values (
        ${storeId}, ${branchId}, ${deviceId}, ${deviceName}, ${platform}, ${appVersion},
        'host', 'direct', 'direct', 'direct', ${deviceToken}, ${deviceId},
        false, false, false, true, now(), now()
      )
      on conflict (store_id, branch_id, device_id) do update set
        device_name = excluded.device_name,
        platform = excluded.platform,
        app_version = excluded.app_version,
        role = 'host',
        transport = 'direct',
        active_transport = 'direct',
        last_sync_transport = 'direct',
        device_token = excluded.device_token,
        host_device_id = excluded.host_device_id,
        revoked = false,
        suspended = false,
        wipe_pending = false,
        online = true,
        last_seen_at = now(),
        updated_at = now()
    `;

    const username = String(store.username || account.username || '');
    const slug = String(store.slug || store.namespace_slug || account.namespace || '');
    return res.status(200).json({
      ok: true,
      storeId,
      branchId,
      hostDeviceId: deviceId,
      oldHostDeviceId,
      deviceToken,
      controlPlaneTenantId: '',
      username,
      storeSlug: slug,
      storeName: String(store.name || ''),
      loginName: `${username}@${slug}`,
      directSyncEnabled: true,
      deviceLimit: await getClientDeviceLimitStatus(storeId),
      recoveredAt: new Date().toISOString(),
    });
  } catch (error) {
    return sendError(res, error);
  }
}
