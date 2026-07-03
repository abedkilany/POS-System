import { sql, assertAccountOrDevice, assertStoreAllowed, ensureDeviceAuthColumns, sendError } from '../_db.js';

function toInt(value, fallback, min, max) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.min(Math.max(Math.trunc(parsed), min), max);
}

async function ensureMaintenanceIndexes() {
  await sql`alter table sync_events add column if not exists store_epoch integer not null default 1`;
  await sql`alter table sync_events add column if not exists sequence integer not null default 0`;
  await sql`alter table sync_events add column if not exists event_id text default ''`;
  await sql`alter table sync_events add column if not exists request_id text default ''`;
  await sql`alter table sync_events add column if not exists source_command_id text default ''`;
  await sql`alter table cloud_change_requests add column if not exists rejection_reason text default ''`;
  await sql`alter table cloud_change_requests add column if not exists accepted_at timestamptz`;
  await sql`alter table cloud_change_requests add column if not exists status text not null default 'pending'`;
  await sql`alter table entity_snapshots add column if not exists branch_id text not null default 'main'`;
  await sql`create index if not exists idx_sync_events_store_branch_sequence on sync_events (store_id, branch_id, sequence)`;
  await sql`create index if not exists idx_cloud_change_requests_store_status on cloud_change_requests (store_id, branch_id, status, accepted_at, received_at)`;
  await sql`create index if not exists idx_entity_snapshots_store_type_updated on entity_snapshots (store_id, branch_id, entity_type, updated_at)`;
  await ensureDeviceAuthColumns();
}

async function assertHostDevice({ storeId, branchId, hostDeviceId }) {
  if (!hostDeviceId) {
    const err = new Error('hostDeviceId is required.');
    err.statusCode = 400;
    throw err;
  }
  const rows = await sql`
    select role, revoked, suspended
    from store_devices
    where store_id = ${storeId}
      and branch_id = ${branchId}
      and device_id = ${hostDeviceId}
    limit 1
  `;
  if (rows.length && (rows[0].revoked === true || rows[0].suspended === true || String(rows[0].role || '') !== 'host')) {
    const err = new Error('Only an active Host device can run Cloud maintenance for this store.');
    err.statusCode = 403;
    throw err;
  }
}

