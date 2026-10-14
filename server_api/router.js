import health from './health.js';
import deployHealth from './deploy-health.js';
import authRegister from './auth/register.js';
import authLogin from './auth/login.js';
import authSession from './auth/session.js';
import authLogout from './auth/logout.js';
import authPasswordReset from './auth/password-reset.js';
import accountChangePassword from './account/change-password.js';
import accountOwnerProfile from './account/owner-profile.js';
import adminSubscribers from './admin/subscribers.js';
import adminPasswordReset from './admin/password-reset.js';
import deviceRevoke from './sync/device-revoke.js';
import deviceWipeAck from './sync/device-wipe-ack.js';
import deviceSuspend from './sync/device-suspend.js';
import deviceAccess from './sync/device-access.js';
import deviceKey from './sync/device-key.js';
import iceConfig from './sync/ice-config.js';
import devices from './sync/devices.js';
import entitlement from './sync/entitlement.js';
import hostHeartbeat from './sync/host-heartbeat.js';
import pairingClaim from './sync/pairing/claim.js';
import pairingCreate from './sync/pairing/create.js';
import pairingStatus from './sync/pairing/status.js';
import recoveryClaim from './sync/recovery/claim.js';
import signal from './sync/signal.js';
import { directRealtimeTicketHandler, realtimeTicketHandler } from './sync/realtime.js';
import googleDriveAuthStart from './google-drive/auth-start.js';
import googleDriveCallback from './google-drive/callback.js';
import googleDriveStatus from './google-drive/status.js';
import googleDriveRefresh from './google-drive/refresh.js';

const routes = new Map([
  ['health', health],
  ['deploy-health', deployHealth],
  ['auth/register', authRegister],
  ['auth/login', authLogin],
  ['auth/session', authSession],
  ['auth/logout', authLogout],
  ['auth/password-reset', authPasswordReset],
  ['account/change-password', accountChangePassword],
  ['account/owner-profile', accountOwnerProfile],
  ['admin/subscribers', adminSubscribers],
  ['admin/password-reset', adminPasswordReset],
  ['sync/device-revoke', deviceRevoke],
  ['sync/device-wipe-ack', deviceWipeAck],
  ['sync/device-suspend', deviceSuspend],
  ['sync/device-access', deviceAccess],
  ['sync/device-key', deviceKey],
  ['sync/ice-config', iceConfig],
  ['sync/devices', devices],
  ['sync/entitlement', entitlement],
  ['sync/host-heartbeat', hostHeartbeat],
  ['sync/pairing/claim', pairingClaim],
  ['sync/pairing/create', pairingCreate],
  ['sync/pairing/status', pairingStatus],
  ['sync/recovery/claim', recoveryClaim],
  ['sync/signal', signal],
  ['sync/realtime-ticket', realtimeTicketHandler],
  ['sync/direct-ticket', directRealtimeTicketHandler],
  ['google-drive/auth-start', googleDriveAuthStart],
  ['google-drive/callback', googleDriveCallback],
  ['google-drive/status', googleDriveStatus],
  ['google-drive/refresh', googleDriveRefresh],
]);

function normalizePath(req) {
  const queryPath = req.query?.path;
  if (Array.isArray(queryPath)) return queryPath.join('/').replace(/^\/+|\/+$/g, '');
  if (typeof queryPath === 'string' && queryPath.trim()) return queryPath.replace(/^\/+|\/+$/g, '');

  const rawUrl = req.url || '';
  const pathname = rawUrl.split('?')[0] || '';
  return pathname.replace(/^\/api\//, '').replace(/^\/+|\/+$/g, '');
}

function allowedOrigins() {
  const raw = (process.env.VENTIO_API_ALLOWED_ORIGINS || '').trim();
  if (!raw) return (process.env.NODE_ENV || '').toLowerCase() === 'production' ? [] : ['*'];
  return raw
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean);
}

function applyCors(req, res) {
  const origins = allowedOrigins();
  const origin = String(req.headers.origin || '').trim();
  const isProduction = (process.env.NODE_ENV || '').toLowerCase() === 'production';

  if (origins.includes('*')) {
    res.setHeader('Access-Control-Allow-Origin', '*');
  } else if (origin && origins.includes(origin)) {
    res.setHeader('Access-Control-Allow-Origin', origin);
    res.setHeader('Vary', 'Origin');
  } else if (origin && !isProduction) {
    res.setHeader('Access-Control-Allow-Origin', origin);
    res.setHeader('Vary', 'Origin');
  } else if (origin && isProduction) {
    return false;
  }

  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PATCH, PUT, DELETE, OPTIONS');
  res.setHeader(
    'Access-Control-Allow-Headers',
    'Content-Type, Accept, Authorization, X-Device-Id, X-Device-Token, X-Device-Role, X-Sync-Transport, X-Store-Id, X-Branch-Id',
  );
  return true;
}

export default async function handler(req, res) {
  if (!applyCors(req, res)) {
    return res.status(403).json({
      ok: false,
      error: 'Origin is not allowed.',
    });
  }

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
