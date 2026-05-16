import health from '../server_api/health.js';
import deviceRevoke from '../server_api/sync/device-revoke.js';
import devices from '../server_api/sync/devices.js';
import hostHeartbeat from '../server_api/sync/host-heartbeat.js';
import hostTransferActivate from '../server_api/sync/host-transfer/activate.js';
import hostTransferApprove from '../server_api/sync/host-transfer/approve.js';
import hostTransferList from '../server_api/sync/host-transfer/list.js';
import hostTransferRequest from '../server_api/sync/host-transfer/request.js';
import pairingClaim from '../server_api/sync/pairing/claim.js';
import pairingCreate from '../server_api/sync/pairing/create.js';
import pull from '../server_api/sync/pull.js';
import push from '../server_api/sync/push.js';
import recoveryClaim from '../server_api/sync/recovery/claim.js';
import requestsAck from '../server_api/sync/requests/ack.js';
import requestsPull from '../server_api/sync/requests/pull.js';
import requestsPush from '../server_api/sync/requests/push.js';

const routes = new Map([
  ['health', health],
  ['sync/device-revoke', deviceRevoke],
  ['sync/devices', devices],
  ['sync/host-heartbeat', hostHeartbeat],
  ['sync/host-transfer/activate', hostTransferActivate],
  ['sync/host-transfer/approve', hostTransferApprove],
  ['sync/host-transfer/list', hostTransferList],
  ['sync/host-transfer/request', hostTransferRequest],
  ['sync/pairing/claim', pairingClaim],
  ['sync/pairing/create', pairingCreate],
  ['sync/pull', pull],
  ['sync/push', push],
  ['sync/recovery/claim', recoveryClaim],
  ['sync/requests/ack', requestsAck],
  ['sync/requests/pull', requestsPull],
  ['sync/requests/push', requestsPush],
]);

function normalizePath(req) {
  const queryPath = req.query?.path;
  if (Array.isArray(queryPath)) return queryPath.join('/').replace(/^\/+|\/+$/g, '');
  if (typeof queryPath === 'string' && queryPath.trim()) return queryPath.replace(/^\/+|\/+$/g, '');

  const rawUrl = req.url || '';
  const pathname = rawUrl.split('?')[0] || '';
  return pathname.replace(/^\/api\//, '').replace(/^\/+|\/+$/g, '');
}

export default async function handler(req, res) {
  const path = normalizePath(req);
  const route = routes.get(path);
  if (!route) {
    return res.status(404).json({
      ok: false,
      error: 'API route not found.',
      path,
    });
  }
  return route(req, res);
}