export default async function handler(req, res) {
  try {
    await ensureMaintenanceIndexes();
    if (req.method !== 'POST') return res.status(405).json({ ok: false, error: 'Method not allowed' });

    const body = req.body || {};
    const storeId = String(body.storeId || body.store_id || req.headers['x-store-id'] || '').trim();
    const branchId = String(body.branchId || body.branch_id || req.headers['x-branch-id'] || 'main').trim() || 'main';
    const hostDeviceId = String(body.hostDeviceId || body.host_device_id || body.deviceId || body.device_id || req.headers['x-device-id'] || '').trim();
    if (!storeId) return res.status(400).json({ ok: false, error: 'storeId is required.' });
    assertStoreAllowed(storeId);
    await assertAccountOrDevice(req, { storeId, branchId, allowedRoles: ['host'], allowedTransports: ['cloud'] });
    await assertHostDevice({ storeId, branchId, hostDeviceId });

    const eventRetentionDays = toInt(body.eventRetentionDays || body.event_retention_days, 7, 1, 365);
    const activeDeviceDays = toInt(body.activeDeviceDays || body.active_device_days, 14, 1, 365);
    const processedRequestRetentionDays = toInt(body.processedRequestRetentionDays || body.processed_request_retention_days, 3, 0, 365);
    const deletedSnapshotRetentionDays = toInt(body.deletedSnapshotRetentionDays || body.deleted_snapshot_retention_days, 7, 0, 365);

    const beforeEventsRows = await sql`select count(*)::int as count from sync_events where store_id = ${storeId} and branch_id = ${branchId}`;
    const beforeRequestsRows = await sql`select count(*)::int as count from cloud_change_requests where store_id = ${storeId} and branch_id = ${branchId}`;
    const beforeSnapshotsRows = await sql`select count(*)::int as count from entity_snapshots where store_id = ${storeId} and branch_id = ${branchId}`;

    const sequenceRows = await sql`
      select coalesce(max(sequence), 0)::bigint as latest_sequence,
             coalesce(min(nullif(sequence, 0)), 0)::bigint as earliest_sequence
      from sync_events
      where store_id = ${storeId}
        and branch_id = ${branchId}
    `;
    const latestSequence = Number(sequenceRows[0]?.latest_sequence || 0);
    const earliestSequence = Number(sequenceRows[0]?.earliest_sequence || 0);

    const ackRows = await sql`
      select min(last_ack_sequence)::bigint as safe_floor_sequence
      from store_devices
      where store_id = ${storeId}
        and branch_id = ${branchId}
        and revoked = false
        and suspended = false
        and last_ack_sequence > 0
        and last_seen_at >= now() - (${activeDeviceDays}::text || ' days')::interval
    `;
    const safeFloorSequence = Number(ackRows[0]?.safe_floor_sequence || 0);
    const retentionCutoffSql = sql`now() - (${eventRetentionDays}::text || ' days')::interval`;
    const retainFloorSequence = safeFloorSequence;

    let removedEvents = 0;
    if (safeFloorSequence > 0) {
      const deletedRows = await sql`
        delete from sync_events
        where store_id = ${storeId}
          and branch_id = ${branchId}
          and sequence > 0
          and sequence <= ${safeFloorSequence}
          and created_at < ${retentionCutoffSql}
        returning id
      `;
      removedEvents = deletedRows.length;
    }

    const requestRows = await sql`
      delete from cloud_change_requests
      where store_id = ${storeId}
        and branch_id = ${branchId}
        and status in ('accepted', 'rejected', 'processed', 'synced')
        and coalesce(accepted_at, received_at, created_at) < now() - (${processedRequestRetentionDays}::text || ' days')::interval
      returning id
    `;

    const snapshotRows = await sql`
      delete from entity_snapshots
      where store_id = ${storeId}
        and branch_id = ${branchId}
        and (
          operation = 'delete'
          or nullif(payload->>'deletedAt', '') is not null
        )
        and updated_at < now() - (${deletedSnapshotRetentionDays}::text || ' days')::interval
      returning entity_id
    `;

    const afterEventsRows = await sql`select count(*)::int as count from sync_events where store_id = ${storeId} and branch_id = ${branchId}`;
    const afterRequestsRows = await sql`select count(*)::int as count from cloud_change_requests where store_id = ${storeId} and branch_id = ${branchId}`;
    const afterSnapshotsRows = await sql`select count(*)::int as count from entity_snapshots where store_id = ${storeId} and branch_id = ${branchId}`;
    const afterSequenceRows = await sql`
      select coalesce(max(sequence), 0)::bigint as latest_sequence,
             coalesce(min(nullif(sequence, 0)), 0)::bigint as earliest_sequence
      from sync_events
      where store_id = ${storeId}
        and branch_id = ${branchId}
    `;

    return res.status(200).json({
      ok: true,
      storeId,
      branchId,
      hostDeviceId,
      eventRetentionDays,
      safeFloorSequence,
      latestSequence,
      earliestSequence,
      retainFloorSequence,
      removedEvents,
      removedRequests: requestRows.length,
      removedSnapshots: snapshotRows.length,
      before: {
        syncEvents: beforeEventsRows[0]?.count || 0,
        cloudChangeRequests: beforeRequestsRows[0]?.count || 0,
        entitySnapshots: beforeSnapshotsRows[0]?.count || 0,
      },
      after: {
        syncEvents: afterEventsRows[0]?.count || 0,
        cloudChangeRequests: afterRequestsRows[0]?.count || 0,
        entitySnapshots: afterSnapshotsRows[0]?.count || 0,
        earliestSequence: Number(afterSequenceRows[0]?.earliest_sequence || 0),
        latestSequence: Number(afterSequenceRows[0]?.latest_sequence || 0),
      },
      skippedEventCleanup: removedEvents === 0 && safeFloorSequence <= 0 ? 'waiting_for_safe_floor_or_not_enough_acknowledged_devices' : '',
      serverTime: new Date().toISOString(),
    });
  } catch (error) {
    sendError(res, error);
  }
}
