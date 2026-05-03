import { sql, assertSyncToken, assertStoreAllowed, sendError } from '../../_db.js';

export default async function handler(req, res) {
  try {
    assertSyncToken(req);
    if (req.method !== 'POST') return res.status(405).json({ ok: false, error: 'Method not allowed' });
    const body = req.body || {};
    const storeId = String(body.storeId || body.store_id || '').trim();
    const branchId = String(body.branchId || body.branch_id || 'main').trim();
    if (!storeId) return res.status(400).json({ ok: false, error: 'storeId is required.' });
    assertStoreAllowed(storeId);
    const ackIds = Array.isArray(body.ackIds) ? body.ackIds.map((id) => String(id)).filter(Boolean) : [];
    let acceptedIds = [];
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
    res.status(200).json({ ok: true, ackIds: acceptedIds });
  } catch (error) {
    sendError(res, error);
  }
}
