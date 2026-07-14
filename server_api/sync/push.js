import { sql, assertAccountOrDevice, assertStoreAllowed, ensureDeviceAuthColumns, sendError } from '../_db.js';
import { notifySyncChanged } from './realtime.js';
import { gunzipSync } from 'zlib';

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

async function allocateServerSequenceRange(storeId, branchId, count) {
  const safeCount = Math.max(0, Number(count || 0));
  if (safeCount <= 0) return { first: 0, last: 0 };
  const rows = await sql`
    insert into cloud_sync_sequences (store_id, branch_id, last_sequence, updated_at)
    values (${storeId}, ${branchId || 'main'}, ${safeCount}, now())
    on conflict (store_id, branch_id) do update set
      last_sequence = cloud_sync_sequences.last_sequence + ${safeCount},
      updated_at = now()
    returning last_sequence
  `;
  const last = Number(rows[0]?.last_sequence || 0);
  return { first: Math.max(1, last - safeCount + 1), last };
}

function decodeIncomingChanges(body) {
  if (Array.isArray(body.changes)) return body.changes;
  const encoding = String(body.changesEncoding || body.encoding || '').trim().toLowerCase();
  const payload = String(body.changesPayload || body.payload || '').trim();
  if (!payload) return [];
  const bytes = Buffer.from(payload, 'base64');
  const jsonText = encoding.includes('gzip')
    ? gunzipSync(bytes).toString('utf8')
    : bytes.toString('utf8');
  const decoded = JSON.parse(jsonText);
  if (!Array.isArray(decoded)) throw new Error('Compressed pending changes payload must decode to an array.');
  return decoded;
}

function isSimpleMaterializationChange(change) {
  if (!change || change.entityType === 'system') return false;
  if (change.operation === 'reset_store_data') return false;
  if (change.entityType === 'stock_movement') return false;
  return change.operation === 'delete' || change.operation === 'upsert' || change.operation === 'create' || change.operation === 'update';
}

function latestSimpleMaterializationRows(changes) {
  const byKey = new Map();
  for (const change of changes) {
    if (!isSimpleMaterializationChange(change)) continue;
    const key = [change.storeId, change.branchId || 'main', change.entityType, change.entityId].join('|');
    byKey.set(key, {
      store_id: change.storeId,
      branch_id: change.branchId || 'main',
      entity_type: change.entityType,
      entity_id: change.entityId,
      operation: change.operation === 'delete' ? 'delete' : 'upsert',
      payload: change.payload || {},
      updated_at: change.createdAt || new Date().toISOString(),
    });
  }
  return Array.from(byKey.values());
}

