import crypto from 'crypto';
import { WebSocketServer, WebSocket } from 'ws';
import { assertAccountOrDevice, assertStoreAllowed, sendError } from '../_db.js';

const clientsByScope = new Map();
const tickets = new Map();
const relayRequests = new Map();
const ticketTtlMs = 60000;
const relayRequestTtlMs = 30000;

function scopeKey(storeId, branchId) {
  return `${storeId}::${branchId || 'main'}`;
}

function requestKey(storeId, branchId, requestId) {
  return `${scopeKey(storeId, branchId)}::${requestId}`;
}

function oppositeRole(role) {
  return role === 'host' ? 'client' : 'host';
}

function addClient(client) {
  const key = scopeKey(client.storeId, client.branchId);
  const clients = clientsByScope.get(key) || new Set();
  clients.add(client);
  clientsByScope.set(key, clients);
}

function removeClient(client) {
  const key = scopeKey(client.storeId, client.branchId);
  const clients = clientsByScope.get(key);
  if (!clients) return;
  clients.delete(client);
  if (!clients.size) clientsByScope.delete(key);
}

function send(client, payload) {
  if (client.socket.readyState !== WebSocket.OPEN) return;
  client.socket.send(JSON.stringify({
    ...payload,
    storeId: client.storeId,
    branchId: client.branchId,
    serverTime: new Date().toISOString(),
  }));
}

function broadcast({ storeId, branchId, role, payload, excludeSocket = null }) {
  const clients = clientsByScope.get(scopeKey(storeId, branchId));
  if (!clients) return 0;
  let count = 0;
  for (const client of clients) {
    if (role && client.role !== role) continue;
    if (excludeSocket && client.socket === excludeSocket) continue;
    send(client, payload);
    count += 1;
  }
  return count;
}

function pruneTickets() {
  const now = Date.now();
  for (const [ticket, value] of tickets.entries()) {
    if (value.expiresAt <= now) tickets.delete(ticket);
  }
}

function pruneRelayRequests() {
  const now = Date.now();
  for (const [key, value] of relayRequests.entries()) {
    if (value.expiresAt <= now) relayRequests.delete(key);
  }
}

function removeRelayRequestsForClient(client) {
  for (const [key, value] of relayRequests.entries()) {
    if (value.source === client) {
      relayRequests.delete(key);
    }
  }
}

function decodePacket(raw) {
  try {
    const decoded = JSON.parse(raw.toString());
    if (decoded && typeof decoded === 'object' && !Array.isArray(decoded)) {
      return decoded;
    }
  } catch (_) {
    return null;
  }
  return null;
}

function forwardRelayRequest(client, packet) {
  const requestId = String(packet.requestId || packet.request_id || '').trim();
  if (!requestId) return;
  const targetRole = String(
    packet.targetRole || packet.target_role || oppositeRole(client.role),
  ).trim().toLowerCase() || oppositeRole(client.role);
  const key = requestKey(client.storeId, client.branchId, requestId);
  relayRequests.set(key, {
    source: client,
    requestId,
    targetRole,
    expiresAt: Date.now() + relayRequestTtlMs,
  });

  const delivered = broadcast({
    storeId: client.storeId,
    branchId: client.branchId,
    role: targetRole,
    payload: {
      ...packet,
      type: 'relay_request',
      requestId,
      targetRole,
      sourceDeviceId: client.deviceId || '',
      sourceRole: client.role,
    },
    excludeSocket: client.socket,
  });

  if (!delivered) {
    relayRequests.delete(key);
    send(client, {
      type: 'relay_response',
      requestId,
      ok: false,
      error: `No ${targetRole} peer is connected for this store.`,
    });
  }
}

function forwardRelayResponse(client, packet) {
  const requestId = String(packet.requestId || packet.request_id || '').trim();
  if (!requestId) return;
  pruneRelayRequests();
  const key = requestKey(client.storeId, client.branchId, requestId);
  const pending = relayRequests.get(key);
  if (!pending) return;
  relayRequests.delete(key);
  send(pending.source, {
    ...packet,
    type: 'relay_response',
    requestId,
    sourceDeviceId: client.deviceId || '',
    sourceRole: client.role,
  });
}

function forwardSignal(client, packet) {
  const targetRole = String(
    packet.targetRole || packet.target_role || oppositeRole(client.role),
  ).trim().toLowerCase() || oppositeRole(client.role);
  broadcast({
    storeId: client.storeId,
    branchId: client.branchId,
    role: targetRole,
    payload: {
      ...packet,
      sourceDeviceId: client.deviceId || '',
      sourceRole: client.role,
    },
    excludeSocket: client.socket,
  });
}

