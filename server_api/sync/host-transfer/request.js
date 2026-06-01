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
    const requestingDeviceId = String(body.requestingDeviceId || body.requesting_device_id || body.deviceId || body.device_id || '').trim();
    const currentHostDeviceId = String(body.currentHostDeviceId || body.current_host_device_id || '').trim();
    const reason = String(body.reason || '').trim();
    if (!storeId) return res.status(400).json({ ok: false, error: 'storeId is required.' });
    if (!requestingDeviceId) return res.status(400).json({ ok: false, error: 'requestingDeviceId is required.' });
    assertStoreAllowed(storeId);
    await assertSyncTokenOrDevice(req, { storeId, branchId, allowedRoles: ['client'], allowedTransports: ['cloud', 'lan'] });
    const rows = await sql`
      insert into host_transfer_requests (store_id, branch_id, requesting_device_id, current_host_device_id, status, reason, requested_at, updated_at)
      values (${storeId}, ${branchId}, ${requestingDeviceId}, ${currentHostDeviceId}, 'pending', ${reason}, now(), now())
      on conflict (store_id, branch_id, requesting_device_id) do update set
        current_host_device_id = excluded.current_host_device_id,
        status = 'pending',
        reason = excluded.reason,
        requested_at = now(),
        approved_at = null,
        activated_at = null,
        updated_at = now()
      returning *
    `;
    res.status(200).json({ ok: true, request: transferDto(rows[0]) });
  } catch (error) { sendError(res, error); }
}
