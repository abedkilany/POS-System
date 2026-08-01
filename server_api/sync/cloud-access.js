import {
  assertAccountOrDevice,
  assertStoreAllowed,
  ensureCloudSyncAccessColumn,
  sendError,
  sql,
} from '../_db.js';

export default async function handler(req, res) {
  try {
    if (req.method !== 'GET') {
      res.setHeader('Allow', 'GET, OPTIONS');
      return res.status(405).json({ ok: false, error: 'Method not allowed.' });
    }

    const storeId = String(req.headers['x-store-id'] || req.headers['X-Store-Id'] || req.query?.storeId || '').trim();
    const branchId = String(req.headers['x-branch-id'] || req.headers['X-Branch-Id'] || req.query?.branchId || 'main').trim() || 'main';
    if (!storeId) {
      return res.status(400).json({ ok: false, error: 'Missing store id.' });
    }

    assertStoreAllowed(storeId);
    // This endpoint exposes store entitlement state, so it must not be a
    // public store-id probe. Account sessions authorize Hosts; paired devices
    // authorize both Hosts and Clients through their device token. Do not pass
    // `cloud` as an allowed transport here: a disabled Cloud plan should be
    // reported as `{ allowed: false }`, not rejected before the query runs.
    await assertAccountOrDevice(req, {
      storeId,
      branchId,
      allowedRoles: ['host', 'client'],
    });

    await ensureCloudSyncAccessColumn();

    const rows = await sql`
      select cloud_sync_enabled
      from app_stores
      where id = ${storeId}
      limit 1
    `;
    const allowed = rows.length > 0 && rows[0].cloud_sync_enabled === true;
    return res.status(200).json({
      ok: true,
      cloudSyncEnabled: allowed,
      allowed,
    });
  } catch (error) {
    return sendError(res, error);
  }
}
