import { randomBytes } from 'crypto';
import { sql, assertStoreAllowed, accountTokenFromRequest, sendError, getClientDeviceLimitStatus } from '../../_db.js';
import { notifySyncChanged } from '../realtime.js';

function asIso(value) {
  return value instanceof Date ? value.toISOString() : new Date(value).toISOString();
}

function normalize(value) {
  return String(value || '').trim().toUpperCase();
}

function makeDeviceToken() {
  return `device_${Date.now()}_${randomBytes(24).toString('base64url')}`;
}

function makeEventId() {
  return `host_changed_${Date.now()}_${randomBytes(8).toString('hex')}`;
}

async function ensureRecoveryTables() {
  await sql`
    create table if not exists store_devices (
      store_id text not null,
      branch_id text not null default 'main',
      device_id text not null,
      device_name text default '',
      platform text default '',
      app_version text default '',
      role text not null default 'client',
      transport text not null default 'cloud',
      store_epoch integer not null default 1,
      device_token text default '',
      host_device_id text default '',
      active_transport text default '',
      last_sync_transport text default '',
      revoked boolean not null default false,
      suspended boolean not null default false,
      wipe_pending boolean not null default false,
      online boolean not null default false,
      last_seen_at timestamptz not null default now(),
      updated_at timestamptz not null default now(),
      primary key (store_id, branch_id, device_id)
    )
  `;
  await sql`alter table store_devices add column if not exists host_device_id text default ''`;
  await sql`alter table store_devices add column if not exists active_transport text default ''`;
  await sql`alter table store_devices add column if not exists last_sync_transport text default ''`;
  await sql`alter table store_devices add column if not exists suspended boolean not null default false`;
  await sql`alter table store_devices add column if not exists wipe_pending boolean not null default false`;
  await sql`alter table store_devices add column if not exists online boolean not null default false`;
  await sql`alter table app_stores add column if not exists cloud_sync_enabled boolean not null default false`;
  await sql`
    create table if not exists store_recovery_keys (
      store_id text not null,
      branch_id text not null default 'main',
      recovery_key_hash text not null default '',
      latest_host_device_id text default '',
      cloud_tenant_id text default '',
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now(),
      primary key (store_id, branch_id)
    )
  `;
  await sql`alter table store_recovery_keys alter column recovery_key_hash set default ''`;
  await sql`
    create table if not exists cloud_sync_sequences (
      store_id text not null,
      branch_id text not null default 'main',
      last_sequence bigint not null default 0,
      updated_at timestamptz not null default now(),
      primary key (store_id, branch_id)
    )
  `;
  await sql`
    create table if not exists sync_events (
      id text primary key,
      store_id text not null,
      branch_id text not null default 'main',
      device_id text not null,
      entity_type text not null,
      entity_id text not null,
      operation text not null,
      payload jsonb not null default '{}'::jsonb,
      created_at timestamptz not null default now()
    )
  `;
  await sql`alter table sync_events add column if not exists store_epoch integer not null default 1`;
  await sql`alter table sync_events add column if not exists sequence bigint not null default 0`;
  await sql`alter table sync_events add column if not exists event_id text default ''`;
  await sql`alter table sync_events add column if not exists request_id text default ''`;
  await sql`alter table sync_events add column if not exists source_command_id text default ''`;
}

async function allocateServerSequence(storeId, branchId) {
  const rows = await sql`
    insert into cloud_sync_sequences (store_id, branch_id, last_sequence, updated_at)
    values (${storeId}, ${branchId || 'main'}, 1, now())
    on conflict (store_id, branch_id) do update set
      last_sequence = cloud_sync_sequences.last_sequence + 1,
      updated_at = now()
    returning last_sequence
  `;
  return Number(rows[0]?.last_sequence || 0);
}

async function storeForAccount({ accountId, storeId, branchId }) {
  const rows = await sql`
    select s.id as store_id, s.branch_id, s.owner_account_id, s.slug, s.name,
           s.cloud_sync_enabled,
           a.username as account_username,
           a.namespace_slug as account_namespace_slug,
           coalesce(r.cloud_tenant_id, '') as cloud_tenant_id,
           coalesce(r.latest_host_device_id, '') as latest_host_device_id
    from app_stores s
    join app_accounts a on a.id = s.owner_account_id
    left join store_recovery_keys r on r.store_id = s.id and r.branch_id = s.branch_id
    where s.id = ${storeId}
      and s.owner_account_id = ${accountId}
      and (${branchId || ''} = '' or s.branch_id = ${branchId || ''})
    limit 1
  `;
  return rows[0] || null;
}

