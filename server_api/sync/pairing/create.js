import { randomBytes, createHash } from 'crypto';
import { sql, assertSyncToken, assertStoreAllowed, assertDeviceAllowed, sendError } from '../../_db.js';

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
      cloud_tenant_id text default '',
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now(),
      primary key (store_id, branch_id)
    )
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
    assertSyncToken(req);
    if (req.method !== 'POST') return res.status(405).json({ ok: false, error: 'Method not allowed' });
    await ensurePairingTable();
    await ensureRecoveryTable();
    const body = req.body || {};
    const storeId = String(body.storeId || body.store_id || '').trim();
    const branchId = String(body.branchId || body.branch_id || 'main').trim() || 'main';
    const hostDeviceId = String(body.hostDeviceId || body.host_device_id || body.deviceId || '').trim();
    const hostDeviceName = String(body.hostDeviceName || body.host_device_name || '').trim();
    const transport = String(body.transport || 'cloud').trim() === 'lan' ? 'lan' : 'cloud';
    const ttlMinutes = Math.min(Math.max(Number(body.ttlMinutes || body.ttl_minutes || 5), 1), 30);
    const recoveryKey = normalizeRecoveryKey(body.recoveryKey || body.recovery_key);
    if (!storeId) return res.status(400).json({ ok: false, error: 'storeId is required.' });
    if (!hostDeviceId) return res.status(400).json({ ok: false, error: 'hostDeviceId is required.' });
    assertStoreAllowed(storeId);
    await assertDeviceAllowed(req, { storeId, branchId, allowedRoles: ['host'], allowedTransports: transport === 'cloud' ? ['cloud'] : [] });

    await sql`delete from device_pairing_codes where expires_at < now() or claimed_at is not null`;
    let code = makeCode();
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
