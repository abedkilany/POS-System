import {
  getDirectSyncEnabled,
  sendError,
} from '../_db.js';

/**
 * Read the subscription entitlement without requiring Direct to be the
 * device's current transport. A local Host must be able to ask whether it is
 * allowed to enable Direct; requiring the Direct transport here creates a
 * circular lock.
 */
export default async function handler(req, res) {
  try {
    if (req.method !== 'GET') {
      res.setHeader('Allow', 'GET, OPTIONS');
      return res.status(405).json({ ok: false, error: 'Method not allowed.' });
    }

    const storeId = String(req.query?.store_id || req.query?.storeId || '').trim();
    const branchId = String(req.query?.branch_id || req.query?.branchId || 'main').trim() || 'main';
    if (!storeId) {
      return res.status(400).json({ ok: false, error: 'store_id is required.' });
    }
    // This endpoint only exposes the subscription feature flag. It does not
    // expose store data or authorize any sync operation. The actual sync
    // endpoints continue to require account/device authentication and call
    // assertDirectSyncEnabled before accepting Direct traffic. Keeping this
    // read separate avoids a circular dependency where a local device cannot
    // learn whether it may enable Direct because it is not Direct yet.

    return res.status(200).json({
      ok: true,
      storeId,
      branchId,
      directSyncEnabled: await getDirectSyncEnabled(storeId),
    });
  } catch (error) {
    return sendError(res, error);
  }
}
