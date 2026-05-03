import { sql, assertSyncToken, sendError } from '../_db.js';

function normalizeChange(raw, fallback) {
  if (!raw || typeof raw !== 'object') throw new Error('Invalid sync change.');
  const id = String(raw.id || '').trim();
  if (!id) throw new Error('Sync change is missing id.');
  const entityType = String(raw.entityType || '').trim();
  const entityId = String(raw.entityId || '').trim();
  const operation = String(raw.operation || '').trim();
  if (!entityType || !entityId || !operation) throw new Error(`Sync change ${id} is missing entityType/entityId/operation.`);
  return {
    id,
    storeId: String(raw.storeId || fallback.storeId || 'default-store'),
    branchId: String(raw.branchId || fallback.branchId || 'main'),
    deviceId: String(raw.deviceId || fallback.deviceId || 'unknown-device'),
    entityType,
    entityId,
    operation,
    payload: raw.payload && typeof raw.payload === 'object' ? raw.payload : {},
    createdAt: raw.createdAt ? new Date(raw.createdAt).toISOString() : new Date().toISOString(),
  };
}

export default async function handler(req, res) {
  try {
    assertSyncToken(req);
    if (req.method !== 'POST') return res.status(405).json({ ok: false, error: 'Method not allowed' });

    const body = req.body || {};
    const changes = Array.isArray(body.changes) ? body.changes : [];
    const fallback = {
      storeId: body.storeId,
      branchId: body.branchId,
      deviceId: body.deviceId,
    };

    const ackIds = [];
    for (const raw of changes) {
      const change = normalizeChange(raw, fallback);
      await sql`
        insert into sync_events (
          id, store_id, branch_id, device_id, entity_type, entity_id, operation, payload, created_at
        ) values (
          ${change.id}, ${change.storeId}, ${change.branchId}, ${change.deviceId}, ${change.entityType}, ${change.entityId}, ${change.operation}, ${JSON.stringify(change.payload)}, ${change.createdAt}
        )
        on conflict (id) do update set
          payload = excluded.payload,
          received_at = now()
      `;
      ackIds.push(change.id);
    }

    res.status(200).json({ ok: true, ackIds, serverTime: new Date().toISOString() });
  } catch (error) {
    sendError(res, error);
  }
}
