import { sql, assertSyncToken, assertStoreAllowed, ensureDeviceAuthColumns, sendError } from '../_db.js';

export default async function handler(req, res) {
  try {
    assertSyncToken(req);
    if (req.method !== 'POST') return res.status(405).json({ ok: false, error: 'Method not allowed' });
    const body = req.body || {};
    const storeId = String(body.storeId || body.store_id || '').trim();
    const branchId = String(body.branchId || body.branch_id || 'main').trim() || 'main';
    const deviceId = String(body.deviceId || body.device_id || '').trim();
    const deviceToken = String(body.deviceToken || body.device_token || req.headers['x-device-token'] || '').trim();
    if (!storeId) return res.status(400).json({ ok: false, error: 'storeId is required.' });
    if (!deviceId) return res.status(400).json({ ok: false, error: 'deviceId is required.' });
    assertStoreAllowed(storeId);
    await ensureDeviceAuthColumns();
    const rows = await sql`
      select coalesce(device_token, '') as device_token
      from store_devices
      where store_id = ${storeId}
        and branch_id = ${branchId}
        and device_id = ${deviceId}
      limit 1
    `;
    if (!rows.length) return res.status(404).json({ ok: false, error: 'Device not found.' });
    if (String(rows[0].device_token || '') && String(rows[0].device_token || '') !== deviceToken) {
      return res.status(403).json({ ok: false, error: 'Invalid device token.' });
    }
    await sql`
      update store_devices
      set wipe_pending = false,
          online = false,
          updated_at = now()
      where store_id = ${storeId}
        and branch_id = ${branchId}
        and device_id = ${deviceId}
    `;
    return res.status(200).json({ ok: true, wipeConfirmed: true });
  } catch (error) {
    sendError(res, error);
  }
}
