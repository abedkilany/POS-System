import { sql, assertSyncToken, assertStoreAllowed, assertDeviceAllowed, sendError } from '../_db.js';

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

function payloadVersion(payload) {
  const value = Number(payload && payload.version);
  return Number.isFinite(value) ? value : 1;
}

function payloadUpdatedAt(payload, fallback) {
  const raw = payload && (payload.updatedAt || payload.updated_at || payload.deletedAt || payload.deleted_at);
  const date = new Date(raw || fallback || Date.now());
  return Number.isNaN(date.getTime()) ? new Date(fallback || Date.now()) : date;
}

function incomingWins({ existingPayload, existingUpdatedAt, incomingPayload, incomingUpdatedAt }) {
  const incomingVersion = payloadVersion(incomingPayload);
  const existingVersion = payloadVersion(existingPayload);
  if (incomingVersion !== existingVersion) return incomingVersion > existingVersion;
  return payloadUpdatedAt(incomingPayload, incomingUpdatedAt).getTime() >= payloadUpdatedAt(existingPayload, existingUpdatedAt).getTime();
}

async function upsertSnapshot({ storeId, branchId, entityType, entityId, operation, payload, updatedAt, force = false }) {
  if (!storeId || !entityType || !entityId) return false;

  const existingRows = await sql`
    select payload, operation, updated_at
    from entity_snapshots
    where store_id = ${storeId}
      and branch_id = ${branchId || 'main'}
      and entity_type = ${entityType}
      and entity_id = ${entityId}
    limit 1
  `;

  if (!force && existingRows.length) {
    const existing = existingRows[0];
    if (!incomingWins({
      existingPayload: existing.payload || {},
      existingUpdatedAt: existing.updated_at,
      incomingPayload: payload || {},
      incomingUpdatedAt: updatedAt,
    })) {
      return false;
    }
  }

  await sql`
    insert into entity_snapshots (store_id, branch_id, entity_type, entity_id, payload, operation, updated_at)
    values (${storeId}, ${branchId || 'main'}, ${entityType}, ${entityId}, ${JSON.stringify(payload || {})}, ${operation === 'delete' ? 'delete' : (operation || 'upsert')}, ${updatedAt})
    on conflict (store_id, branch_id, entity_type, entity_id) do update set
      payload = excluded.payload,
      operation = excluded.operation,
      updated_at = excluded.updated_at
  `;
  return true;
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
          branchId: change.branchId,
          entityType,
          entityId,
          operation: 'upsert',
          payload: item,
          updatedAt,
          force: true,
        });
      }
    }
    if (p.storeProfile && typeof p.storeProfile === 'object') {
      await upsertSnapshot({ storeId: change.storeId, branchId: change.branchId, entityType: 'store_profile', entityId: 'store', operation: 'upsert', payload: p.storeProfile, updatedAt, force: true });
    }
    return;
  }

  if (change.operation === 'reset_store_data') {
    await sql`delete from entity_snapshots where store_id = ${change.storeId} and branch_id = ${change.branchId || 'main'}`;
    return;
  }

  if (change.entityType === 'stock_movement') {
    const p = change.payload || {};
    const productId = String(p.productId || p.product_id || '').trim();
    const quantity = Number(p.quantity || 0);
    if (!productId || !Number.isFinite(quantity) || quantity === 0) return;

    const movementRows = await sql`
      select entity_id
      from entity_snapshots
      where store_id = ${change.storeId}
        and branch_id = ${change.branchId || 'main'}
        and entity_type = 'stock_movement'
        and entity_id = ${change.entityId}
      limit 1
    `;
    if (movementRows.length) return;

    const rows = await sql`
      select payload, operation, updated_at
      from entity_snapshots
      where store_id = ${change.storeId}
        and branch_id = ${change.branchId || 'main'}
        and entity_type = 'product'
        and entity_id = ${productId}
      limit 1
    `;
    if (!rows.length || rows[0].operation === 'delete') return;

    const product = rows[0].payload || {};
    const currentStock = Number(product.stock || 0);
    const nextProduct = {
      ...product,
      stock: currentStock + quantity,
      updatedAt,
      syncStatus: 'synced',
      storeId: change.storeId,
      branchId: change.branchId || product.branchId || 'main',
    };
    await upsertSnapshot({
      storeId: change.storeId,
      branchId: change.branchId,
      entityType: 'product',
      entityId: productId,
      operation: 'upsert',
      payload: nextProduct,
      updatedAt,
      force: true,
    });
    await upsertSnapshot({
      storeId: change.storeId,
      branchId: change.branchId,
      entityType: 'stock_movement',
      entityId: change.entityId,
      operation: 'upsert',
      payload: { ...p, appliedToProductSnapshot: productId },
      updatedAt,
    });
    return;
  }

  await upsertSnapshot({
    storeId: change.storeId,
    branchId: change.branchId,
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
    await sql`alter table sync_events add column if not exists store_epoch integer not null default 1`;
    await sql`alter table sync_events add column if not exists sequence integer not null default 0`;
    if (req.method !== 'POST') return res.status(405).json({ ok: false, error: 'Method not allowed' });

    const body = req.body || {};
    const changes = Array.isArray(body.changes) ? body.changes : [];
    const fallback = {
      storeId: body.storeId,
      branchId: body.branchId,
      deviceId: body.deviceId,
    };

    if (fallback.storeId) {
      const storeId = String(fallback.storeId);
      const branchId = String(fallback.branchId || 'main');
      assertStoreAllowed(storeId);
      await assertDeviceAllowed(req, { storeId, branchId, allowedRoles: ['host'], allowedTransports: ['cloud'] });
    }

    const ackIds = [];
    for (const raw of changes) {
      const change = normalizeChange(raw, fallback);
      assertStoreAllowed(change.storeId);
      const syncV2Kind = change.payload && change.payload._syncV2 && String(change.payload._syncV2.kind || '');
      if (syncV2Kind === 'draftCommand') {
        return res.status(403).json({ ok: false, error: 'Draft commands must be sent to the Host relay, not the authoritative event stream.' });
      }
      const inserted = await sql`
        insert into sync_events (
          id, store_id, branch_id, device_id, entity_type, entity_id, operation, payload, created_at, store_epoch, sequence
        ) values (
          ${change.id}, ${change.storeId}, ${change.branchId}, ${change.deviceId}, ${change.entityType}, ${change.entityId}, ${change.operation}, ${JSON.stringify(change.payload)}, ${change.createdAt}, ${change.storeEpoch}, ${change.sequence}
        )
        on conflict (id) do nothing
        returning id
      `;
      if (inserted.length > 0) {
        await materializeChange(change);
      }
      ackIds.push(change.id);
    }

    res.status(200).json({ ok: true, ackIds, serverTime: new Date().toISOString() });
  } catch (error) {
    sendError(res, error);
  }
}
