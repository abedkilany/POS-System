import { sql, assertAccountOrDevice, assertStoreAllowed, ensureDeviceAuthColumns, sendError } from '../_db.js';
import { notifySyncChanged } from './realtime.js';

function safeDate(value) {
  if (!value) return null;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return null;
  return date.toISOString();
}

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
    eventId: String((raw.payload && raw.payload._syncV2 && raw.payload._syncV2.eventId) || raw.eventId || raw.event_id || id),
    requestId: String((raw.payload && raw.payload._syncV2 && raw.payload._syncV2.requestId) || raw.requestId || raw.request_id || ''),
    sourceCommandId: String((raw.payload && raw.payload._syncV2 && raw.payload._syncV2.sourceCommandId) || raw.sourceCommandId || raw.source_command_id || ''),
  };
}


async function ensureCloudSequenceTable() {
  await sql`
    create table if not exists cloud_sync_sequences (
      store_id text not null,
      branch_id text not null default 'main',
      last_sequence bigint not null default 0,
      updated_at timestamptz not null default now(),
      primary key (store_id, branch_id)
    )
  `;
}

async function allocateServerSequence(storeId, branchId) {
  const rows = await sql`
    insert into cloud_sync_sequences (store_id, branch_id, last_sequence, updated_at)
    values (${storeId}, ${branchId || 'main'}, 1, now())
    on conflict (store_id, branch_id) do update set
      last_sequence = cloud_sync_sequences.last_sequence + 1,
      updated_at = now()
    returning last_sequence
  `;
  return Number(rows[0]?.last_sequence || 0);
}

