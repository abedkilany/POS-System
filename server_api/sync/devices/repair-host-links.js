import { sql, assertSyncToken, assertStoreAllowed, assertDeviceAllowed, ensureDeviceAuthColumns, sendError } from '../../_db.js';

export default async function handler(req, res) {
  try {
    assertSyncToken(req);
    if (req.method !== 'POST') return res.status(405).json({ ok: false, error: 'Method not allowed' });

    const body = req.body || {};
    const storeId = String(body.storeId || body.store_id || '').trim();
    const branchId = String(body.branchId || body.branch_id || 'main').trim() || 'main';
    const hostDeviceId = String(body.hostDeviceId || body.host_device_id || '').trim();
    const clientDeviceIds = Array.isArray(body.clientDeviceIds || body.client_device_ids)
      ? (body.clientDeviceIds || body.client_device_ids).map((id) => String(id).trim()).filter(Boolean)
      : [];

    if (!storeId) return res.status(400).json({ ok: false, error: 'storeId is required.' });
    if (!hostDeviceId) return res.status(400).json({ ok: false, error: 'hostDeviceId is required.' });
    if (!clientDeviceIds.length) return res.status(200).json({ ok: true, checked: 0, repaired: 0, repairedDeviceIds: [] });

    assertStoreAllowed(storeId);
    await assertDeviceAllowed(req, { storeId, branchId, allowedRoles: ['host'], allowedTransports: ['cloud'] });
    await ensureDeviceAuthColumns();
    await sql`alter table store_devices add column if not exists host_device_id text default ''`;
    await sql`
      create index if not exists idx_store_devices_host_device
      on store_devices (store_id, branch_id, host_device_id)
    `;

    const rows = await sql`
      update store_devices
      set host_device_id = ${hostDeviceId},
          updated_at = now()
      where store_id = ${storeId}
        and branch_id = ${branchId}
        and device_id = any(${clientDeviceIds})
        and coalesce(host_device_id, '') = ''
        and coalesce(role, '') <> 'host'
        and revoked = false
      returning device_id
    `;

    return res.status(200).json({
      ok: true,
      checked: clientDeviceIds.length,
      repaired: rows.length,
      repairedDeviceIds: rows.map((row) => row.device_id),
    });
  } catch (error) {
    sendError(res, error);
  }
}
