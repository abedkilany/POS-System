import { sql, assertSyncTokenOrDevice, assertStoreAllowed, ensureDeviceAuthColumns, sendError } from '../_db.js';

function asIso(value) {
  return value instanceof Date ? value.toISOString() : new Date(value).toISOString();
}

function safeIso(value) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return null;
  return date.toISOString();
}

function encodeCursor(value) {
  return Buffer.from(JSON.stringify(value), 'utf8').toString('base64url');
}

function decodeCursor(value) {
  if (!value) return null;
  try {
    return JSON.parse(Buffer.from(String(value), 'base64url').toString('utf8'));
  } catch (_) {
    return null;
  }
}

async function markDevicePullSeen(req, { storeId, branchId }) {
  const deviceId = String(req.headers['x-device-id'] || req.headers['X-Device-Id'] || req.query.device_id || req.query.deviceId || '').trim();
  if (!deviceId || !storeId) return;

  // A Pull means the Host sent data, not that the Client applied it.
  // Keep only presence/transport metadata here. lastApplied*/lastAck* are
  // updated exclusively by the Client ACK/heartbeat after local apply succeeds.
  await sql`
    update store_devices
    set active_transport = case when coalesce(active_transport, '') = '' then 'cloud' else active_transport end,
        last_sync_transport = 'cloud',
        online = true,
        last_seen_at = now(),
        updated_at = now()
    where store_id = ${storeId}
      and branch_id = ${branchId}
      and device_id = ${deviceId}
  `;
}

