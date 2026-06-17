import { assertStoreAllowed, assertAccountOrDevice, sendError } from '../../_db.js';
import { sql } from '../../_db.js';
import { ensureHostTransferTables, transferDto } from './_shared.js';

export default async function handler(req, res) {
  try {
    if (req.method !== 'GET') return res.status(405).json({ ok: false, error: 'Method not allowed' });
    await ensureHostTransferTables();
    const storeId = String(req.query.store_id || req.query.storeId || '').trim();
    const branchId = String(req.query.branch_id || req.query.branchId || 'main').trim() || 'main';
    if (!storeId) return res.status(400).json({ ok: false, error: 'store_id is required.' });
    assertStoreAllowed(storeId);
    await assertAccountOrDevice(req, { storeId, branchId, allowedRoles: ['host', 'client'], allowedTransports: ['cloud', 'lan'] });
    const rows = await sql`
      select * from host_transfer_requests
      where store_id = ${storeId} and branch_id = ${branchId}
      order by updated_at desc
      limit 50
    `;
    res.status(200).json({ ok: true, requests: rows.map(transferDto), serverTime: new Date().toISOString() });
  } catch (error) { sendError(res, error); }
}
