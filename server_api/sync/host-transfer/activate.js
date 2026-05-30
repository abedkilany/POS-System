import { assertStoreAllowed, assertSyncTokenOrDevice, sendError } from '../../_db.js';
import { sql } from '../../_db.js';
import { ensureHostTransferTables, transferDto } from './_shared.js';

export default async function handler(req, res) {
  try {
    if (req.method !== 'POST') return res.status(405).json({ ok: false, error: 'Method not allowed' });
    await ensureHostTransferTables();
    const body = req.body || {};
    const storeId = String(body.storeId || body.store_id || '').trim();
    const branchId = String(body.branchId || body.branch_id || 'main').trim() || 'main';
    const newHostDeviceId = String(body.newHostDeviceId || body.new_host_device_id || body.deviceId || body.device_id || '').trim();
    if (!storeId) return res.status(400).json({ ok: false, error: 'storeId is required.' });
    if (!newHostDeviceId) return res.status(400).json({ ok: false, error: 'newHostDeviceId is required.' });
    assertStoreAllowed(storeId);
    await assertSyncTokenOrDevice(req, { storeId, branchId, allowedRoles: ['client'], allowedTransports: ['cloud', 'lan'] });
    const rows = await sql`
      update host_transfer_requests
      set status = 'activated', activated_at = now(), updated_at = now()
      where store_id = ${storeId} and branch_id = ${branchId} and requesting_device_id = ${newHostDeviceId} and status = 'approved'
      returning *
    `;
    if (!rows.length) return res.status(409).json({ ok: false, error: 'No approved Host transfer was found for this device.' });
    await sql`update store_devices set role = 'host', transport = 'cloud', active_transport = 'cloud', last_sync_transport = 'cloud', online = true, last_seen_at = now(), updated_at = now() where store_id = ${storeId} and branch_id = ${branchId} and device_id = ${newHostDeviceId}`;
    res.status(200).json({ ok: true, request: transferDto(rows[0]) });
  } catch (error) { sendError(res, error); }
}