export default async function handler(req, res) {
  try {
    await sql`alter table sync_events add column if not exists store_epoch integer not null default 1`;
    await sql`alter table sync_events add column if not exists sequence integer not null default 0`;
    await ensureDeviceAuthColumns();
    if (req.method !== 'GET') return res.status(405).json({ ok: false, error: 'Method not allowed' });

    const storeId = String(req.query.store_id || req.query.storeId || 'default-store');
    const branchId = String(req.query.branch_id || req.query.branchId || 'main');
    assertStoreAllowed(storeId);
    await assertSyncTokenOrDevice(req, { storeId, branchId, allowedRoles: ['host', 'client'], allowedTransports: ['cloud'] });
    const since = req.query.since ? safeIso(String(req.query.since)) : null;
    const sinceSequence = Math.max(Number(req.query.since_sequence || req.query.sinceSequence || 0), 0);
    const limit = Math.min(Math.max(Number(req.query.limit || 1000), 1), 5000);
    const cursor = decodeCursor(req.query.cursor);
    const minSnapshotUpdatedAt = req.query.min_snapshot_updated_at ? safeIso(String(req.query.min_snapshot_updated_at)) : null;
    const bootstrapMode = String(req.query.bootstrap || req.query.bootstrap_mode || '').trim().toLowerCase();
    const loginBootstrapOnly = bootstrapMode === 'login';

    // First-time/new-device pull: return the latest materialized state in
    // stable pages. The cursor also carries a high-water mark so events created
    // during a multi-page snapshot are not skipped after the snapshot finishes.
    if (!since && sinceSequence <= 0) {
      const watermark = cursor?.watermark || new Date().toISOString();
      const cursorUpdatedAt = cursor?.updatedAt ? safeIso(cursor.updatedAt) : null;
      const cursorEntityType = cursor?.entityType || '';
      const cursorEntityId = cursor?.entityId || '';
      const snapshotRows = cursorUpdatedAt
        ? await sql`
            select store_id, branch_id, entity_type, entity_id, operation, payload, updated_at
            from entity_snapshots
            where store_id = ${storeId}
              and branch_id = ${branchId}
              and operation <> 'delete'
              and entity_type <> 'stock_movement'
              and (${loginBootstrapOnly} = false or entity_type in ('store_profile', 'role', 'user'))
              and (${minSnapshotUpdatedAt}::timestamptz is null or updated_at >= ${minSnapshotUpdatedAt})
              and (
                updated_at > ${cursorUpdatedAt}
                or (updated_at = ${cursorUpdatedAt} and entity_type > ${cursorEntityType})
                or (updated_at = ${cursorUpdatedAt} and entity_type = ${cursorEntityType} and entity_id > ${cursorEntityId})
              )
            order by updated_at asc, entity_type asc, entity_id asc
            limit ${limit + 1}
          `
        : await sql`
            select store_id, branch_id, entity_type, entity_id, operation, payload, updated_at
            from entity_snapshots
            where store_id = ${storeId}
              and branch_id = ${branchId}
              and operation <> 'delete'
              and entity_type <> 'stock_movement'
              and (${loginBootstrapOnly} = false or entity_type in ('store_profile', 'role', 'user'))
              and (${minSnapshotUpdatedAt}::timestamptz is null or updated_at >= ${minSnapshotUpdatedAt})
            order by updated_at asc, entity_type asc, entity_id asc
            limit ${limit + 1}
          `;
      const pageRows = snapshotRows.slice(0, limit);
      const hasMore = snapshotRows.length > limit;
      const last = pageRows[pageRows.length - 1];
      const sequenceRows = await sql`
        select coalesce(max(sequence), 0) as max_sequence
        from sync_events
        where store_id = ${storeId}
          and branch_id = ${branchId}
          and received_at <= ${watermark}::timestamptz
      `;
      const watermarkSequence = Number(sequenceRows[0]?.max_sequence || 0);
      const changes = pageRows.map((row) => ({
        id: `snapshot-${row.entity_type}-${row.entity_id}-${asIso(row.updated_at)}`,
        storeId: row.store_id,
        branchId: row.branch_id || branchId,
        deviceId: 'cloud-snapshot',
        entityType: row.entity_type,
        entityId: row.entity_id,
        operation: 'upsert',
        payload: row.payload || {},
        createdAt: asIso(row.updated_at),
        isSynced: true,
        syncedAt: new Date().toISOString(),
        storeEpoch: 1,
        sequence: 0,
      }));
      await markDevicePullSeen(req, { storeId, branchId });
      return res.status(200).json({
        ok: true,
        changes,
        hasMore,
        nextCursor: hasMore && last ? encodeCursor({ mode: 'snapshot', watermark, updatedAt: asIso(last.updated_at), entityType: last.entity_type, entityId: last.entity_id }) : null,
        generatedAt: hasMore ? null : watermark,
        generatedSequence: hasMore ? null : watermarkSequence,
        source: 'entity_snapshots',
      });
    }

    if (sinceSequence > 0) {
      const sequenceWindowRows = await sql`
        select coalesce(min(nullif(sequence, 0)), 0) as earliest_sequence,
               coalesce(max(sequence), 0) as latest_sequence
        from sync_events
        where store_id = ${storeId}
          and branch_id = ${branchId}
      `;
      const earliestSequence = Number(sequenceWindowRows[0]?.earliest_sequence || 0);
      const latestSequence = Number(sequenceWindowRows[0]?.latest_sequence || 0);
      if (earliestSequence > 0 && sinceSequence < earliestSequence - 1) {
        await markDevicePullSeen(req, { storeId, branchId });
        return res.status(200).json({
          ok: true,
          changes: [],
          hasMore: false,
          nextCursor: null,
          needsSnapshot: true,
          earliestSequence,
          latestSequence,
          generatedAt: new Date().toISOString(),
          generatedSequence: latestSequence,
          source: 'sync_events_compacted',
        });
      }
    }

    const cursorReceivedAt = cursor?.receivedAt ? safeIso(cursor.receivedAt) : null;
    const cursorCreatedAt = cursor?.createdAt ? safeIso(cursor.createdAt) : null;
    const cursorId = cursor?.id || '';
    const rows = cursorReceivedAt && cursorCreatedAt
      ? await sql`
          select id, store_id, branch_id, device_id, entity_type, entity_id, operation, payload, created_at, received_at, store_epoch, sequence
          from sync_events
          where store_id = ${storeId}
            and branch_id = ${branchId}
            and (case when ${sinceSequence} > 0 then sequence > ${sinceSequence} else received_at > ${since} end)
            and (
              received_at > ${cursorReceivedAt}
              or (received_at = ${cursorReceivedAt} and created_at > ${cursorCreatedAt})
              or (received_at = ${cursorReceivedAt} and created_at = ${cursorCreatedAt} and id > ${cursorId})
            )
          order by received_at asc, created_at asc, id asc
          limit ${limit + 1}
        `
      : await sql`
          select id, store_id, branch_id, device_id, entity_type, entity_id, operation, payload, created_at, received_at, store_epoch, sequence
          from sync_events
          where store_id = ${storeId}
            and branch_id = ${branchId}
            and (case when ${sinceSequence} > 0 then sequence > ${sinceSequence} else received_at > ${since} end)
          order by received_at asc, created_at asc, id asc
          limit ${limit + 1}
        `;

    const pageRows = rows.slice(0, limit);
    const hasMore = rows.length > limit;
    const last = pageRows[pageRows.length - 1];
    const changes = pageRows.map((row) => ({
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
      storeEpoch: row.store_epoch || 1,
      sequence: row.sequence || 0,
    }));

    const maxReceivedAt = pageRows.length ? asIso(pageRows[pageRows.length - 1].received_at) : since;
    const maxSequence = pageRows.length ? Math.max(...pageRows.map((row) => Number(row.sequence || 0))) : sinceSequence;
    await markDevicePullSeen(req, { storeId, branchId });
    res.status(200).json({
      ok: true,
      changes,
      hasMore,
      nextCursor: hasMore && last ? encodeCursor({ mode: 'events', receivedAt: asIso(last.received_at), createdAt: asIso(last.created_at), id: last.id }) : null,
      generatedAt: hasMore ? null : (maxReceivedAt || new Date().toISOString()),
      generatedSequence: hasMore ? null : maxSequence,
      source: 'sync_events',
    });
  } catch (error) {
    sendError(res, error);
  }
}
