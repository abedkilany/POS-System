import zlib from 'zlib';
import { sql, assertAccountOrDevice, assertStoreAllowed, ensureDeviceAuthColumns, sendError } from '../_db.js';

const collectionTypes = {
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
  warehouseInventory: 'warehouse_inventory',
  stockOperations: 'stock_operation',
  inventoryReconciliations: 'inventory_reconciliation',
  inventoryMigrationAdjustments: 'inventory_migration_adjustment',
  accountTransactions: 'account_transaction',
  roles: 'role',
  users: 'user',
};

function decodePayload(body) {
  const encoding = String(body.encoding || '').toLowerCase();
  if (encoding === 'gzip+base64+json') {
    const compressed = Buffer.from(String(body.payload || ''), 'base64');
    return JSON.parse(zlib.gunzipSync(compressed).toString('utf8'));
  }
  if (body.payload && typeof body.payload === 'object') return body.payload;
  return {};
}

function idOf(item, fallback) {
  if (item && typeof item === 'object' && item.id != null && String(item.id).trim()) return String(item.id);
  return fallback;
}

async function ensureTables() {
  await sql`
    create table if not exists store_devices (
      store_id text not null,
      branch_id text not null default 'main',
      device_id text not null,
      device_name text default '',
      platform text default '',
      role text default '',
      transport text default '',
      app_version text default '',
      store_epoch integer not null default 1,
      revoked boolean not null default false,
      device_token text default '',
      host_device_id text default '',
      last_seen_at timestamptz not null default now(),
      updated_at timestamptz not null default now(),
      primary key (store_id, branch_id, device_id)
    )
  `;
  await ensureDeviceAuthColumns();
  await sql`
    create table if not exists entity_snapshots (
      store_id text not null,
      branch_id text not null default 'main',
      entity_type text not null,
      entity_id text not null,
      payload jsonb not null default '{}'::jsonb,
      operation text not null,
      updated_at timestamptz not null default now(),
      primary key (store_id, branch_id, entity_type, entity_id)
    )
  `;
  await sql`create table if not exists bootstrap_snapshot_jobs (
    store_id text not null,
    branch_id text not null default 'main',
    job_id text not null,
    device_id text not null default '',
    status text not null default 'building',
    total_chunks integer not null default 0,
    received_chunks integer not null default 0,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    primary key (store_id, branch_id, job_id)
  )`;
  await sql`create table if not exists bootstrap_snapshot_sections (
    store_id text not null,
    branch_id text not null default 'main',
    job_id text not null,
    section text not null,
    entity_type text not null default '',
    status text not null default 'uploading',
    total_chunks integer not null default 0,
    received_chunks integer not null default 0,
    completed_at timestamptz,
    updated_at timestamptz not null default now(),
    primary key (store_id, branch_id, job_id, section)
  )`;
  await sql`create index if not exists idx_bootstrap_snapshot_sections_latest on bootstrap_snapshot_sections (store_id, branch_id, section, updated_at desc)`;
  await sql`create table if not exists unified_snapshot_chunks (
    store_id text not null,
    branch_id text not null default 'main',
    job_id text not null,
    ordinal integer not null,
    total_chunks integer not null default 0,
    chunk jsonb not null default '{}'::jsonb,
    snapshot_manifest jsonb not null default '{}'::jsonb,
    sync_generated_at timestamptz not null default now(),
    sync_generated_sequence integer not null default 0,
    updated_at timestamptz not null default now(),
    primary key (store_id, branch_id, job_id, ordinal)
  )`;
  await sql`create index if not exists idx_unified_snapshot_chunks_latest on unified_snapshot_chunks (store_id, branch_id, updated_at desc, job_id, ordinal)`;
  await sql`alter table entity_snapshots add column if not exists branch_id text not null default 'main'`;
  await sql`create unique index if not exists idx_entity_snapshots_unique on entity_snapshots (store_id, branch_id, entity_type, entity_id)`;
}


async function upsertSnapshotsBatch(rows) {
  if (!rows.length) return;
  await sql`
    insert into entity_snapshots (store_id, branch_id, entity_type, entity_id, payload, operation, updated_at)
    select store_id, branch_id, entity_type, entity_id, payload, operation, updated_at::timestamptz
    from jsonb_to_recordset(${JSON.stringify(rows)}::jsonb) as x(
      store_id text,
      branch_id text,
      entity_type text,
      entity_id text,
      payload jsonb,
      operation text,
      updated_at text
    )
    on conflict (store_id, branch_id, entity_type, entity_id) do update set
      payload = excluded.payload,
      operation = excluded.operation,
      updated_at = excluded.updated_at
  `;
}