export async function realtimeTicketHandler(req, res) {
  try {
    if (req.method !== 'GET') return res.status(405).json({ ok: false, error: 'Method not allowed' });
    pruneTickets();
    const storeId = String(req.query.store_id || req.query.storeId || '').trim();
    const branchId = String(req.query.branch_id || req.query.branchId || 'main').trim() || 'main';
    const role = String(req.query.role || req.headers['x-device-role'] || '').trim().toLowerCase();
    const deviceId = String(req.headers['x-device-id'] || req.query.device_id || req.query.deviceId || '').trim();
    if (!storeId || (role !== 'host' && role !== 'client')) {
      return res.status(400).json({ ok: false, error: 'Invalid realtime ticket request.' });
    }
    assertStoreAllowed(storeId);
    await assertAccountOrDevice(req, {
      storeId,
      branchId,
      allowedRoles: role === 'host' ? ['host'] : ['client'],
      allowedTransports: ['cloud'],
    });
    const ticket = crypto.randomUUID();
    tickets.set(ticket, {
      storeId,
      branchId,
      role,
      deviceId,
      expiresAt: Date.now() + ticketTtlMs,
    });
    res.status(200).json({
      ok: true,
      ticket,
      expiresInSeconds: Math.floor(ticketTtlMs / 1000),
      serverTime: new Date().toISOString(),
    });
  } catch (error) {
    sendError(res, error);
  }
}

export function notifySyncChanged({ storeId, branchId = 'main', latestSequence = 0 }) {
  if (!storeId) return 0;
  return broadcast({
    storeId,
    branchId,
    role: 'client',
    payload: {
      type: 'sync_changed',
      changed: true,
      latestSequence: Number(latestSequence || 0),
    },
  });
}

export function notifyHostRequests({ storeId, branchId = 'main', pendingRequests = 1 }) {
  if (!storeId) return 0;
  return broadcast({
    storeId,
    branchId,
    role: 'host',
    payload: {
      type: 'host_requests',
      changed: true,
      pendingRequests: Number(pendingRequests || 0),
    },
  });
}

export function attachRealtimeServer(server) {
  const wss = new WebSocketServer({ noServer: true });

  server.on('upgrade', async (request, socket, head) => {
    const url = new URL(request.url || '/', 'http://localhost');
    if (url.pathname !== '/api/sync/realtime') return;

    try {
      pruneTickets();
      const ticket = String(url.searchParams.get('ticket') || '').trim();
      const ticketData = tickets.get(ticket);
      if (!ticketData || ticketData.expiresAt <= Date.now()) {
        throw new Error('Invalid realtime subscription.');
      }
      tickets.delete(ticket);
      const { storeId, branchId, role } = ticketData;
      assertStoreAllowed(storeId);

      wss.handleUpgrade(request, socket, head, (ws) => {
        const client = {
          socket: ws,
          storeId,
          branchId,
          role,
          deviceId: ticketData.deviceId || '',
          alive: true,
        };
        addClient(client);
        send(client, { type: 'realtime_welcome', changed: false });
        ws.on('message', (raw) => {
          const packet = decodePacket(raw);
          if (!packet) return;
          pruneRelayRequests();
          const type = String(packet.type || '').trim();
          if (!type) return;
          if (type === 'relay_request') {
            forwardRelayRequest(client, packet);
            return;
          }
          if (type === 'relay_response') {
            forwardRelayResponse(client, packet);
            return;
          }
          if (type === 'sync_changed' ||
              type === 'host_requests' ||
              type === 'realtime_signal') {
            forwardSignal(client, packet);
          }
        });
        ws.on('pong', () => {
          client.alive = true;
        });
        ws.on('close', () => {
          removeClient(client);
          removeRelayRequestsForClient(client);
        });
        ws.on('error', () => {
          removeClient(client);
          removeRelayRequestsForClient(client);
        });
      });
    } catch (error) {
      socket.write('HTTP/1.1 401 Unauthorized\r\nConnection: close\r\n\r\n');
      socket.destroy();
    }
  });

  const heartbeat = setInterval(() => {
    pruneRelayRequests();
    for (const clients of clientsByScope.values()) {
      for (const client of clients) {
        if (client.socket.readyState !== WebSocket.OPEN) {
          removeClient(client);
          removeRelayRequestsForClient(client);
          continue;
        }
        if (!client.alive) {
          client.socket.terminate();
          removeClient(client);
          removeRelayRequestsForClient(client);
          continue;
        }
        client.alive = false;
        client.socket.ping();
      }
    }
  }, 30000);

  server.on('close', () => clearInterval(heartbeat));
}
