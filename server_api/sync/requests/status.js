import { sql, assertSyncTokenOrDevice, assertStoreAllowed, sendError } from '../../_db.js';

export default async function handler(req, res) {
  try {
    if (req.method !== 'POST') return res.status(405).json({ ok: false, error: 'Method not allowed' });
    const body = req.body || {};
    const storeId = String(body.storeId || body.store_id || '').trim();
    const branchId = String(body.branchId || body.branch_id || 'main').trim();
    const deviceId = String(body.deviceId || body.device_id || '').trim();
    const requestIds = Array.isArray(body.requestIds) ? body.requestIds.map((id) => String(id)).filter(Boolean) : [];
    if (!storeId) return res.status(400).json({ ok: false, error: 'storeId is required.' });
    await sql`alter table cloud_change_requests add column if not exists rejection_reason text default ''`;
    assertStoreAllowed(storeId);
    await assertSyncTokenOrDevice(req, { storeId, branchId, allowedRoles: ['client'], allowedTransports: ['cloud'] });
    if (!requestIds.length) return res.status(200).json({ ok: true, acceptedIds: [], rejected: [], pendingIds: [] });

    const rows = await sql`
      select id, status, coalesce(rejection_reason, '') as rejection_reason
      from cloud_change_requests
      where store_id = ${storeId}
        and branch_id = ${branchId}
        and device_id = ${deviceId}
        and id = any(${requestIds})
    `;
    const acceptedIds = [];
    const pendingIds = [];
    const rejected = [];
    for (const row of rows) {
      if (row.status === 'rejected') rejected.push({ id: row.id, reason: row.rejection_reason || 'Rejected by Host.' });
      else if (row.status === 'accepted') acceptedIds.push(row.id);
      else pendingIds.push(row.id);
    }
    res.status(200).json({ ok: true, acceptedIds, rejected, pendingIds, serverTime: new Date().toISOString() });
  } catch (error) {
    sendError(res, error);
  }
}
