import { assertAccountOrDevice, assertAccountStoreToken, ensureCloudSyncAccessColumn, sendError, sql } from '../_db.js';

export default async function handler(req, res) {
  try {
    if (req.method !== 'GET') {
      res.setHeader('Allow', 'GET, OPTIONS');
      return res.status(405).json({ ok: false, error: 'Method not allowed.' });
    }

    await ensureCloudSyncAccessColumn();
    const storeId = String(req.headers['x-store-id'] || req.headers['X-Store-Id'] || req.query?.storeId || '').trim();
    const branchId = String(req.headers['x-branch-id'] || req.headers['X-Branch-Id'] || req.query?.branchId || 'main').trim() || 'main';
    if (!storeId) {
      return res.status(400).json({ ok: false, error: 'Missing store id.' });
    }

    // This endpoint is a read-only entitlement check. Prefer the online account
    // session when available because a local Host may still be localOnly before
    // Cloud Sync is enabled and therefore may not have a cloud transport/device
    // record yet. We validate the account against the store only; branch is not
    // relevant for a store-level subscription flag. If there is no valid account
    // token, fall back to the same device credentials used by sync/pull and
    // sync/push.
    try {
      assertAccountStoreToken(req, { storeId });
    } catch (_) {
      await assertAccountOrDevice(req, {
        storeId,
        branchId,
        allowedRoles: ['host', 'client'],
        allowAccount: false,
      });
    }

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
