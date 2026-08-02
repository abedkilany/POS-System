import { randomBytes, createHash, timingSafeEqual } from 'crypto';
import {
  sql,
  assertAccountOrDevice,
  assertStoreAllowed,
  sendError,
} from '../../_db.js';

async function ensurePairingTable() {
  await sql`
    create table if not exists device_pairing_codes (
      code text primary key,
      store_id text not null,
      branch_id text not null default 'main',
      host_device_id text not null,
      host_device_name text default '',
      transport text not null,
      expires_at timestamptz not null,
      claimed_by_device_id text default '',
      claimed_at timestamptz,
      created_at timestamptz not null default now()
    )
  `;
  await sql`create index if not exists idx_device_pairing_codes_store on device_pairing_codes (store_id, branch_id, expires_at desc)`;
}

function normalizeRecoveryKey(value) {
  return String(value || '').trim().toUpperCase();
}

function hashRecoveryKey(value) {
  return createHash('sha256').update(normalizeRecoveryKey(value), 'utf8').digest('hex');
}

async function ensureRecoveryTable() {
  await sql`
    create table if not exists store_recovery_keys (
      store_id text not null,
      branch_id text not null default 'main',
      recovery_key_hash text not null,
      latest_host_device_id text default '',
      control_plane_tenant_id text default '',
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now(),
      primary key (store_id, branch_id)
    )
  `;
  await sql`alter table store_devices add column if not exists device_public_key text default ''`;
}


