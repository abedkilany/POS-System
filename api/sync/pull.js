import { sql, assertSyncToken, sendError } from '../_db.js';

function asIso(value) {
  return value instanceof Date ? value.toISOString() : new Date(value).toISOString();
}

export default async function handler(req, res) {
  try {
    assertSyncToken(req);
    if (req.method !== 'GET') return res.status(405).json({ ok: false, error: 'Method not allowed' });

    const storeId = String(req.query.store_id || req.query.storeId || 'default-store');
    const branchId = String(req.query.branch_id || req.query.branchId || 'main');
    const since = req.query.since ? new Date(String(req.query.since)).toISOString() : null;
    const limit = Math.min(Number(req.query.limit || 1000), 5000);

    // First-time/new-device pull: return the latest materialized state so a new
    // browser/device can hydrate Hive even if it never saw the original events.
    if (!since) {
      const snapshotRows = await sql`
        select store_id, entity_type, entity_id, operation, payload, updated_at
        from entity_snapshots
        where store_id = ${storeId}
          and operation <> 'delete'
        order by updated_at asc
        limit ${limit}
      `;
      const changes = snapshotRows.map((row) => ({
        id: `snapshot-${row.entity_type}-${row.entity_id}-${asIso(row.updated_at)}`,
        storeId: row.store_id,
        branchId,
        deviceId: 'cloud-snapshot',
        entityType: row.entity_type,
        entityId: row.entity_id,
        operation: 'upsert',
        payload: row.payload || {},
        createdAt: asIso(row.updated_at),
        isSynced: true,
        syncedAt: new Date().toISOString(),
      }));
      return res.status(200).json({ ok: true, changes, generatedAt: new Date().toISOString(), source: 'entity_snapshots' });
    }

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
      createdAt: asIso(row.created_at),
      isSynced: true,
      syncedAt: new Date().toISOString(),
    }));

    res.status(200).json({ ok: true, changes, generatedAt: new Date().toISOString(), source: 'sync_events' });
  } catch (error) {
    sendError(res, error);
  }
}
