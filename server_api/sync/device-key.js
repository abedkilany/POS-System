import { sql, assertAccountOrDevice, assertStoreAllowed, sendError } from '../_db.js';

async function ensureDeviceKeyColumn() {
  await sql`alter table store_devices add column if not exists device_public_key text default ''`;
}

function cleanKey(value) {
  return String(value || '').trim();
}

export default async function handler(req, res) {
  try {
    const body = req.body || {};
    const storeId = String(body.storeId || body.store_id || req.query.store_id || '').trim();
    const branchId = String(body.branchId || body.branch_id || req.query.branch_id || 'main').trim() || 'main';
    if (!storeId) return res.status(400).json({ ok: false, error: 'storeId is required.' });
    assertStoreAllowed(storeId);
    await ensureDeviceKeyColumn();

    if (req.method === 'POST') {
      const deviceId = String(body.deviceId || body.device_id || req.headers['x-device-id'] || '').trim();
      const publicKey = cleanKey(body.publicKey || body.public_key);
      if (!deviceId || !publicKey) {
        return res.status(400).json({ ok: false, error: 'deviceId and publicKey are required.' });
      }
      if (publicKey.length > 512) {
        return res.status(400).json({ ok: false, error: 'publicKey is too large.' });
      }
      await assertAccountOrDevice(req, {
        storeId,
        branchId,
        allowedRoles: ['host', 'client'],
        allowedTransports: [],
      });
      const headerDeviceId = String(req.headers['x-device-id'] || req.headers['X-Device-Id'] || '').trim();
      if (headerDeviceId && headerDeviceId !== deviceId) {
        return res.status(403).json({ ok: false, error: 'Device credentials cannot update another device.' });
      }
      await sql`
        update store_devices
        set device_public_key = ${publicKey}, updated_at = now()
        where store_id = ${storeId} and branch_id = ${branchId} and device_id = ${deviceId}
      `;
      return res.status(200).json({ ok: true, storeId, branchId, deviceId, publicKey });
    }

    if (req.method === 'GET') {
      const targetDeviceId = String(
        req.query.device_id || req.query.deviceId || req.query.target_device_id || req.query.targetDeviceId || '',
      ).trim();
      if (!targetDeviceId) return res.status(400).json({ ok: false, error: 'targetDeviceId is required.' });
      await assertAccountOrDevice(req, {
        storeId,
        branchId,
        allowedRoles: ['host', 'client'],
        allowedTransports: [],
      });
      const callerDeviceId = String(req.headers['x-device-id'] || req.headers['X-Device-Id'] || '').trim();
      const callerRows = await sql`
        select role, host_device_id
        from store_devices
        where store_id = ${storeId} and branch_id = ${branchId} and device_id = ${callerDeviceId}
        limit 1
      `;
      const rows = await sql`
        select device_id, role, host_device_id, device_public_key
        from store_devices
        where store_id = ${storeId} and branch_id = ${branchId} and device_id = ${targetDeviceId}
        limit 1
      `;
      if (!rows.length) return res.status(404).json({ ok: false, error: 'Device was not found.' });
      const row = rows[0];
      const caller = callerRows[0];
      const isRelated = callerDeviceId === targetDeviceId ||
        caller?.role === 'host' ||
        row.host_device_id === callerDeviceId ||
        caller?.host_device_id === targetDeviceId;
      if (!isRelated) {
        return res.status(403).json({ ok: false, error: 'Peer key is not available to this device.' });
      }
      return res.status(200).json({
        ok: true,
        storeId,
        branchId,
        deviceId: row.device_id,
        publicKey: row.device_public_key || '',
      });
    }

    return res.status(405).json({ ok: false, error: 'Method not allowed' });
  } catch (error) {
    sendError(res, error);
  }
}
