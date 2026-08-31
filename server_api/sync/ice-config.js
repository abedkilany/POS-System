import crypto from 'crypto';
import { assertAccountOrDevice, assertStoreAllowed, sendError } from '../_db.js';

function urls() {
  return String(process.env.TURN_SERVER_URLS || '')
    .split(/[\s,;]+/)
    .map((value) => value.trim())
    .filter(Boolean);
}

export default async function handler(req, res) {
  try {
    if (req.method !== 'GET') return res.status(405).json({ ok: false, error: 'Method not allowed' });
    const storeId = String(req.query?.store_id || '').trim();
    const branchId = String(req.query?.branch_id || 'main').trim() || 'main';
    if (!storeId) return res.status(400).json({ ok: false, error: 'store_id is required.' });
    assertStoreAllowed(storeId);
    await assertAccountOrDevice(req, { storeId, branchId, allowedRoles: ['host', 'client'] });
    const configuredUrls = urls();
    if (!configuredUrls.length) return res.status(200).json({ ok: true, servers: [], expiresAt: '' });
    const secret = String(process.env.TURN_SHARED_SECRET || '').trim();
    if (!secret) return res.status(503).json({ ok: false, error: 'TURN is not configured.' });
    const expiresAt = Math.floor(Date.now() / 1000) + 3600;
    const deviceId = String(req.headers['x-device-id'] || 'ventio').trim();
    const username = `${expiresAt}:${deviceId}`;
    const credential = crypto.createHmac('sha1', secret).update(username).digest('base64');
    return res.status(200).json({
      ok: true,
      servers: [{
        urls: configuredUrls,
        username,
        credential,
      }],
      expiresAt: new Date(expiresAt * 1000).toISOString(),
    });
  } catch (error) {
    sendError(res, error);
  }
}
