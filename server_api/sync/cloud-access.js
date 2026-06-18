import { ensureCloudSyncAccessColumn, sendError, sql } from '../_db.js';

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
