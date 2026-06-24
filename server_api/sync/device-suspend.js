import { sql, assertStoreAllowed, assertAccountOrDevice, ensureDeviceAuthColumns, sendError } from '../_db.js';

export default async function handler(req, res) {
  try {
    if (req.method !== 'POST') return res.status(405).json({ ok: false, error: 'Method not allowed' });
    const body = req.body || {};
    const storeId = String(body.storeId || body.store_id || '').trim();
    const branchId = String(body.branchId || body.branch_id || 'main').trim() || 'main';
    const deviceId = String(body.deviceId || body.device_id || '').trim();
    const suspended = body.suspended === true;
    if (!storeId) return res.status(400).json({ ok: false, error: 'storeId is required.' });
    if (!deviceId) return res.status(400).json({ ok: false, error: 'deviceId is required.' });
    assertStoreAllowed(storeId);
    await ensureDeviceAuthColumns();
    await assertAccountOrDevice(req, { storeId, branchId, allowedRoles: ['host'], allowedTransports: ['cloud'] });
    const rows = await sql`
      update store_devices
      set suspended = ${suspended}, updated_at = now()
      where store_id = ${storeId}
        and branch_id = ${branchId}
        and device_id = ${deviceId}
        and role <> 'host'
        and revoked = false
      returning device_id, suspended
    `;
    return res.status(200).json({ ok: true, devices: rows });
  } catch (error) {
    sendError(res, error);
  }
}