const snapshotCollections = {
  products: 'product',
  customers: 'customer',
  sales: 'sale',
  saleQuotations: 'sale_quotation',
  deliveryNotes: 'delivery_note',
  billsOfMaterials: 'bill_of_materials',
  manufacturingOrders: 'manufacturing_order',
  suppliers: 'supplier',
  warehouses: 'warehouse',
  supplierProductPrices: 'supplier_product_price',
  priceLists: 'price_list',
  productPrices: 'product_price',
  productPriceOverrides: 'product_price_override',
  productCosts: 'product_cost',
  costingMethodHistory: 'costing_method_history',
  inventoryCostingMethod: 'inventory_costing_method',
  inventoryCostLayers: 'inventory_cost_layer',
  expenses: 'expense',
  categories: 'category',
  brands: 'brand',
  units: 'unit',
  purchases: 'purchase',
  stockMovements: 'stock_movement',
  inventoryCounts: 'inventory_count',
  accountTransactions: 'account_transaction',
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


async function cleanupExpiredSoftDeletes(storeId, branchId, retentionDays = 30) {
  // Keep tombstones long enough for offline Clients to learn about deletions,
  // then prune them from the materialized snapshot so fresh devices do not
  // accumulate old deleted rows forever. Authoritative sync_events remain as
  // the audit trail; only the read-optimized entity_snapshots table is pruned.
  await sql`
    delete from entity_snapshots
    where store_id = ${storeId}
      and branch_id = ${branchId || 'main'}
      and operation = 'delete'
      and updated_at < now() - (${retentionDays}::text || ' days')::interval
  `;
  await sql`
    delete from entity_snapshots
    where store_id = ${storeId}
      and branch_id = ${branchId || 'main'}
      and payload->>'deletedAt' is not null
      and nullif(payload->>'deletedAt', '')::timestamptz < now() - (${retentionDays}::text || ' days')::interval
  `;
}

async function materializeChange(change) {
  const updatedAt = change.createdAt || new Date().toISOString();

  if (change.entityType === 'system' && change.operation === 'restore_snapshot') {
    const p = change.payload || {};
    // A restore_snapshot is a full clean Host snapshot. Remove stale rows first
    // so deleted/missing entities do not remain visible to new Cloud clients.
    await sql`delete from entity_snapshots where store_id = ${change.storeId} and branch_id = ${change.branchId || 'main'}`;
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
    await sql`alter table sync_events add column if not exists store_epoch integer not null default 1`;
    await sql`alter table sync_events add column if not exists sequence bigint not null default 0`;
    await sql`alter table sync_events add column if not exists event_id text default ''`;
    await sql`alter table sync_events add column if not exists request_id text default ''`;
    await sql`alter table sync_events add column if not exists source_command_id text default ''`;
    await ensureCloudSequenceTable();
    await sql`create unique index if not exists idx_sync_events_event_id_unique on sync_events (store_id, branch_id, event_id) where event_id is not null and event_id <> ''`;
    await sql`create unique index if not exists idx_sync_events_source_command_unique on sync_events (store_id, branch_id, source_command_id) where source_command_id is not null and source_command_id <> ''`;
    await ensureDeviceAuthColumns();
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
      await assertAccountOrDevice(req, { storeId, branchId, allowedRoles: ['host'], allowedTransports: ['cloud'] });
    }

    const ackIds = [];
    let latestAcceptedAt = null;
    let latestAcceptedSequence = 0;
    for (const raw of changes) {
      const change = normalizeChange(raw, fallback);
      assertStoreAllowed(change.storeId);
      const syncV2Kind = change.payload && change.payload._syncV2 && String(change.payload._syncV2.kind || '');
      if (syncV2Kind === 'draftCommand') {
        return res.status(403).json({ ok: false, error: 'Draft commands must be sent to the Host relay, not the authoritative event stream.' });
      }
      const duplicateRows = await sql`
        select id, sequence
        from sync_events
        where store_id = ${change.storeId}
          and branch_id = ${change.branchId}
          and (
            id = ${change.id}
            or (${change.eventId} <> '' and event_id = ${change.eventId})
            or (${change.sourceCommandId} <> '' and source_command_id = ${change.sourceCommandId})
          )
        limit 1
      `;
      if (duplicateRows.length > 0) {
        latestAcceptedSequence = Math.max(latestAcceptedSequence, Number(duplicateRows[0].sequence || 0));
        ackIds.push(change.id);
        continue;
      }

      // Cloud sequence must be authoritative and monotonic per store/branch.
      // Device-local sequence values can overlap or move backwards after a
      // restore/snapshot, so never use the incoming change.sequence as the
      // server cursor stored in sync_events.
      change.sequence = await allocateServerSequence(change.storeId, change.branchId);

      const inserted = await sql`
        insert into sync_events (
          id, store_id, branch_id, device_id, entity_type, entity_id, operation, payload, created_at, store_epoch, sequence, event_id, request_id, source_command_id
        ) values (
          ${change.id}, ${change.storeId}, ${change.branchId}, ${change.deviceId}, ${change.entityType}, ${change.entityId}, ${change.operation}, ${JSON.stringify(change.payload)}, ${change.createdAt}, ${change.storeEpoch}, ${change.sequence}, ${change.eventId}, ${change.requestId}, ${change.sourceCommandId}
        )
        on conflict (id) do nothing
        returning id, sequence
      `;
      if (inserted.length > 0) {
        await materializeChange(change);
        await cleanupExpiredSoftDeletes(change.storeId, change.branchId);
        latestAcceptedSequence = Math.max(latestAcceptedSequence, Number(inserted[0].sequence || change.sequence || 0));
      }
      latestAcceptedAt = change.createdAt;
      ackIds.push(change.id);
    }

    const deviceId = String(body.deviceId || body.device_id || req.headers['x-device-id'] || fallback.deviceId || '').trim();
    const storeId = String(fallback.storeId || (changes[0] && (changes[0].storeId || changes[0].store_id)) || '').trim();
    const branchId = String(fallback.branchId || (changes[0] && (changes[0].branchId || changes[0].branch_id)) || 'main').trim() || 'main';
    if (storeId && deviceId) {
      const cursor = safeDate(body.cursor || body.lastAppliedCursor || body.last_applied_cursor || latestAcceptedAt);
      const sequence = Math.max(Number(body.sequence || body.lastAppliedSequence || body.last_applied_sequence || 0), latestAcceptedSequence);
      await sql`
        update store_devices
        set last_sync_transport = 'cloud',
            active_transport = case when coalesce(active_transport, '') = '' then 'cloud' else active_transport end,
            last_ack_cursor = greatest(coalesce(last_ack_cursor, 'epoch'::timestamptz), coalesce(${cursor}::timestamptz, last_ack_cursor, 'epoch'::timestamptz)),
            last_ack_sequence = greatest(coalesce(last_ack_sequence, 0), ${sequence}),
            last_ack_at = now(),
            online = true,
            last_seen_at = now(),
            updated_at = now()
        where store_id = ${storeId}
          and branch_id = ${branchId}
          and device_id = ${deviceId}
      `;
    }

    if (storeId && latestAcceptedSequence > 0) {
      notifySyncChanged({ storeId, branchId, latestSequence: latestAcceptedSequence });
    }

    res.status(200).json({ ok: true, ackIds, acceptedSequence: latestAcceptedSequence, serverTime: new Date().toISOString() });
  } catch (error) {
    sendError(res, error);
  }
}
