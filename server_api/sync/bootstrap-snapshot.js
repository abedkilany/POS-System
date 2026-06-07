import zlib from 'zlib';
import { sql, assertSyncTokenOrDevice, assertStoreAllowed, ensureDeviceAuthColumns, sendError } from '../_db.js';

const collectionTypes = {
  products: 'product',
  customers: 'customer',
  sales: 'sale',
  suppliers: 'supplier',
  supplierProductPrices: 'supplier_product_price',
  expenses: 'expense',
  categories: 'category',
  brands: 'brand',
  units: 'unit',
  purchases: 'purchase',
  stockMovements: 'stock_movement',
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
  await sql`alter table entity_snapshots add column if not exists branch_id text not null default 'main'`;
  await sql`create unique index if not exists idx_entity_snapshots_unique on entity_snapshots (store_id, branch_id, entity_type, entity_id)`;
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
    if (req.method !== 'POST') return res.status(405).json({ ok: false, error: 'Method not allowed' });
    await ensureTables();

    const body = req.body || {};
    const storeId = String(body.storeId || body.store_id || 'default-store');
    const branchId = String(body.branchId || body.branch_id || 'main');
    const jobId = String(body.jobId || body.job_id || '').trim();
    const deviceId = String(body.deviceId || body.device_id || req.headers['x-device-id'] || '').trim();
    const collection = String(body.collection || '').trim();
    const ordinal = Number(body.ordinal || 0);
    const totalChunks = Math.max(Number(body.totalChunks || body.total_chunks || 1), 1);
    const force = body.force === true || String(body.force || '').toLowerCase() === 'true';
    const updatedAt = new Date(body.generatedAt || Date.now()).toISOString();

    if (!jobId) return res.status(400).json({ ok: false, error: 'Missing snapshot jobId.' });
    if (!collection) return res.status(400).json({ ok: false, error: 'Missing snapshot collection.' });
    assertStoreAllowed(storeId);
    await assertSyncTokenOrDevice(req, { storeId, branchId, allowedRoles: ['host'], allowedTransports: ['cloud'] });

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
      await sql`delete from entity_snapshots where store_id = ${storeId} and branch_id = ${branchId}`;
      await sql`
        insert into bootstrap_snapshot_jobs (store_id, branch_id, job_id, device_id, status, total_chunks, received_chunks)
        values (${storeId}, ${branchId}, ${jobId}, ${deviceId}, 'uploading', ${totalChunks}, 0)
        on conflict (store_id, branch_id, job_id) do update set
          status = 'uploading', total_chunks = excluded.total_chunks, updated_at = now()
      `;
    }

    const payload = decodePayload(body);
    if (collection === '_meta') {
      if (payload.storeProfile && typeof payload.storeProfile === 'object') {
        await upsertSnapshot({ storeId, branchId, entityType: 'store_profile', entityId: 'store', operation: 'upsert', payload: payload.storeProfile, updatedAt });
      }
    } else {
      const entityType = collectionTypes[collection];
      if (!entityType) return res.status(400).json({ ok: false, error: `Unsupported snapshot collection: ${collection}` });
      const items = Array.isArray(payload.items) ? payload.items : [];
      for (let i = 0; i < items.length; i += 1) {
        const item = items[i];
        await upsertSnapshot({ storeId, branchId, entityType, entityId: idOf(item, `${collection}-${ordinal}-${i}`), operation: 'upsert', payload: item, updatedAt });
      }
    }

    const rows = await sql`
      update bootstrap_snapshot_jobs
      set received_chunks = least(total_chunks, received_chunks + 1),
          status = case when received_chunks + 1 >= total_chunks then 'completed' else 'uploading' end,
          updated_at = now()
      where store_id = ${storeId} and branch_id = ${branchId} and job_id = ${jobId}
      returning status, received_chunks, total_chunks
    `;
    const job = rows[0] || { status: 'uploading', received_chunks: ordinal + 1, total_chunks: totalChunks };
    return res.status(200).json({ ok: true, jobId, status: job.status, receivedChunks: job.received_chunks, totalChunks: job.total_chunks });
  } catch (error) {
    sendError(res, error);
  }
}
