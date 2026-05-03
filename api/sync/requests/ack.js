import { sql, assertSyncToken, assertStoreAllowed, sendError } from '../../_db.js';

export default async function handler(req, res) {
  try {
    assertSyncToken(req);
    if (req.method !== 'POST') return res.status(405).json({ ok: false, error: 'Method not allowed' });
    const body = req.body || {};
    const storeId = String(body.storeId || body.store_id || '').trim();
    if (storeId) assertStoreAllowed(storeId);
    const ackIds = Array.isArray(body.ackIds) ? body.ackIds.map((id) => String(id)) : [];
    if (ackIds.length) {
      await sql`
        update cloud_change_requests
        set status = 'accepted', accepted_at = now(), host_device_id = ${String(body.hostDeviceId || body.host_device_id || '')}
        where id = any(${ackIds})
      `;
    }
    res.status(200).json({ ok: true, ackIds });
  } catch (error) {
    sendError(res, error);
  }
}
