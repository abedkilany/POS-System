import { assertStoreAllowed, assertAccountOrDevice, sendError } from '../../_db.js';
import { sql } from '../../_db.js';
import { ensureHostTransferTables, transferDto } from './_shared.js';

export default async function handler(req, res) {
  try {
    if (req.method !== 'POST') return res.status(405).json({ ok: false, error: 'Method not allowed' });
    await ensureHostTransferTables();
    const body = req.body || {};
    const storeId = String(body.storeId || body.store_id || '').trim();
    const branchId = String(body.branchId || body.branch_id || 'main').trim() || 'main';
    const requestingDeviceId = String(body.requestingDeviceId || body.requesting_device_id || '').trim();
    const approvedByHostDeviceId = String(body.approvedByHostDeviceId || body.approved_by_host_device_id || body.hostDeviceId || body.host_device_id || '').trim();
    if (!storeId) return res.status(400).json({ ok: false, error: 'storeId is required.' });
    if (!requestingDeviceId) return res.status(400).json({ ok: false, error: 'requestingDeviceId is required.' });
    if (!approvedByHostDeviceId) return res.status(400).json({ ok: false, error: 'approvedByHostDeviceId is required.' });
    assertStoreAllowed(storeId);
    await assertAccountOrDevice(req, { storeId, branchId, allowedRoles: ['host'], allowedTransports: ['cloud'] });
    const rows = await sql`
      insert into host_transfer_requests (store_id, branch_id, requesting_device_id, current_host_device_id, status, approved_by_host_device_id, requested_at, approved_at, updated_at)
      values (${storeId}, ${branchId}, ${requestingDeviceId}, ${approvedByHostDeviceId}, 'approved_pending_activation', ${approvedByHostDeviceId}, now(), now(), now())
      on conflict (store_id, branch_id, requesting_device_id) do update set
        current_host_device_id = ${approvedByHostDeviceId},
        status = 'approved_pending_activation',
        approved_by_host_device_id = ${approvedByHostDeviceId},
        approved_at = now(),
        updated_at = now()
      returning *
    `;
    // Keep the current Host authoritative until the approved Client activates.
    // The old Host becomes Client only after activation succeeds.
    res.status(200).json({ ok: true, request: transferDto(rows[0]) });
  } catch (error) { sendError(res, error); }
}