export default async function handler(req, res) {
  try {
    await ensureRecoveryTables();
    if (req.method !== 'POST') return res.status(405).json({ ok: false, error: 'Method not allowed' });

    const body = req.body || {};
    const storeId = normalize(body.storeId || body.store_id);
    const requestedBranchId = normalize(body.branchId || body.branch_id);
    const deviceId = String(body.deviceId || body.device_id || '').trim();
    const deviceName = String(body.deviceName || body.device_name || '').trim();
    const platform = String(body.platform || '').trim();
    const appVersion = String(body.appVersion || body.app_version || '').trim();

    if (!storeId || !storeId.startsWith('ST-')) return res.status(400).json({ ok: false, error: 'A valid Store ID is required.' });
    if (!deviceId) return res.status(400).json({ ok: false, error: 'deviceId is required.' });
    assertStoreAllowed(storeId);

    const account = accountTokenFromRequest(req);
    if (!account) return res.status(401).json({ ok: false, error: 'Invalid or missing online account session.' });
    if (String(account.storeId || '') !== storeId) {
      return res.status(403).json({ ok: false, error: 'This account is not allowed to recover the requested store.' });
    }

    const store = await storeForAccount({
      accountId: String(account.accountId || ''),
      storeId,
      branchId: requestedBranchId,
    });
    if (!store) {
      return res.status(404).json({ ok: false, error: 'Store was not found for this account.' });
    }

    const recoveredBranchId = store.branch_id || requestedBranchId || 'BR-MAIN1';
    const oldHostRows = await sql`
      select device_id
      from store_devices
      where store_id = ${storeId}
        and branch_id = ${recoveredBranchId}
        and role = 'host'
        and device_id <> ${deviceId}
      order by updated_at desc
      limit 1
    `;
    const oldHostDeviceId = oldHostRows[0]?.device_id || store.latest_host_device_id || '';
    const deviceLimit = await getClientDeviceLimitStatus(storeId);
    if (oldHostDeviceId && oldHostDeviceId !== deviceId && deviceLimit.limitReached) {
      return res.status(409).json({
        ok: false,
        code: 'DEVICE_LIMIT_REACHED',
        error: 'You have reached the connected devices limit. Delete one linked device before converting the current Host to a Client.',
        deviceLimit,
      });
    }
    const deviceToken = makeDeviceToken();
    const cloudTenantId = store.cloud_tenant_id || '';

    await sql`
      update store_devices
      set role = case when device_id = ${deviceId} then 'host' else role end,
          host_device_id = ${deviceId},
          active_transport = case when coalesce(active_transport, '') = '' then 'cloud' else active_transport end,
          last_sync_transport = case when coalesce(last_sync_transport, '') = '' then 'cloud' else last_sync_transport end,
          updated_at = now()
      where store_id = ${storeId}
        and branch_id = ${recoveredBranchId}
    `;

    if (oldHostDeviceId && oldHostDeviceId !== deviceId) {
      await sql`
        update store_devices
        set role = 'client', host_device_id = ${deviceId}, updated_at = now()
        where store_id = ${storeId}
          and branch_id = ${recoveredBranchId}
          and device_id = ${oldHostDeviceId}
      `;
    }

    await sql`
      insert into store_devices (
        store_id, branch_id, device_id, device_name, platform, app_version, role, transport, active_transport, last_sync_transport, device_token, host_device_id, revoked, suspended, wipe_pending, online, last_seen_at, updated_at
      ) values (
        ${storeId}, ${recoveredBranchId}, ${deviceId}, ${deviceName}, ${platform}, ${appVersion}, 'host', 'cloud', 'cloud', 'cloud', ${deviceToken}, ${deviceId}, false, false, false, true, now(), now()
      )
      on conflict (store_id, branch_id, device_id) do update set
        device_name = excluded.device_name,
        platform = excluded.platform,
        app_version = excluded.app_version,
        role = 'host',
        transport = 'cloud',
        active_transport = 'cloud',
        last_sync_transport = 'cloud',
        device_token = excluded.device_token,
        host_device_id = excluded.host_device_id,
        revoked = false,
        suspended = false,
        wipe_pending = false,
        online = true,
        last_seen_at = now(),
        updated_at = now()
    `;

    await sql`
      insert into store_recovery_keys (store_id, branch_id, recovery_key_hash, latest_host_device_id, cloud_tenant_id, updated_at)
      values (${storeId}, ${recoveredBranchId}, '', ${deviceId}, ${cloudTenantId}, now())
      on conflict (store_id, branch_id) do update set
        latest_host_device_id = excluded.latest_host_device_id,
        cloud_tenant_id = case when excluded.cloud_tenant_id <> '' then excluded.cloud_tenant_id else store_recovery_keys.cloud_tenant_id end,
        updated_at = now()
    `;

    const eventId = makeEventId();
    const sequence = await allocateServerSequence(storeId, recoveredBranchId);
    const payload = {
      storeId,
      branchId: recoveredBranchId,
      oldHostDeviceId,
      newHostDeviceId: deviceId,
      activatedAt: asIso(new Date()),
      reason: 'store_recovery_promote_host',
      _syncV2: { kind: 'hostChanged', eventId },
    };
    await sql`
      insert into sync_events (
        id, store_id, branch_id, device_id, entity_type, entity_id, operation, payload, created_at, store_epoch, sequence, event_id, request_id, source_command_id
      ) values (
        ${eventId}, ${storeId}, ${recoveredBranchId}, ${deviceId}, 'host_transfer', ${deviceId}, 'HOST_CHANGED', ${JSON.stringify(payload)}, now(), 1, ${sequence}, ${eventId}, '', ''
      )
      on conflict (id) do nothing
    `;
    notifySyncChanged({ storeId, branchId: recoveredBranchId, latestSequence: sequence });

    return res.status(200).json({
      ok: true,
      storeId,
      branchId: recoveredBranchId,
      hostDeviceId: deviceId,
      oldHostDeviceId,
      deviceToken,
      cloudTenantId,
      hostChangedEventId: eventId,
      username: store.account_username || account.username || '',
      storeSlug: store.slug || store.account_namespace_slug || account.namespace || '',
      storeName: store.name || '',
      loginName: `${store.account_username || account.username || ''}@${store.slug || store.account_namespace_slug || account.namespace || ''}`,
      cloudSyncEnabled: store.cloud_sync_enabled === true,
      deviceLimit: await getClientDeviceLimitStatus(storeId),
      recoveredAt: asIso(new Date()),
    });
  } catch (error) {
    sendError(res, error);
  }
}
