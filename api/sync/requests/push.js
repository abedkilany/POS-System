import { sql, assertSyncToken, assertStoreAllowed, assertDeviceAllowed, sendError } from '../../_db.js';

function normalizeChange(raw, fallback) {
  if (!raw || typeof raw !== 'object') throw new Error('Invalid sync change.');
  const id = String(raw.id || '').trim();
  if (!id) throw new Error('Sync change is missing id.');
  const entityType = String(raw.entityType || raw.entity_type || '').trim();
  const entityId = String(raw.entityId || raw.entity_id || '').trim();
  const operation = String(raw.operation || '').trim();
  if (!entityType || !entityId || !operation) throw new Error(`Sync change ${id} is missing entityType/entityId/operation.`);
  return {
    id,
    storeId: String(raw.storeId || raw.store_id || fallback.storeId || 'default-store'),
    branchId: String(raw.branchId || raw.branch_id || fallback.branchId || 'main'),
    deviceId: String(raw.deviceId || raw.device_id || fallback.deviceId || 'unknown-device'),
    entityType,
    entityId,
    operation,
    payload: raw.payload && typeof raw.payload === 'object' ? raw.payload : {},
    createdAt: raw.createdAt ? new Date(raw.createdAt).toISOString() : new Date().toISOString(),
    storeEpoch: Number(raw.storeEpoch || raw.store_epoch || 1),
    sequence: Number(raw.sequence || 0),
  };
}

export default async function handler(req, res) {
  try {
    assertSyncToken(req);
    await sql`alter table cloud_change_requests add column if not exists store_epoch integer not null default 1`;
    await sql`alter table cloud_change_requests add column if not exists sequence integer not null default 0`;
    if (req.method !== 'POST') return res.status(405).json({ ok: false, error: 'Method not allowed' });

    const body = req.body || {};
    const changes = Array.isArray(body.changes) ? body.changes : [];
    const fallback = { storeId: body.storeId, branchId: body.branchId, deviceId: body.deviceId };
    if (fallback.storeId) {
      const storeId = String(fallback.storeId);
      const branchId = String(fallback.branchId || 'main');
      assertStoreAllowed(storeId);
      await assertDeviceAllowed(req, { storeId, branchId, allowedRoles: ['client'], allowedTransports: ['cloud'] });
    }

    const ackIds = [];
    for (const raw of changes) {
      const change = normalizeChange(raw, fallback);
      assertStoreAllowed(change.storeId);
      const syncV2Kind = change.payload && change.payload._syncV2 && String(change.payload._syncV2.kind || '');
      if (syncV2Kind === 'authoritativeEvent') {
        return res.status(403).json({ ok: false, error: 'Authoritative events can only be published by the Host.' });
      }
      await sql`
        insert into cloud_change_requests (
          id, store_id, branch_id, device_id, entity_type, entity_id, operation, payload, created_at, store_epoch, sequence, status
        ) values (
          ${change.id}, ${change.storeId}, ${change.branchId}, ${change.deviceId}, ${change.entityType}, ${change.entityId}, ${change.operation}, ${JSON.stringify(change.payload)}, ${change.createdAt}, ${change.storeEpoch}, ${change.sequence}, 'pending'
        )
        on conflict (id) do nothing
      `;
      ackIds.push(change.id);
    }

    res.status(200).json({ ok: true, ackIds, relay: 'host_inbox', serverTime: new Date().toISOString() });
  } catch (error) {
    sendError(res, error);
  }
}
