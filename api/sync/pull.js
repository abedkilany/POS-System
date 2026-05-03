import { sql, assertSyncToken, sendError } from '../_db.js';

export default async function handler(req, res) {
  try {
    assertSyncToken(req);
    if (req.method !== 'GET') return res.status(405).json({ ok: false, error: 'Method not allowed' });

    const storeId = String(req.query.store_id || req.query.storeId || 'default-store');
    const since = req.query.since ? new Date(String(req.query.since)).toISOString() : '1970-01-01T00:00:00.000Z';
    const limit = Math.min(Number(req.query.limit || 500), 2000);

    const rows = await sql`
      select id, store_id, branch_id, device_id, entity_type, entity_id, operation, payload, created_at
      from sync_events
      where store_id = ${storeId}
        and created_at > ${since}
      order by created_at asc
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
      createdAt: row.created_at instanceof Date ? row.created_at.toISOString() : row.created_at,
      isSynced: true,
      syncedAt: new Date().toISOString(),
    }));

    res.status(200).json({ ok: true, changes, generatedAt: new Date().toISOString() });
  } catch (error) {
    sendError(res, error);
  }
}