async function upsertSnapshot({ storeId, branchId, entityType, entityId, operation, payload, updatedAt }) {
  await sql`
    insert into entity_snapshots (store_id, branch_id, entity_type, entity_id, payload, operation, updated_at)
    values (${storeId}, ${branchId || 'main'}, ${entityType}, ${entityId}, ${JSON.stringify(payload || {})}, ${operation || 'upsert'}, ${updatedAt})
    on conflict (store_id, branch_id, entity_type, entity_id) do update set
      payload = excluded.payload,
      operation = excluded.operation,
      updated_at = excluded.updated_at
  `;
}

export default async function handler(req, res) {
  try {
    await ensureTables();

    if (req.method === 'GET') {
      const storeId = String(req.query.store_id || req.query.storeId || 'default-store');
      const branchId = String(req.query.branch_id || req.query.branchId || 'main');
      assertStoreAllowed(storeId);
      await assertAccountOrDevice(req, { storeId, branchId, allowedRoles: ['host', 'client'], allowedTransports: ['cloud'] });
      const mode = String(req.query.mode || '').trim().toLowerCase();
      const jobIdQuery = String(req.query.job_id || req.query.jobId || '').trim();
      const latestJobRows = jobIdQuery
        ? [{ job_id: jobIdQuery }]
        : await sql`
            select job_id
            from bootstrap_snapshot_jobs
            where store_id = ${storeId}
              and branch_id = ${branchId}
              and status = 'completed'
            order by updated_at desc
            limit 1
          `;
      const jobId = latestJobRows[0]?.job_id || '';
      if (!jobId) return res.status(404).json({ ok: false, error: 'No completed unified snapshot is available.' });

      if (mode === 'manifest') {
        const rows = await sql`
          select chunk, snapshot_manifest, total_chunks, sync_generated_at, sync_generated_sequence
          from unified_snapshot_chunks
          where store_id = ${storeId}
            and branch_id = ${branchId}
            and job_id = ${jobId}
          order by ordinal asc
          limit 1
        `;
        const first = rows[0];
        if (!first) return res.status(404).json({ ok: false, error: 'Snapshot manifest not found.' });
        const chunk = first.chunk || {};
        const snapshotSequence = Number(first.sync_generated_sequence || 0);
        const safeGeneratedRows = snapshotSequence > 0
          ? await sql`
              select coalesce(max(received_at), ${first.sync_generated_at}::timestamptz) as generated_at
              from sync_events
              where store_id = ${storeId}
                and branch_id = ${branchId}
                and sequence <= ${snapshotSequence}
            `
          : [];
        const safeGeneratedAt = safeGeneratedRows[0]?.generated_at || first.sync_generated_at;
        return res.status(200).json({
          ok: true,
          jobId,
          snapshotFormat: chunk.snapshotFormat,
          snapshotVersion: chunk.snapshotVersion,
          snapshotKind: chunk.snapshotKind,
          snapshotManifest: first.snapshot_manifest || chunk.snapshotManifest || {},
          totalChunks: Number(first.total_chunks || chunk.totalChunks || 0),
          syncGeneratedAt: new Date(safeGeneratedAt).toISOString(),
          syncGeneratedSequence: snapshotSequence,
          hostSnapshotGeneration: String(chunk.hostSnapshotGeneration || chunk.snapshotGeneration || chunk.restoreGeneration || ''),
          snapshotGeneration: String(chunk.hostSnapshotGeneration || chunk.snapshotGeneration || chunk.restoreGeneration || ''),
          hostRestoreCommandId: String(chunk.hostRestoreCommandId || chunk.restoreCommandId || chunk.rebuildCommandId || ''),
          restoreCommandId: String(chunk.hostRestoreCommandId || chunk.restoreCommandId || chunk.rebuildCommandId || ''),
        });
      }

      if (mode === 'chunk') {
        const ordinal = Math.max(Number(req.query.ordinal || 0), 0);
        const rows = await sql`
          select chunk, total_chunks
          from unified_snapshot_chunks
          where store_id = ${storeId}
            and branch_id = ${branchId}
            and job_id = ${jobId}
            and ordinal = ${ordinal}
          limit 1
        `;
        const row = rows[0];
        if (!row) return res.status(404).json({ ok: false, error: 'Snapshot chunk not found.' });
        return res.status(200).json({
          ok: true,
          jobId,
          ordinal,
          totalChunks: Number(row.total_chunks || 0),
          chunk: row.chunk || {},
        });
      }
      return res.status(400).json({ ok: false, error: 'Unsupported snapshot GET mode.' });
    }

    if (req.method !== 'POST') return res.status(405).json({ ok: false, error: 'Method not allowed' });

    const body = req.body || {};
    const storeId = String(body.storeId || body.store_id || 'default-store');
    const branchId = String(body.branchId || body.branch_id || 'main');
    const jobId = String(body.jobId || body.job_id || '').trim();
    const deviceId = String(body.deviceId || body.device_id || req.headers['x-device-id'] || '').trim();
    const collection = String(body.collection || '').trim();
    const ordinal = Number(body.ordinal || 0);
    const totalChunks = Math.max(Number(body.totalChunks || body.total_chunks || 1), 1);
    const sectionTotalChunks = Math.max(Number(body.sectionTotalChunks || body.section_total_chunks || 1), 1);
    const force = body.force === true || String(body.force || '').toLowerCase() === 'true';
    const preserveExisting = body.preserveExisting === true || String(body.preserveExisting || body.preserve_existing || '').toLowerCase() === 'true';
    const allSections = Array.isArray(body.allSections || body.all_sections) ? (body.allSections || body.all_sections).map((item) => String(item || '').trim()).filter(Boolean) : [];
    const updatedAt = new Date(body.generatedAt || Date.now()).toISOString();

    if (!jobId) return res.status(400).json({ ok: false, error: 'Missing snapshot jobId.' });
    if (!collection) return res.status(400).json({ ok: false, error: 'Missing snapshot collection.' });
    assertStoreAllowed(storeId);
    await assertAccountOrDevice(req, { storeId, branchId, allowedRoles: ['host'], allowedTransports: ['cloud'] });

    await sql`
      insert into unified_snapshot_chunks (store_id, branch_id, job_id, ordinal, total_chunks, chunk, snapshot_manifest, sync_generated_at, sync_generated_sequence, updated_at)
      values (${storeId}, ${branchId}, ${jobId}, ${ordinal}, ${totalChunks}, ${JSON.stringify(body || {})}, ${JSON.stringify(body.snapshotManifest || {})}, ${updatedAt}, ${Number(body.syncGeneratedSequence || body.sync_generated_sequence || 0)}, now())
      on conflict (store_id, branch_id, job_id, ordinal) do update set
        total_chunks = excluded.total_chunks,
        chunk = excluded.chunk,
        snapshot_manifest = excluded.snapshot_manifest,
        sync_generated_at = excluded.sync_generated_at,
        sync_generated_sequence = excluded.sync_generated_sequence,
        updated_at = now()
    `;

    if (ordinal === 0) {
      const active = await sql`
        select job_id from bootstrap_snapshot_jobs
        where store_id = ${storeId}
          and branch_id = ${branchId}
          and status in ('building', 'uploading')
          and updated_at > now() - interval '10 minutes'
          and job_id <> ${jobId}
        limit 1
      `;
      if (active.length && !force) {
        return res.status(409).json({ ok: false, error: 'A bootstrap snapshot is already in progress.', activeJobId: active[0].job_id });
      }
      if (force) {
        await sql`update bootstrap_snapshot_jobs set status = 'cancelled', updated_at = now() where store_id = ${storeId} and branch_id = ${branchId} and status in ('building', 'uploading') and job_id <> ${jobId}`;
      }
      if (!preserveExisting) {
        await sql`delete from entity_snapshots where store_id = ${storeId} and branch_id = ${branchId}`;
        await sql`delete from bootstrap_snapshot_sections where store_id = ${storeId} and branch_id = ${branchId}`;
      }
      await sql`
        insert into bootstrap_snapshot_jobs (store_id, branch_id, job_id, device_id, status, total_chunks, received_chunks)
        values (${storeId}, ${branchId}, ${jobId}, ${deviceId}, 'uploading', ${totalChunks}, 0)
        on conflict (store_id, branch_id, job_id) do update set
          status = 'uploading', total_chunks = excluded.total_chunks, updated_at = now()
      `;

      if (allSections.length) {
        const sectionRows = allSections.map((section) => ({
          store_id: storeId,
          branch_id: branchId,
          job_id: jobId,
          section,
          entity_type: section === '_meta' ? 'store_profile' : (collectionTypes[section] || ''),
          status: 'pending',
          total_chunks: 0,
          received_chunks: 0,
        }));
        await sql`
          insert into bootstrap_snapshot_sections (store_id, branch_id, job_id, section, entity_type, status, total_chunks, received_chunks, updated_at)
          select store_id, branch_id, job_id, section, entity_type, status, total_chunks, received_chunks, now()
          from jsonb_to_recordset(${JSON.stringify(sectionRows)}::jsonb) as x(
            store_id text,
            branch_id text,
            job_id text,
            section text,
            entity_type text,
            status text,
            total_chunks integer,
            received_chunks integer
          )
          on conflict (store_id, branch_id, job_id, section) do update set
            entity_type = excluded.entity_type,
            status = case when bootstrap_snapshot_sections.status = 'completed' then 'completed' else 'pending' end,
            updated_at = now()
        `;
      }
    }

    const entityTypeForSection = collection === '_meta' ? 'store_profile' : (collectionTypes[collection] || '');
    await sql`
      insert into bootstrap_snapshot_sections (store_id, branch_id, job_id, section, entity_type, status, total_chunks, received_chunks, updated_at)
      values (${storeId}, ${branchId}, ${jobId}, ${collection}, ${entityTypeForSection}, 'uploading', ${sectionTotalChunks}, 0, now())
      on conflict (store_id, branch_id, job_id, section) do update set
        entity_type = excluded.entity_type,
        status = 'uploading',
        total_chunks = greatest(bootstrap_snapshot_sections.total_chunks, excluded.total_chunks),
        updated_at = now()
    `;

    const payload = decodePayload(body);
    if (collection === '_meta') {
      if (payload.storeProfile && typeof payload.storeProfile === 'object') {
        await upsertSnapshot({ storeId, branchId, entityType: 'store_profile', entityId: 'store', operation: 'upsert', payload: payload.storeProfile, updatedAt });
      }
    } else {
      const entityType = collectionTypes[collection];
      if (!entityType) return res.status(400).json({ ok: false, error: `Unsupported snapshot collection: ${collection}` });
      const items = Array.isArray(payload.items) ? payload.items : [];
      const rows = items.map((item, i) => ({
        store_id: storeId,
        branch_id: branchId || 'main',
        entity_type: entityType,
        entity_id: idOf(item, `${collection}-${ordinal}-${i}`),
        payload: item || {},
        operation: 'upsert',
        updated_at: updatedAt,
      }));
      await upsertSnapshotsBatch(rows);
    }

    const rows = await sql`
      update bootstrap_snapshot_jobs
      set received_chunks = least(total_chunks, received_chunks + 1),
          status = case when received_chunks + 1 >= total_chunks then 'completed' else 'uploading' end,
          updated_at = now()
      where store_id = ${storeId} and branch_id = ${branchId} and job_id = ${jobId}
      returning status, received_chunks, total_chunks
    `;
    const sectionRows = await sql`
      update bootstrap_snapshot_sections
      set received_chunks = least(total_chunks, received_chunks + 1),
          status = case when received_chunks + 1 >= total_chunks then 'completed' else 'uploading' end,
          completed_at = case when received_chunks + 1 >= total_chunks then coalesce(completed_at, now()) else completed_at end,
          updated_at = now()
      where store_id = ${storeId} and branch_id = ${branchId} and job_id = ${jobId} and section = ${collection}
      returning status, received_chunks, total_chunks
    `;
    const job = rows[0] || { status: 'uploading', received_chunks: ordinal + 1, total_chunks: totalChunks };
    const sectionJob = sectionRows[0] || { status: 'uploading', received_chunks: 1, total_chunks: sectionTotalChunks };
    return res.status(200).json({ ok: true, jobId, status: job.status, receivedChunks: job.received_chunks, totalChunks: job.total_chunks, section: collection, sectionStatus: sectionJob.status, sectionReceivedChunks: sectionJob.received_chunks, sectionTotalChunks: sectionJob.total_chunks });
  } catch (error) {
    sendError(res, error);
  }
}
