import { sql, assertSyncToken, sendError } from '../_db.js';

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
  };
}

const snapshotCollections = {
  products: 'product',
  customers: 'customer',
  sales: 'sale',
  suppliers: 'supplier',
  expenses: 'expense',
  categories: 'category',
  brands: 'brand',
  units: 'unit',
  roles: 'role',
  users: 'user',
};

function idOf(item, fallback) {
  if (item && typeof item === 'object' && item.id != null && String(item.id).trim()) return String(item.id);
  return fallback;
}

async function upsertSnapshot({ storeId, entityType, entityId, operation, payload, updatedAt }) {
  if (!storeId || !entityType || !entityId) return;
  if (operation === 'delete') {
    await sql`
      insert into entity_snapshots (store_id, entity_type, entity_id, payload, operation, updated_at)
      values (${storeId}, ${entityType}, ${entityId}, ${JSON.stringify(payload || {})}, ${operation}, ${updatedAt})
      on conflict (store_id, entity_type, entity_id) do update set
        payload = excluded.payload,
        operation = excluded.operation,
        updated_at = excluded.updated_at
    `;
    return;
  }
  await sql`
    insert into entity_snapshots (store_id, entity_type, entity_id, payload, operation, updated_at)
    values (${storeId}, ${entityType}, ${entityId}, ${JSON.stringify(payload || {})}, ${operation || 'upsert'}, ${updatedAt})
    on conflict (store_id, entity_type, entity_id) do update set
      payload = excluded.payload,
      operation = excluded.operation,
      updated_at = excluded.updated_at
  `;
}

async function materializeChange(change) {
  const updatedAt = change.createdAt || new Date().toISOString();

  if (change.entityType === 'system' && change.operation === 'restore_snapshot') {
    const p = change.payload || {};
    for (const [key, entityType] of Object.entries(snapshotCollections)) {
      const list = Array.isArray(p[key]) ? p[key] : [];
      for (let i = 0; i < list.length; i += 1) {
        const item = list[i];
        const entityId = idOf(item, `${key}-${i}`);
        await upsertSnapshot({
          storeId: change.storeId,
          entityType,
          entityId,
          operation: 'upsert',
          payload: item,
          updatedAt,
        });
      }
    }
    if (p.storeProfile && typeof p.storeProfile === 'object') {
      await upsertSnapshot({ storeId: change.storeId, entityType: 'store_profile', entityId: 'store', operation: 'upsert', payload: p.storeProfile, updatedAt });
    }
    return;
  }

  if (change.operation === 'reset_store_data') {
    await sql`delete from entity_snapshots where store_id = ${change.storeId}`;
    return;
  }

  if (change.entityType === 'stock_movement') return;

  await upsertSnapshot({
    storeId: change.storeId,
    entityType: change.entityType,
    entityId: change.entityId,
    operation: change.operation === 'delete' ? 'delete' : 'upsert',
    payload: change.payload,
    updatedAt,
  });
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
      await materializeChange(change);
      ackIds.push(change.id);
    }

    res.status(200).json({ ok: true, ackIds, serverTime: new Date().toISOString() });
  } catch (error) {
    sendError(res, error);
  }
}
