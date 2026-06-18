export const config = {
  api: {
    bodyParser: {
      sizeLimit: '25mb',
    },
  },
};

import health from '../server_api/health.js';
import deployHealth from '../server_api/deploy-health.js';
import authRegister from '../server_api/auth/register.js';
import authLogin from '../server_api/auth/login.js';
import authSession from '../server_api/auth/session.js';
import adminSubscribers from '../server_api/admin/subscribers.js';
import deviceRevoke from '../server_api/sync/device-revoke.js';
import deviceWipeAck from '../server_api/sync/device-wipe-ack.js';
import deviceSuspend from '../server_api/sync/device-suspend.js';
import deviceAccess from '../server_api/sync/device-access.js';
import cloudAccess from '../server_api/sync/cloud-access.js';
import devices from '../server_api/sync/devices.js';
import hostHeartbeat from '../server_api/sync/host-heartbeat.js';
import hostTransferActivate from '../server_api/sync/host-transfer/activate.js';
import hostTransferApprove from '../server_api/sync/host-transfer/approve.js';
import hostTransferList from '../server_api/sync/host-transfer/list.js';
import hostTransferRequest from '../server_api/sync/host-transfer/request.js';
import pairingClaim from '../server_api/sync/pairing/claim.js';
import pairingCreate from '../server_api/sync/pairing/create.js';
import pairingStatus from '../server_api/sync/pairing/status.js';
import pull from '../server_api/sync/pull.js';
import push from '../server_api/sync/push.js';
import signal from '../server_api/sync/signal.js';
import { realtimeTicketHandler } from '../server_api/sync/realtime.js';
import recoveryClaim from '../server_api/sync/recovery/claim.js';
import requestsAck from '../server_api/sync/requests/ack.js';
import requestsPull from '../server_api/sync/requests/pull.js';
import requestsStatus from '../server_api/sync/requests/status.js';
import requestsPush from '../server_api/sync/requests/push.js';
import maintenance from '../server_api/sync/maintenance.js';
import bootstrapSnapshot from '../server_api/sync/bootstrap-snapshot.js';
import googleDriveAuthStart from '../server_api/google-drive/auth-start.js';
import googleDriveCallback from '../server_api/google-drive/callback.js';
import googleDriveStatus from '../server_api/google-drive/status.js';
import googleDriveRefresh from '../server_api/google-drive/refresh.js';

const routes = new Map([
  ['health', health],
  ['deploy-health', deployHealth],
  ['auth/register', authRegister],
  ['auth/login', authLogin],
  ['auth/session', authSession],
  ['admin/subscribers', adminSubscribers],
  ['sync/device-revoke', deviceRevoke],
  ['sync/device-wipe-ack', deviceWipeAck],
  ['sync/device-suspend', deviceSuspend],
  ['sync/device-access', deviceAccess],
  ['sync/cloud-access', cloudAccess],
  ['sync/devices', devices],
  ['sync/host-heartbeat', hostHeartbeat],
  ['sync/host-transfer/activate', hostTransferActivate],
  ['sync/host-transfer/approve', hostTransferApprove],
  ['sync/host-transfer/list', hostTransferList],
  ['sync/host-transfer/request', hostTransferRequest],
  ['sync/pairing/claim', pairingClaim],
  ['sync/pairing/create', pairingCreate],
  ['sync/pairing/status', pairingStatus],
  ['sync/pull', pull],
  ['sync/push', push],
  ['sync/signal', signal],
  ['sync/realtime-ticket', realtimeTicketHandler],
  ['sync/maintenance', maintenance],
  ['sync/bootstrap-snapshot', bootstrapSnapshot],
  ['google-drive/auth-start', googleDriveAuthStart],
  ['google-drive/callback', googleDriveCallback],
  ['google-drive/status', googleDriveStatus],
  ['google-drive/refresh', googleDriveRefresh],
  ['sync/recovery/claim', recoveryClaim],
  ['sync/requests/ack', requestsAck],
  ['sync/requests/pull', requestsPull],
  ['sync/requests/status', requestsStatus],
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
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PATCH, PUT, DELETE, OPTIONS');
  res.setHeader(
    'Access-Control-Allow-Headers',
    'Content-Type, Accept, Authorization, X-Device-Id, X-Device-Token, X-Device-Role, X-Sync-Transport, X-Store-Id, X-Branch-Id',
  );

  if (req.method === 'OPTIONS') {
    return res.status(204).end();
  }

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
