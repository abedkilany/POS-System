import {
  sql,
  assertSyncToken,
  assertAccountStoreToken,
  assertCloudSyncEnabled,
  sendError,
} from './_db.js';

export default async function handler(req, res) {
  try {
    try {
      assertSyncToken(req);
    } catch (_) {
      const storeId = String(req.headers['x-store-id'] || req.headers['X-Store-Id'] || '').trim();
      const branchId = String(req.headers['x-branch-id'] || req.headers['X-Branch-Id'] || '').trim();
      assertAccountStoreToken(req, { storeId, branchId });
      if (storeId) await assertCloudSyncEnabled(storeId);
    }
    const rows = await sql`select now() as now`;
    res.status(200).json({ ok: true, service: 'pos-sync-api', databaseTime: rows[0].now });
  } catch (error) {
    sendError(res, error);
  }
}
