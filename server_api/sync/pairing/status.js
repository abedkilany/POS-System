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
}

function toIso(value) {
  if (!value) return null;
  return value instanceof Date ? value.toISOString() : new Date(value).toISOString();
}

export default async function handler(req, res) {
  try {
    assertSyncToken(req);
    if (req.method !== 'POST') return res.status(405).json({ ok: false, error: 'Method not allowed' });
    await ensurePairingTable();
    const body = req.body || {};
    const code = String(body.code || '').trim();
    const storeId = String(body.storeId || body.store_id || '').trim();
    const branchId = String(body.branchId || body.branch_id || 'main').trim() || 'main';
    if (!code) return res.status(400).json({ ok: false, error: 'Pairing code is required.' });
    if (!storeId) return res.status(400).json({ ok: false, error: 'storeId is required.' });
    assertStoreAllowed(storeId);
    await assertDeviceAllowed(req, { storeId, branchId, allowedRoles: ['host'], allowedTransports: [] });

    const rows = await sql`
      select code, store_id, branch_id, host_device_id, transport, expires_at, claimed_by_device_id, claimed_at
      from device_pairing_codes
      where code = ${code} and store_id = ${storeId} and branch_id = ${branchId}
      limit 1
    `;
    if (!rows.length) return res.status(200).json({ ok: true, status: 'invalid' });
    const row = rows[0];
    let status = 'active';
    if (row.claimed_at) status = 'consumed';
    else if (new Date(row.expires_at).getTime() < Date.now()) status = 'expired';
    return res.status(200).json({
      ok: true,
      status,
      code: row.code,
      transport: row.transport,
      expiresAt: toIso(row.expires_at),
      claimedAt: toIso(row.claimed_at),
      claimedByDeviceId: row.claimed_by_device_id || '',
    });
  } catch (error) {
    sendError(res, error);
  }
}
