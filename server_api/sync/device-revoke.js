import { sql, assertSyncToken, assertStoreAllowed, assertDeviceAllowed, ensureDeviceAuthColumns, sendError } from '../_db.js';

export default async function handler(req, res) {
  try {
    assertSyncToken(req);
    if (req.method !== 'POST') return res.status(405).json({ ok: false, error: 'Method not allowed' });
    const body = req.body || {};
    const storeId = String(body.storeId || body.store_id || '').trim();
    const branchId = String(body.branchId || body.branch_id || 'main').trim() || 'main';
    const deviceId = String(body.deviceId || body.device_id || '').trim();
    if (!storeId) return res.status(400).json({ ok: false, error: 'storeId is required.' });
    if (!deviceId) return res.status(400).json({ ok: false, error: 'deviceId is required.' });
    assertStoreAllowed(storeId);
    await ensureDeviceAuthColumns();
    await assertDeviceAllowed(req, { storeId, branchId, allowedRoles: ['host'], allowedTransports: ['cloud'] });
    const rows = await sql`
      update store_devices
      set revoked = true, suspended = false, wipe_pending = true, wipe_requested_at = now(), updated_at = now()
      where store_id = ${storeId}
        and branch_id = ${branchId}
        and device_id = ${deviceId}
        and role <> 'host'
      returning device_id
    `;
    return res.status(200).json({ ok: true, revoked: rows.map((row) => row.device_id) });
  } catch (error) {
    sendError(res, error);
  }
}
