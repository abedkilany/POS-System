import { assertAccountOrDevice, assertStoreAllowed, sendError } from '../_db.js';

export default async function handler(req, res) {
  try {
    if (req.method !== 'GET') {
      return res.status(405).json({ ok: false, error: 'Method not allowed' });
    }

    const storeId = String(
      req.query.store_id || req.query.storeId || req.headers['x-store-id'] || '',
    ).trim();
    const branchId = String(
      req.query.branch_id || req.query.branchId || req.headers['x-branch-id'] || 'main',
    ).trim() || 'main';

    if (!storeId) {
      return res.status(400).json({ ok: false, error: 'storeId is required.' });
    }

    assertStoreAllowed(storeId);
    await assertAccountOrDevice(req, {
      storeId,
      branchId,
      allowedRoles: ['host', 'client'],
      allowedTransports: ['cloud'],
    });

    return res.status(200).json({
      ok: true,
      changed: false,
      serverTime: new Date().toISOString(),
      message: 'Signal gateway is available.',
    });
  } catch (error) {
    sendError(res, error);
  }
}
