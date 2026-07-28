import crypto from 'crypto';
import { WebSocketServer, WebSocket } from 'ws';
import { assertAccountOrDevice, assertStoreAllowed, sendError } from '../_db.js';

const clientsByScope = new Map();
const tickets = new Map();
const ticketTtlMs = 60000;

function scopeKey(storeId, branchId) {
  return `${storeId}::${branchId || 'main'}`;
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
  // Relay requests are always peer-to-peer across the Host/Client boundary.
  // Do not let a connected device select an arbitrary role or use the relay
  // as a same-role broadcast channel.
  const targetRole = oppositeRole(client.role);
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
  const sourceDeviceId = String(
    packet.sourceDeviceId || packet.source_device_id || '',
  ).trim();
  const clients = clientsByScope.get(scopeKey(client.storeId, client.branchId));
  if (!clients) return;
  for (const item of clients) {
    if (item.deviceId !== sourceDeviceId) continue;
    send(item, {
      ...packet,
      type: 'relay_response',
      requestId,
      sourceDeviceId: client.deviceId || '',
      sourceRole: client.role,
    });
    return;
  }
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
  // Payloads are streamed through memory only. Keep a bounded frame size so
  // an oversized relay message cannot consume unbounded server memory.
  const wss = new WebSocketServer({
    noServer: true,
    maxPayload: 25 * 1024 * 1024,
  });

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
          // The server intentionally does not persist or inspect business
          // payloads. It only routes the already-authenticated frame to the
          // opposite peer in the same store/branch scope.
          const packet = decodePacket(raw);
          if (!packet) return;
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
        });
        ws.on('error', () => {
          removeClient(client);
        });
      });
    } catch (error) {
      socket.write('HTTP/1.1 401 Unauthorized\r\nConnection: close\r\n\r\n');
      socket.destroy();
    }
  });

  const heartbeat = setInterval(() => {
    for (const clients of clientsByScope.values()) {
      for (const client of clients) {
        if (client.socket.readyState !== WebSocket.OPEN) {
          removeClient(client);
          continue;
        }
        if (!client.alive) {
          client.socket.terminate();
          removeClient(client);
          continue;
        }
        client.alive = false;
        client.socket.ping();
      }
    }
  }, 30000);

  server.on('close', () => clearInterval(heartbeat));
}
