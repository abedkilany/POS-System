import { randomBytes } from 'crypto';
import { sql, assertStoreAllowed, ensureDeviceAuthColumns, sendError } from '../../_db.js';

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
      device_token text default '',
      last_seen_at timestamptz not null default now(),
      updated_at timestamptz not null default now(),
      primary key (store_id, branch_id, device_id)
    )
  `;
  await ensureDeviceAuthColumns();
}

function makeDeviceToken() {
  return `dev_${randomBytes(32).toString('base64url')}`;
}

export default async function handler(req, res) {
  try {
    // Claiming a pairing code must not require the Host deployment token.
    // The single-use pairing code is the Client's bootstrap secret.
    if (req.method !== 'POST') return res.status(405).json({ ok: false, error: 'Method not allowed' });
    await ensurePairingTable();
    await ensureDeviceTable();
    const body = req.body || {};
    const code = String(body.code || '').trim();
    const deviceId = String(body.deviceId || body.device_id || '').trim();
    const deviceName = String(body.deviceName || body.device_name || '').trim();
    const platform = String(body.platform || '').trim();
    const appVersion = String(body.appVersion || body.app_version || '').trim();
    if (!code) return res.status(400).json({ ok: false, error: 'Pairing code is required.' });
    if (!deviceId) return res.status(400).json({ ok: false, error: 'deviceId is required.' });

    const lookup = await sql`
      select code, store_id, branch_id, host_device_id, host_device_name, transport, expires_at, claimed_at
      from device_pairing_codes
      where code = ${code}
      limit 1
    `;
    if (!lookup.length) return res.status(404).json({ ok: false, error: 'Pairing code was not found.' });
    if (new Date(lookup[0].expires_at).getTime() < Date.now()) return res.status(410).json({ ok: false, error: 'Pairing code expired.' });
    if (lookup[0].claimed_at) return res.status(409).json({ ok: false, error: 'Pairing code was already used.' });

    // Atomic single-use claim: if two devices submit the same code, only the
    // oldest request that reaches the server updates claimed_at. Later requests
    // get no returned row and are rejected.
    const claimed = await sql`
      update device_pairing_codes
      set claimed_by_device_id = ${deviceId}, claimed_at = now()
      where code = ${code} and claimed_at is null and expires_at > now()
      returning code, store_id, branch_id, host_device_id, host_device_name, transport, expires_at, claimed_at
    `;
    if (!claimed.length) return res.status(409).json({ ok: false, error: 'Pairing code was already claimed by an older request.' });
    const pairing = claimed[0];
    assertStoreAllowed(pairing.store_id);

    const deviceToken = makeDeviceToken();
    await sql`
      insert into store_devices (store_id, branch_id, device_id, device_name, platform, role, transport, app_version, device_token, revoked, last_seen_at, updated_at)
      values (${pairing.store_id}, ${pairing.branch_id}, ${deviceId}, ${deviceName}, ${platform}, 'client', ${pairing.transport}, ${appVersion}, ${deviceToken}, false, now(), now())
      on conflict (store_id, branch_id, device_id) do update set
        device_name = excluded.device_name,
        platform = excluded.platform,
        role = 'client',
        transport = excluded.transport,
        app_version = excluded.app_version,
        device_token = excluded.device_token,
        revoked = false,
        last_seen_at = now(),
        updated_at = now()
    `;
    return res.status(200).json({
      ok: true,
      storeId: pairing.store_id,
      branchId: pairing.branch_id,
      hostDeviceId: pairing.host_device_id,
      hostDeviceName: pairing.host_device_name || '',
      deviceId,
      deviceToken,
      role: 'client',
      transport: pairing.transport,
    });
  } catch (error) {
    sendError(res, error);
  }
}