async function materializeSimpleChangesBulk(changes) {
  const rows = latestSimpleMaterializationRows(changes);
  if (!rows.length) return;
  await sql`
    with incoming as (
      select *
      from jsonb_to_recordset(${JSON.stringify(rows)}::jsonb) as x(
        store_id text,
        branch_id text,
        entity_type text,
        entity_id text,
        operation text,
        payload jsonb,
        updated_at timestamptz
      )
    )
    insert into entity_snapshots (store_id, branch_id, entity_type, entity_id, payload, operation, updated_at)
    select store_id, branch_id, entity_type, entity_id, payload, operation, updated_at
    from incoming
    on conflict (store_id, branch_id, entity_type, entity_id) do update set
      payload = excluded.payload,
      operation = excluded.operation,
      updated_at = excluded.updated_at
    where
      (case when coalesce(excluded.payload->>'version', '') ~ '^[0-9]+(\\.[0-9]+)?$' then (excluded.payload->>'version')::numeric else 1 end) >
      (case when coalesce(entity_snapshots.payload->>'version', '') ~ '^[0-9]+(\\.[0-9]+)?$' then (entity_snapshots.payload->>'version')::numeric else 1 end)
      or (
        (case when coalesce(excluded.payload->>'version', '') ~ '^[0-9]+(\\.[0-9]+)?$' then (excluded.payload->>'version')::numeric else 1 end) =
        (case when coalesce(entity_snapshots.payload->>'version', '') ~ '^[0-9]+(\\.[0-9]+)?$' then (entity_snapshots.payload->>'version')::numeric else 1 end)
        and excluded.updated_at >= entity_snapshots.updated_at
      )
  `;
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
  warehouseInventory: 'warehouse_inventory',
  stockOperations: 'stock_operation',
  inventoryReconciliations: 'inventory_reconciliation',
  inventoryMigrationAdjustments: 'inventory_migration_adjustment',
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

function isWarehouseAwareStockMovement(payload) {
  if (!payload || typeof payload !== 'object') return false;
  return Boolean(
    String(payload.warehouseId || payload.warehouse_id || '').trim() ||
    String(payload.idempotencyKey || payload.idempotency_key || '').trim() ||
    String(payload.movementGroupId || payload.movement_group_id || '').trim() ||
    String(payload.documentLineId || payload.document_line_id || '').trim()
  );
}

function movementIdempotencyKey(payload) {
  if (!payload || typeof payload !== 'object') return '';
  return String(payload.idempotencyKey || payload.idempotency_key || '').trim();
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
    const branch = change.branchId || 'main';
    const warehouseAware = isWarehouseAwareStockMovement(p);
    if (warehouseAware) {
      const warehouseId = String(p.warehouseId || p.warehouse_id || 'main').trim() || 'main';
      const idempotencyKey = movementIdempotencyKey(p);
      const duplicateRows = idempotencyKey
        ? await sql`
            select 1
            from entity_snapshots
            where store_id = ${change.storeId}
              and branch_id = ${branch}
              and entity_type = 'stock_movement'
              and (
                entity_id = ${change.entityId}
                or payload->>'idempotencyKey' = ${idempotencyKey}
                or payload->>'idempotency_key' = ${idempotencyKey}
              )
            limit 1
          `
        : await sql`
            select 1
            from entity_snapshots
            where store_id = ${change.storeId}
              and branch_id = ${branch}
              and entity_type = 'stock_movement'
              and entity_id = ${change.entityId}
            limit 1
          `;
      if (duplicateRows.length) {
        return;
      }
      const movementSnapshotId = change.entityId;
      await upsertSnapshot({
        storeId: change.storeId,
        branchId: branch,
        entityType: 'stock_movement',
        entityId: movementSnapshotId,
        operation: 'upsert',
        payload: p,
        updatedAt,
      });
      const warehouseRows = await sql`
        select coalesce(sum((payload->>'quantity')::numeric), 0) as quantity
        from entity_snapshots
        where store_id = ${change.storeId}
          and branch_id = ${branch}
          and entity_type = 'warehouse_inventory'
          and payload->>'productId' = ${productId}
          and payload->>'warehouseId' = ${warehouseId}
      `;
      const productBalanceRows = await sql`
        select coalesce(sum((payload->>'quantity')::numeric), 0) as quantity
        from entity_snapshots
        where store_id = ${change.storeId}
          and branch_id = ${branch}
          and entity_type = 'warehouse_inventory'
          and payload->>'productId' = ${productId}
      `;
      const nextWarehouseQuantity = Number(warehouseRows[0]?.quantity || 0) + quantity;
      const nextProductQuantity = Number(productBalanceRows[0]?.quantity || 0) + quantity;
      await upsertSnapshot({
        storeId: change.storeId,
        branchId: branch,
        entityType: 'warehouse_inventory',
        entityId: `${warehouseId}::${productId}`,
        operation: 'upsert',
        payload: {
          id: p.id || `${change.storeId}_${warehouseId}_${productId}`,
          storeId: change.storeId,
          branchId: branch,
          warehouseId,
          productId,
          quantity: nextWarehouseQuantity,
          updatedAt,
          createdAt: p.createdAt || updatedAt,
          deviceId: p.deviceId || change.deviceId || '',
          syncStatus: 'synced',
          lastModifiedByDeviceId: p.lastModifiedByDeviceId || p.deviceId || change.deviceId || '',
        },
        updatedAt,
        force: true,
      });
      const productRows = await sql`
        select payload, operation, updated_at
        from entity_snapshots
        where store_id = ${change.storeId}
          and branch_id = ${branch}
          and entity_type = 'product'
          and entity_id = ${productId}
        limit 1
      `;
      if (productRows.length && productRows[0].operation !== 'delete') {
        const product = productRows[0].payload || {};
        const nextProduct = {
          ...product,
          stock: nextProductQuantity,
          updatedAt,
          syncStatus: 'synced',
          storeId: change.storeId,
          branchId: branch,
        };
        await upsertSnapshot({
          storeId: change.storeId,
          branchId: branch,
          entityType: 'product',
          entityId: productId,
          operation: 'upsert',
          payload: nextProduct,
          updatedAt,
          force: true,
        });
      }
      return;
    }

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

    const legacyWarehouseId = 'main';
    const productRows = await sql`
      select payload, operation, updated_at
      from entity_snapshots
      where store_id = ${change.storeId}
        and branch_id = ${change.branchId || 'main'}
        and entity_type = 'product'
        and entity_id = ${productId}
      limit 1
    `;
    if (!productRows.length || productRows[0].operation === 'delete') return;

    const product = productRows[0].payload || {};
    const legacyWarehouseRows = await sql`
      select coalesce(sum((payload->>'quantity')::numeric), 0) as quantity
      from entity_snapshots
      where store_id = ${change.storeId}
        and branch_id = ${change.branchId || 'main'}
        and entity_type = 'warehouse_inventory'
        and payload->>'productId' = ${productId}
        and payload->>'warehouseId' = ${legacyWarehouseId}
    `;
    const legacyWarehouseQuantity = Number(legacyWarehouseRows[0]?.quantity || 0) + quantity;
    await upsertSnapshot({
      storeId: change.storeId,
      branchId: change.branchId,
      entityType: 'warehouse_inventory',
      entityId: `${legacyWarehouseId}::${productId}`,
      operation: 'upsert',
      payload: {
        id: p.id || `${change.storeId}_${legacyWarehouseId}_${productId}`,
        storeId: change.storeId,
        branchId: change.branchId || 'main',
        warehouseId: legacyWarehouseId,
        productId,
        quantity: legacyWarehouseQuantity,
        updatedAt,
        createdAt: p.createdAt || updatedAt,
        deviceId: p.deviceId || change.deviceId || '',
        syncStatus: 'synced',
        lastModifiedByDeviceId: p.lastModifiedByDeviceId || p.deviceId || change.deviceId || '',
      },
      updatedAt,
      force: true,
    });
    const productBalanceRowsAfter = await sql`
      select coalesce(sum((payload->>'quantity')::numeric), 0) as quantity
      from entity_snapshots
      where store_id = ${change.storeId}
        and branch_id = ${change.branchId || 'main'}
        and entity_type = 'warehouse_inventory'
        and payload->>'productId' = ${productId}
    `;
    const currentStock = Number(productBalanceRowsAfter[0]?.quantity || 0);
    const nextProduct = {
      ...product,
      stock: currentStock,
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
    const changes = decodeIncomingChanges(body);
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

    const normalizedChanges = [];
    for (const raw of changes) {
      const change = normalizeChange(raw, fallback);
      assertStoreAllowed(change.storeId);
      const syncV2Kind = change.payload && change.payload._syncV2 && String(change.payload._syncV2.kind || '');
      if (syncV2Kind === 'draftCommand') {
        return res.status(403).json({ ok: false, error: 'Draft commands must be sent to the Host relay, not the authoritative event stream.' });
      }
      normalizedChanges.push(change);
    }

    const ackIds = [];
    let latestAcceptedAt = null;
    let latestAcceptedSequence = 0;
    const duplicateIds = new Set();
    if (normalizedChanges.length) {
      const lookupRows = normalizedChanges.map((change) => ({
        id: change.id,
        store_id: change.storeId,
        branch_id: change.branchId || 'main',
        event_id: change.eventId || '',
        source_command_id: change.sourceCommandId || '',
      }));
      const duplicates = await sql`
        with incoming as (
          select *
          from jsonb_to_recordset(${JSON.stringify(lookupRows)}::jsonb) as x(
            id text,
            store_id text,
            branch_id text,
            event_id text,
            source_command_id text
          )
        )
        select distinct incoming.id as incoming_id, sync_events.sequence
        from incoming
        join sync_events on sync_events.store_id = incoming.store_id
          and sync_events.branch_id = incoming.branch_id
          and (
            sync_events.id = incoming.id
            or (incoming.event_id <> '' and sync_events.event_id = incoming.event_id)
            or (incoming.source_command_id <> '' and sync_events.source_command_id = incoming.source_command_id)
          )
      `;
      for (const row of duplicates) {
        duplicateIds.add(String(row.incoming_id));
        latestAcceptedSequence = Math.max(latestAcceptedSequence, Number(row.sequence || 0));
      }
    }

    const freshChanges = normalizedChanges.filter((change) => !duplicateIds.has(change.id));
    const groupedFresh = new Map();
    for (const change of freshChanges) {
      const key = [change.storeId, change.branchId || 'main'].join('|');
      if (!groupedFresh.has(key)) groupedFresh.set(key, []);
      groupedFresh.get(key).push(change);
    }
    for (const group of groupedFresh.values()) {
      const range = await allocateServerSequenceRange(group[0].storeId, group[0].branchId, group.length);
      for (let i = 0; i < group.length; i += 1) {
        group[i].sequence = range.first + i;
      }
    }

    const insertedChanges = [];
    if (freshChanges.length) {
      const eventRows = freshChanges.map((change) => ({
        id: change.id,
        store_id: change.storeId,
        branch_id: change.branchId || 'main',
        device_id: change.deviceId,
        entity_type: change.entityType,
        entity_id: change.entityId,
        operation: change.operation,
        payload: change.payload || {},
        created_at: change.createdAt,
        store_epoch: change.storeEpoch,
        sequence: change.sequence,
        event_id: change.eventId || '',
        request_id: change.requestId || '',
        source_command_id: change.sourceCommandId || '',
      }));
      const inserted = await sql`
        with incoming as (
          select *
          from jsonb_to_recordset(${JSON.stringify(eventRows)}::jsonb) as x(
            id text,
            store_id text,
            branch_id text,
            device_id text,
            entity_type text,
            entity_id text,
            operation text,
            payload jsonb,
            created_at timestamptz,
            store_epoch integer,
            sequence bigint,
            event_id text,
            request_id text,
            source_command_id text
          )
        )
        insert into sync_events (
          id, store_id, branch_id, device_id, entity_type, entity_id, operation, payload, created_at, store_epoch, sequence, event_id, request_id, source_command_id
        )
        select id, store_id, branch_id, device_id, entity_type, entity_id, operation, payload, created_at, store_epoch, sequence, event_id, request_id, source_command_id
        from incoming
        on conflict do nothing
        returning id, sequence
      `;
      const insertedById = new Map(inserted.map((row) => [String(row.id), Number(row.sequence || 0)]));
      for (const change of freshChanges) {
        if (!insertedById.has(change.id)) continue;
        latestAcceptedSequence = Math.max(latestAcceptedSequence, insertedById.get(change.id) || change.sequence || 0);
        insertedChanges.push(change);
      }
      await materializeSimpleChangesBulk(insertedChanges);
      for (const change of insertedChanges) {
        if (isSimpleMaterializationChange(change)) continue;
        await materializeChange(change);
      }
    }

    const cleanupKeys = new Set();
    for (const change of insertedChanges) {
      cleanupKeys.add([change.storeId, change.branchId || 'main'].join('|'));
    }
    for (const key of cleanupKeys) {
      const [cleanupStoreId, cleanupBranchId] = key.split('|');
      await cleanupExpiredSoftDeletes(cleanupStoreId, cleanupBranchId);
    }

    for (const change of normalizedChanges) {
      ackIds.push(change.id);
      latestAcceptedAt = change.createdAt;
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
