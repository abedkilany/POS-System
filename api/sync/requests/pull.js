import { sql, assertSyncToken, assertStoreAllowed, sendError } from '../../_db.js';

function asIso(value) {
  return value instanceof Date ? value.toISOString() : new Date(value).toISOString();
}

export default async function handler(req, res) {
  try {
    assertSyncToken(req);
    if (req.method !== 'GET') return res.status(405).json({ ok: false, error: 'Method not allowed' });

    const storeId = String(req.query.store_id || req.query.storeId || 'default-store');
    const branchId = String(req.query.branch_id || req.query.branchId || 'main');
    assertStoreAllowed(storeId);
    const limit = Math.min(Number(req.query.limit || 1000), 5000);

    const rows = await sql`
      select id, store_id, branch_id, device_id, entity_type, entity_id, operation, payload, created_at, received_at
      from cloud_change_requests
      where store_id = ${storeId}
        and branch_id = ${branchId}
        and status in ('pending', 'failed')
      order by received_at asc, created_at asc
      limit ${limit}
    `;

    const changes = rows.map((row) => ({
      id: row.id,
      storeId: row.store_id,
      branchId: row.branch_id || '',
      deviceId: row.device_id || '',
      entityType: row.entity_type,
      entityId: row.entity_id,
      operation: row.operation,
      payload: row.payload || {},
      createdAt: asIso(row.created_at),
      isSynced: false,
      syncedAt: null,
    }));

    res.status(200).json({ ok: true, changes, generatedAt: new Date().toISOString(), source: 'host_inbox' });
  } catch (error) {
    sendError(res, error);
  }
}
