import { sql, assertAccountOrDevice, assertStoreAllowed, sendError } from '../_db.js';

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function latestAuthoritativeSequence(storeId, branchId) {
  const rows = await sql`
    select coalesce(max(sequence), 0)::bigint as sequence
    from sync_events
    where store_id = ${storeId}
      and branch_id = ${branchId}
  `;
  return Number(rows[0]?.sequence || 0);
}

async function pendingHostRequests(storeId, branchId) {
  const rows = await sql`
    select count(*)::int as pending,
           coalesce(max(received_at), 'epoch'::timestamptz) as latest_received
    from cloud_change_requests
    where store_id = ${storeId}
      and branch_id = ${branchId}
      and status = 'pending'
  `;
  return {
    pending: Number(rows[0]?.pending || 0),
    latestReceivedAt: rows[0]?.latest_received
      ? new Date(rows[0].latest_received).toISOString()
      : '',
  };
}

export default async function handler(req, res) {
  try {
    if (req.method !== 'GET') return res.status(405).json({ ok: false, error: 'Method not allowed' });
    const storeId = String(req.query.store_id || req.query.storeId || req.headers['x-store-id'] || '').trim();
    const branchId = String(req.query.branch_id || req.query.branchId || req.headers['x-branch-id'] || 'main').trim() || 'main';
    const role = String(req.query.role || req.headers['x-device-role'] || '').trim().toLowerCase();
    const sinceSequence = Number.parseInt(String(req.query.since_sequence || req.query.sinceSequence || '0'), 10) || 0;
    const waitSeconds = Math.max(1, Math.min(25, Number.parseInt(String(req.query.wait_seconds || req.query.waitSeconds || '25'), 10) || 25));
    if (!storeId) return res.status(400).json({ ok: false, error: 'storeId is required.' });
    assertStoreAllowed(storeId);
    await assertAccountOrDevice(req, {
      storeId,
      branchId,
      allowedRoles: role === 'host' ? ['host'] : ['client'],
      allowedTransports: ['cloud'],
    });

    const deadline = Date.now() + waitSeconds * 1000;
    while (true) {
      if (role === 'host') {
        const requestState = await pendingHostRequests(storeId, branchId);
        if (requestState.pending > 0 || Date.now() >= deadline) {
          return res.status(200).json({
            ok: true,
            changed: requestState.pending > 0,
            pendingRequests: requestState.pending,
            latestReceivedAt: requestState.latestReceivedAt,
            serverTime: new Date().toISOString(),
          });
        }
      } else {
        const latestSequence = await latestAuthoritativeSequence(storeId, branchId);
        if (latestSequence > sinceSequence || Date.now() >= deadline) {
          return res.status(200).json({
            ok: true,
            changed: latestSequence > sinceSequence,
            latestSequence,
            serverTime: new Date().toISOString(),
          });
        }
      }
      await sleep(1000);
    }
  } catch (error) {
    sendError(res, error);
  }
}
