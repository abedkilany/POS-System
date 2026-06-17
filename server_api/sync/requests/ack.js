import { sql, assertStoreAllowed, assertAccountOrDevice, sendError } from '../../_db.js';

export default async function handler(req, res) {
  try {
    if (req.method !== 'POST') return res.status(405).json({ ok: false, error: 'Method not allowed' });
    const body = req.body || {};
    const storeId = String(body.storeId || body.store_id || '').trim();
    const branchId = String(body.branchId || body.branch_id || 'main').trim();
    if (!storeId) return res.status(400).json({ ok: false, error: 'storeId is required.' });
    assertStoreAllowed(storeId);
    await assertAccountOrDevice(req, { storeId, branchId, allowedRoles: ['host'], allowedTransports: ['cloud'] });
    await sql`alter table cloud_change_requests add column if not exists rejection_reason text default ''`;
    const ackIds = Array.isArray(body.ackIds) ? body.ackIds.map((id) => String(id)).filter(Boolean) : [];
    const rejectedRaw = Array.isArray(body.rejected) ? body.rejected : [];
    let acceptedIds = [];
    const rejected = [];
    if (ackIds.length) {
      const rows = await sql`
        update cloud_change_requests
        set status = 'accepted', accepted_at = now(), host_device_id = ${String(body.hostDeviceId || body.host_device_id || '')}
        where id = any(${ackIds})
          and store_id = ${storeId}
          and branch_id = ${branchId}
        returning id
      `;
      acceptedIds = rows.map((row) => row.id);
    }
    for (const item of rejectedRaw) {
      const id = String((item && item.id) || '').trim();
      if (!id) continue;
      const reason = String((item && item.reason) || 'Rejected by Host.');
      const rows = await sql`
        update cloud_change_requests
        set status = 'rejected', rejection_reason = ${reason}, accepted_at = now(), host_device_id = ${String(body.hostDeviceId || body.host_device_id || '')}
        where id = ${id}
          and store_id = ${storeId}
          and branch_id = ${branchId}
        returning id, rejection_reason
      `;
      for (const row of rows) rejected.push({ id: row.id, reason: row.rejection_reason || reason });
    }
    res.status(200).json({ ok: true, ackIds: acceptedIds, rejected });
  } catch (error) {
    sendError(res, error);
  }
}