async function ensureStoreDevicesTable() {
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
      wipe_requested_at timestamptz,
      device_token text default '',
      host_device_id text default '',
      active_transport text default '',
      last_sync_transport text default '',
      last_applied_cursor timestamptz,
      last_ack_cursor timestamptz,
      last_applied_sequence bigint not null default 0,
      last_ack_sequence bigint not null default 0,
      last_ack_at timestamptz,
      online boolean not null default false,
      last_seen_at timestamptz not null default now(),
      updated_at timestamptz not null default now(),
      primary key (store_id, branch_id, device_id)
    )
  `;
}

async function authorizeLocalHostOrAccount(req, {
  storeId,
  branchId,
  hostDeviceId,
  hostDeviceName,
  hostDevicePublicKey,
  recoveryKey,
  transport,
}) {
  try {
    await assertAccountOrDevice(req, {
      storeId,
      branchId,
      allowedRoles: ['host'],
      allowedTransports: transport === 'direct' || transport === 'lan'
        ? [transport]
        : [],
    });
    return;
  } catch (accountOrDeviceError) {
    throw accountOrDeviceError;
  }

  if (!recoveryKey) {
    const err = new Error('Recovery Key is required to create a remote pairing code from a local Host.');
    err.statusCode = 401;
    throw err;
  }

  const existing = await sql`
    select recovery_key_hash
    from store_recovery_keys
    where store_id = ${storeId}
      and branch_id = ${branchId}
    limit 1
  `;
  if (existing.length && existing[0].recovery_key_hash) {
    const expectedHash = String(existing[0].recovery_key_hash || '');
    const providedHash = hashRecoveryKey(recoveryKey);
    const a = Buffer.from(expectedHash, 'hex');
    const b = Buffer.from(providedHash, 'hex');
    if (a.length !== b.length || !timingSafeEqual(a, b)) {
      const err = new Error('Invalid Recovery Key for this Store ID.');
      err.statusCode = 403;
      throw err;
    }
  }

  const deviceToken = String(req.headers['x-device-token'] || req.headers['X-Device-Token'] || '').trim();
  await ensureStoreDevicesTable();
  await sql`
    insert into store_devices (
      store_id, branch_id, device_id, device_name, role, transport, active_transport,
      last_sync_transport, device_token, host_device_id, device_public_key, online, last_seen_at, updated_at
    ) values (
      ${storeId}, ${branchId}, ${hostDeviceId}, ${hostDeviceName}, 'host', ${transport}, ${transport},
      ${transport}, ${deviceToken}, ${hostDeviceId}, ${hostDevicePublicKey}, true, now(), now()
    )
    on conflict (store_id, branch_id, device_id) do update set
      device_name = excluded.device_name,
      role = 'host',
      transport = excluded.transport,
      active_transport = excluded.active_transport,
      last_sync_transport = excluded.last_sync_transport,
      device_token = case when excluded.device_token <> '' then excluded.device_token else store_devices.device_token end,
      host_device_id = excluded.host_device_id,
      device_public_key = case when excluded.device_public_key <> '' then excluded.device_public_key else store_devices.device_public_key end,
      revoked = false,
      suspended = false,
      online = true,
      last_seen_at = now(),
      updated_at = now()
  `;
}

function makeCode() {
  // Mixed-case alphanumeric pairing code. Ambiguous characters are omitted
  // to reduce copy/scan mistakes while keeping much higher entropy than 6 digits.
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';
  const bytes = randomBytes(14);
  let raw = '';
  for (const byte of bytes) raw += alphabet[byte % alphabet.length];
  return `${raw.slice(0, 4)}-${raw.slice(4, 8)}-${raw.slice(8, 12)}-${raw.slice(12, 14)}`;
}

export default async function handler(req, res) {
  try {
    if (req.method !== 'POST') return res.status(405).json({ ok: false, error: 'Method not allowed' });
    await ensurePairingTable();
    await ensureRecoveryTable();
    const body = req.body || {};
    const storeId = String(body.storeId || body.store_id || '').trim();
    const branchId = String(body.branchId || body.branch_id || 'main').trim() || 'main';
    const hostDeviceId = String(body.hostDeviceId || body.host_device_id || body.deviceId || '').trim();
    const hostDeviceName = String(body.hostDeviceName || body.host_device_name || '').trim();
    const hostDevicePublicKey = String(body.devicePublicKey || body.device_public_key || '').trim();
    const requestedTransport = String(body.transport || 'direct').trim().toLowerCase();
    const transport = requestedTransport === 'lan' || requestedTransport === 'direct'
      ? requestedTransport
      : '';
    if (!transport) return res.status(400).json({ ok: false, error: 'transport must be lan or direct.' });
    const ttlMinutes = Math.min(Math.max(Number(body.ttlMinutes || body.ttl_minutes || 5), 1), 30);
    const recoveryKey = normalizeRecoveryKey(body.recoveryKey || body.recovery_key);
    if (!storeId) return res.status(400).json({ ok: false, error: 'storeId is required.' });
    if (!hostDeviceId) return res.status(400).json({ ok: false, error: 'hostDeviceId is required.' });
    assertStoreAllowed(storeId);
    await authorizeLocalHostOrAccount(req, {
      storeId,
      branchId,
      hostDeviceId,
      hostDeviceName,
      hostDevicePublicKey,
      recoveryKey,
      transport,
    });

    await sql`delete from device_pairing_codes where expires_at < now() or claimed_at is not null`;
    const requestedCode = String(body.code || '').trim();
    const codePattern = /^[A-Za-z0-9]{16}$/;
    let code = codePattern.test(requestedCode) ? requestedCode : makeCode();
    for (let attempt = 0; attempt < 5; attempt += 1) {
      const existing = await sql`select code from device_pairing_codes where code = ${code} limit 1`;
      if (!existing.length) break;
      code = makeCode();
    }

    if (recoveryKey) {
      await sql`
        insert into store_recovery_keys (store_id, branch_id, recovery_key_hash, latest_host_device_id, updated_at)
        values (${storeId}, ${branchId}, ${hashRecoveryKey(recoveryKey)}, ${hostDeviceId}, now())
        on conflict (store_id, branch_id) do update set
          recovery_key_hash = excluded.recovery_key_hash,
          latest_host_device_id = excluded.latest_host_device_id,
          updated_at = now()
      `;
    }

    const rows = await sql`
      insert into device_pairing_codes (code, store_id, branch_id, host_device_id, host_device_name, transport, expires_at)
      values (${code}, ${storeId}, ${branchId}, ${hostDeviceId}, ${hostDeviceName}, ${transport}, now() + (${ttlMinutes} || ' minutes')::interval)
      returning code, store_id, branch_id, host_device_id, host_device_name, transport, expires_at
    `;
    const row = rows[0];
    return res.status(200).json({
      ok: true,
      code: row.code,
      storeId: row.store_id,
      branchId: row.branch_id,
      hostDeviceId: row.host_device_id,
      hostDeviceName: row.host_device_name || '',
      transport: row.transport,
      expiresAt: row.expires_at instanceof Date ? row.expires_at.toISOString() : new Date(row.expires_at).toISOString(),
    });
  } catch (error) {
    sendError(res, error);
  }
}
