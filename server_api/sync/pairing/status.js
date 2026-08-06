import {
  sql,
  assertAccountOrDevice,
  assertDirectSyncEnabled,
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
}

export default async function handler(req, res) {
  try {
    if (req.method !== 'POST') {
      return res.status(405).json({ ok: false, error: 'Method not allowed' });
    }

    await ensurePairingTable();
    const body = req.body || {};
    const storeId = String(body.storeId || body.store_id || '').trim();
    const branchId = String(body.branchId || body.branch_id || 'main').trim();
    const code = String(body.code || '').trim();
    if (!storeId || !code) {
      return res.status(400).json({
        ok: false,
        error: 'storeId and code are required.',
      });
    }

    await assertAccountOrDevice(req, {
      storeId,
      branchId,
      allowedRoles: ['host'],
      allowedTransports: ['direct'],
    });
    await assertDirectSyncEnabled(storeId);

    const rows = await sql`
      select code, store_id, branch_id, host_device_id, host_device_name,
             transport, expires_at, claimed_by_device_id, claimed_at
      from device_pairing_codes
      where code = ${code}
        and store_id = ${storeId}
        and branch_id = ${branchId}
        and transport = 'direct'
      limit 1
    `;

    if (!rows.length) {
      return res.status(200).json({
        ok: true,
        status: 'invalid',
        message: 'Pairing code was not found.',
      });
    }

    const row = rows[0];
    const expiresAt = new Date(row.expires_at);
    const status = row.claimed_at
      ? 'consumed'
      : expiresAt.getTime() <= Date.now()
          ? 'expired'
          : 'active';

    return res.status(200).json({
      ok: true,
      status,
      expiresAt: expiresAt.toISOString(),
      claimedAt: row.claimed_at ? new Date(row.claimed_at).toISOString() : null,
      claimedByDeviceId: row.claimed_by_device_id || '',
      claimedByDeviceName: '',
      storeId: row.store_id,
      branchId: row.branch_id,
      hostDeviceId: row.host_device_id,
      hostDeviceName: row.host_device_name || '',
      transport: row.transport,
    });
  } catch (error) {
    return sendError(res, error);
  }
}
