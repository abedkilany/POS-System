import http from 'node:http';
import { DatabaseSync } from 'node:sqlite';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
loadDotEnv(path.join(__dirname, '.env'));

const PORT = Number(process.env.PORT || 3000);
const DB_PATH = path.resolve(__dirname, process.env.DB_PATH || './data/marketplace.db');
const SYNC_TOKEN = process.env.CLOUD_SYNC_TOKEN || 'change-this-token';
const AUTH_SECRET = process.env.AUTH_SESSION_SECRET || SYNC_TOKEN || 'dev-secret-change-me';
const STORE_TOKEN_SECRET = process.env.STORE_TOKEN_SECRET || AUTH_SECRET;
const ALLOWED_ORIGINS = String(process.env.ALLOWED_ORIGINS || '*').split(',').map((s) => s.trim()).filter(Boolean);

fs.mkdirSync(path.dirname(DB_PATH), { recursive: true });
const db = new DatabaseSync(DB_PATH);
db.exec('PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON;');
initSchema();
// No demo store is seeded here. The Marketplace should show only stores
// explicitly published by real store devices.

const server = http.createServer(async (req, res) => {
  try {
    applyCors(req, res);
    if (req.method === 'OPTIONS') return send(res, 204, null);

    const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
    let pathname = normalizePath(url.pathname);
    // Compatibility: Flutter/Vercel code calls /api/*, while the local server
    // exposes the same handlers without the /api prefix.
    if (pathname === '/api') pathname = '/';
    if (pathname.startsWith('/api/')) pathname = pathname.slice(4) || '/';

    if (req.method === 'GET' && pathname === '/health') {
      return send(res, 200, { ok: true, service: 'local-marketplace-server', database: DB_PATH, now: new Date().toISOString() });
    }

    if (pathname.startsWith('/auth/')) return handleAuth(req, res, pathname);
    if (pathname.startsWith('/store/')) return handleStore(req, res, pathname);
    if (pathname.startsWith('/sync/')) return handleSync(req, res, pathname, url);
    if (pathname.startsWith('/marketplace/')) return handleMarketplace(req, res, pathname, url);

    return send(res, 404, { ok: false, error: 'Not found' });
  } catch (error) {
    return send(res, Number(error.statusCode || 500), { ok: false, error: error.message || String(error) });
  }
});

server.listen(PORT, () => {
  console.log(`Local Marketplace Server running on http://localhost:${PORT}`);
  console.log(`SQLite database: ${DB_PATH}`);
});

function loadDotEnv(file) {
  if (!fs.existsSync(file)) return;
  const lines = fs.readFileSync(file, 'utf8').split(/\r?\n/);
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#') || !trimmed.includes('=')) continue;
    const [key, ...rest] = trimmed.split('=');
    if (!process.env[key]) process.env[key] = rest.join('=').trim();
  }
}

function normalizePath(value) {
  const p = String(value || '/').replace(/\/+/g, '/');
  return p.endsWith('/') && p.length > 1 ? p.slice(0, -1) : p;
}

function applyCors(req, res) {
  const origin = req.headers.origin || '*';
  const allowOrigin = ALLOWED_ORIGINS.includes('*') ? '*' : (ALLOWED_ORIGINS.includes(origin) ? origin : ALLOWED_ORIGINS[0] || '*');
  res.setHeader('Access-Control-Allow-Origin', allowOrigin);
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PUT,DELETE,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Sync-Token, X-Store-Id');
  res.setHeader('Access-Control-Max-Age', '86400');
}

function send(res, status, body) {
  res.statusCode = status;
  if (body === null) return res.end();
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  return res.end(JSON.stringify(body));
}

async function readBody(req) {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  if (!chunks.length) return {};
  const raw = Buffer.concat(chunks).toString('utf8');
  if (!raw.trim()) return {};
  try { return JSON.parse(raw); } catch { throw httpError(400, 'Invalid JSON body'); }
}

function httpError(statusCode, message) {
  const err = new Error(message);
  err.statusCode = statusCode;
  return err;
}

function maybeAssertSyncToken(req) {
  if (!SYNC_TOKEN || SYNC_TOKEN === 'change-this-token') return;
  const provided = req.headers['x-sync-token'] || req.headers.authorization?.replace(/^Bearer\s+/i, '');
  if (provided !== SYNC_TOKEN) throw httpError(401, 'Invalid sync token.');
}

function initSchema() {
  db.exec(`
    CREATE TABLE IF NOT EXISTS sync_events (
      id TEXT PRIMARY KEY,
      store_id TEXT NOT NULL,
      branch_id TEXT DEFAULT 'main',
      device_id TEXT DEFAULT '',
      entity_type TEXT NOT NULL,
      entity_id TEXT NOT NULL,
      operation TEXT NOT NULL,
      payload TEXT NOT NULL DEFAULT '{}',
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      received_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE INDEX IF NOT EXISTS idx_sync_events_store_received ON sync_events (store_id, branch_id, received_at);
    CREATE INDEX IF NOT EXISTS idx_sync_events_entity ON sync_events (store_id, entity_type, entity_id);

    CREATE TABLE IF NOT EXISTS entity_snapshots (
      store_id TEXT NOT NULL,
      branch_id TEXT NOT NULL DEFAULT 'main',
      entity_type TEXT NOT NULL,
      entity_id TEXT NOT NULL,
      payload TEXT NOT NULL DEFAULT '{}',
      operation TEXT NOT NULL DEFAULT 'upsert',
      updated_at TEXT NOT NULL DEFAULT (datetime('now')),
      PRIMARY KEY (store_id, branch_id, entity_type, entity_id)
    );

    CREATE TABLE IF NOT EXISTS cloud_change_requests (
      id TEXT PRIMARY KEY,
      store_id TEXT NOT NULL,
      branch_id TEXT DEFAULT 'main',
      device_id TEXT DEFAULT '',
      entity_type TEXT NOT NULL,
      entity_id TEXT NOT NULL,
      operation TEXT NOT NULL,
      payload TEXT NOT NULL DEFAULT '{}',
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      received_at TEXT NOT NULL DEFAULT (datetime('now')),
      status TEXT NOT NULL DEFAULT 'pending',
      accepted_at TEXT,
      host_device_id TEXT DEFAULT '',
      last_error TEXT DEFAULT ''
    );
    CREATE INDEX IF NOT EXISTS idx_cloud_change_requests_pending ON cloud_change_requests (store_id, branch_id, status, received_at);

    CREATE TABLE IF NOT EXISTS store_host_heartbeats (
      store_id TEXT NOT NULL,
      branch_id TEXT NOT NULL DEFAULT 'main',
      host_device_id TEXT NOT NULL,
      host_device_name TEXT DEFAULT '',
      platform TEXT DEFAULT '',
      app_version TEXT DEFAULT '',
      sync_mode TEXT DEFAULT '',
      last_seen_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now')),
      PRIMARY KEY (store_id, branch_id, host_device_id)
    );

    CREATE TABLE IF NOT EXISTS app_users (
      id TEXT PRIMARY KEY,
      full_name TEXT NOT NULL,
      username TEXT UNIQUE NOT NULL,
      password_hash TEXT NOT NULL,
      account_type TEXT NOT NULL DEFAULT 'customer',
      role_id TEXT NOT NULL DEFAULT 'customer',
      phone TEXT DEFAULT '',
      email TEXT DEFAULT '',
      primary_store_id TEXT DEFAULT '',
      is_active INTEGER DEFAULT 1,
      is_system INTEGER DEFAULT 0,
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now')),
      last_login_at TEXT
    );
    CREATE UNIQUE INDEX IF NOT EXISTS idx_app_users_username_unique ON app_users (lower(username));

    CREATE TABLE IF NOT EXISTS platform_stores (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      owner_user_id TEXT DEFAULT '',
      phone TEXT DEFAULT '',
      address TEXT DEFAULT '',
      description TEXT DEFAULT '',
      is_online_enabled INTEGER DEFAULT 1,
      subscription_plan TEXT DEFAULT 'trial',
      subscription_status TEXT DEFAULT 'pending_review',
      commission_rate REAL DEFAULT 0,
      is_active INTEGER DEFAULT 1,
      store_token_hash TEXT DEFAULT '',
      token_rotated_at TEXT,
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS store_members (
      id TEXT PRIMARY KEY,
      store_id TEXT NOT NULL,
      user_id TEXT NOT NULL,
      role TEXT NOT NULL DEFAULT 'owner',
      permissions TEXT DEFAULT '[]',
      is_active INTEGER DEFAULT 1,
      store_token_hash TEXT DEFAULT '',
      token_rotated_at TEXT,
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now')),
      UNIQUE(store_id, user_id)
    );

    CREATE TABLE IF NOT EXISTS customer_profiles (
      user_id TEXT PRIMARY KEY,
      default_address TEXT DEFAULT '',
      phone TEXT DEFAULT '',
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS driver_profiles (
      user_id TEXT PRIMARY KEY,
      phone TEXT DEFAULT '',
      zone TEXT DEFAULT '',
      is_available INTEGER DEFAULT 0,
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS marketplace_products (
      id TEXT NOT NULL,
      store_id TEXT NOT NULL,
      branch_id TEXT DEFAULT 'main',
      name TEXT NOT NULL,
      code TEXT DEFAULT '',
      category TEXT DEFAULT 'General',
      price REAL DEFAULT 0,
      stock INTEGER DEFAULT 0,
      payload TEXT DEFAULT '{}',
      is_active INTEGER DEFAULT 1,
      is_available_online INTEGER DEFAULT 1,
      updated_at TEXT DEFAULT (datetime('now')),
      PRIMARY KEY (store_id, branch_id, id)
    );
    CREATE INDEX IF NOT EXISTS idx_marketplace_products_store ON marketplace_products (store_id, branch_id, is_active, is_available_online);

    CREATE TABLE IF NOT EXISTS online_orders (
      id TEXT PRIMARY KEY,
      store_id TEXT NOT NULL,
      customer_user_id TEXT DEFAULT '',
      customer_name TEXT DEFAULT '',
      customer_phone TEXT DEFAULT '',
      delivery_address TEXT DEFAULT '',
      notes TEXT DEFAULT '',
      status TEXT DEFAULT 'placed',
      items TEXT DEFAULT '[]',
      delivery_fee REAL DEFAULT 0,
      discount REAL DEFAULT 0,
      payment_method TEXT DEFAULT 'cash_on_delivery',
      payment_status TEXT DEFAULT 'unpaid',
      assigned_driver_user_id TEXT DEFAULT '',
      is_deleted INTEGER DEFAULT 0,
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now'))
    );
  `);
}


function normalizeUsername(value) { return String(value || '').trim().toLowerCase(); }
function roleForAccountType(type) {
  if (type === 'customer') return 'customer';
  if (type === 'driver') return 'driver';
  if (type === 'merchant') return 'store_owner';
  if (type === 'app_admin') return 'platform_admin';
  return 'platform_user';
}
function randomId(prefix) { return `${prefix}_${Date.now()}_${Math.floor(Math.random() * 999999).toString().padStart(6, '0')}`; }
function hashPassword(password) {
  const salt = crypto.randomBytes(12).toString('base64url');
  return hashPasswordWithSalt(password, salt);
}
function hashPasswordWithSalt(password, salt) {
  let digest = Buffer.from(`store_manager_pro|local_pin_v2|${salt}|${String(password || '').trim()}`, 'utf8');
  for (let i = 0; i < 12000; i += 1) digest = crypto.createHash('sha256').update(digest).digest();
  return `sha256salt:${salt}:${digest.toString('base64url')}`;
}
function verifyPassword(password, storedHash) {
  const parts = String(storedHash || '').split(':');
  return parts.length === 3 && parts[0] === 'sha256salt' && hashPasswordWithSalt(password, parts[1]) === storedHash;
}
function issueSessionToken(userId) {
  const body = `${userId}.${Date.now()}.${crypto.randomBytes(12).toString('base64url')}`;
  const sig = crypto.createHmac('sha256', AUTH_SECRET).update(body).digest('base64url');
  return `${body}.${sig}`;
}
function issueStoreToken() { return `st_${crypto.randomBytes(24).toString('base64url')}`; }
function hashStoreToken(token) { return crypto.createHmac('sha256', STORE_TOKEN_SECRET).update(String(token || '').trim()).digest('base64url'); }
function parseJson(value, fallback) { try { return value ? JSON.parse(value) : fallback; } catch { return fallback; } }
function bool(v) { return v === true || v === 1 || v === '1'; }
function runTransaction(fn) {
  db.exec('BEGIN IMMEDIATE');
  try {
    const result = fn();
    db.exec('COMMIT');
    return result;
  } catch (error) {
    try { db.exec('ROLLBACK'); } catch (_) {}
    throw error;
  }
}
function publicUser(row) {
  if (!row) return null;
  return { id: row.id, fullName: row.full_name, username: row.username, passwordHash: row.password_hash, roleId: row.role_id, accountType: row.account_type, phone: row.phone || '', email: row.email || '', primaryStoreId: row.primary_store_id || '', extraPermissions: [], deniedPermissions: [], isActive: bool(row.is_active), isSystem: bool(row.is_system), createdAt: row.created_at, updatedAt: row.updated_at, lastLoginAt: row.last_login_at || null };
}
function toPlatformStore(row) { return row && { id: row.id, name: row.name, ownerUserId: row.owner_user_id || '', phone: row.phone || '', address: row.address || '', description: row.description || '', isOnlineEnabled: bool(row.is_online_enabled), subscriptionPlan: row.subscription_plan || 'trial', subscriptionStatus: row.subscription_status || 'pending_review', commissionRate: Number(row.commission_rate || 0), isActive: bool(row.is_active), createdAt: row.created_at, updatedAt: row.updated_at }; }
function toStoreMember(row) { return row && { id: row.id, storeId: row.store_id, userId: row.user_id, role: row.role, permissions: parseJson(row.permissions, []), isActive: bool(row.is_active), createdAt: row.created_at, updatedAt: row.updated_at }; }
function toCustomerProfile(row) { return row && { userId: row.user_id, defaultAddress: row.default_address || '', phone: row.phone || '', createdAt: row.created_at, updatedAt: row.updated_at }; }
function toDriverProfile(row) { return row && { userId: row.user_id, phone: row.phone || '', zone: row.zone || '', isAvailable: bool(row.is_available), createdAt: row.created_at, updatedAt: row.updated_at }; }

async function handleAuth(req, res, pathname) {
  const body = await readBody(req);
  if (req.method !== 'POST') return send(res, 405, { ok: false, error: 'Method not allowed.' });
  if (pathname === '/auth/register') return authRegister(res, body);
  if (pathname === '/auth/login') return authLogin(res, body);
  return send(res, 404, { ok: false, error: 'Auth endpoint not found.' });
}
function authRegister(res, body) {
  const fullName = String(body.fullName || '').trim();
  const username = normalizeUsername(body.username);
  const password = String(body.password || '').trim();
  const accountType = String(body.accountType || 'customer').trim() || 'customer';
  const phone = String(body.phone || '').trim();
  const email = String(body.email || '').trim();
  if (!fullName || !username) return send(res, 400, { ok: false, error: 'Name and username are required.' });
  if (password.length < 4) return send(res, 400, { ok: false, error: 'Password must be at least 4 characters.' });
  if (!['customer', 'platform_user'].includes(accountType)) return send(res, 400, { ok: false, error: 'This account type cannot self-register.' });
  const existing = db.prepare('SELECT id FROM app_users WHERE lower(username) = lower(?) LIMIT 1').get(username);
  if (existing) return send(res, 409, { ok: false, error: 'Username already exists.' });
  const now = new Date().toISOString();
  const userId = randomId('user');
  const roleId = roleForAccountType(accountType);
  db.prepare(`INSERT INTO app_users (id, full_name, username, password_hash, account_type, role_id, phone, email, primary_store_id, is_active, is_system, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, '', 1, 0, ?, ?)`).run(userId, fullName, username, hashPassword(password), accountType, roleId, phone, email, now, now);
  if (accountType === 'customer') db.prepare(`INSERT INTO customer_profiles (user_id, default_address, phone, created_at, updated_at) VALUES (?, '', ?, ?, ?)`).run(userId, phone, now, now);
  const user = db.prepare('SELECT * FROM app_users WHERE id = ?').get(userId);
  const customerProfile = db.prepare('SELECT * FROM customer_profiles WHERE user_id = ?').get(userId);
  return send(res, 200, { ok: true, message: 'Account created locally.', user: publicUser(user), sessionToken: issueSessionToken(userId), platformStore: null, storeMember: null, customerProfile: toCustomerProfile(customerProfile), driverProfile: null });
}
function authLogin(res, body) {
  const username = normalizeUsername(body.username);
  const password = String(body.password || '').trim();
  if (!username || !password) return send(res, 400, { ok: false, error: 'Username and password are required.' });
  const user = db.prepare('SELECT * FROM app_users WHERE lower(username) = lower(?) AND is_active = 1 LIMIT 1').get(username);
  if (!user || !verifyPassword(password, user.password_hash)) return send(res, 401, { ok: false, error: 'Invalid username or password.' });
  const now = new Date().toISOString();
  db.prepare('UPDATE app_users SET last_login_at = ?, updated_at = ? WHERE id = ?').run(now, now, user.id);
  const fresh = db.prepare('SELECT * FROM app_users WHERE id = ?').get(user.id);
  const platformStore = fresh.primary_store_id ? toPlatformStore(db.prepare('SELECT * FROM platform_stores WHERE id = ? LIMIT 1').get(fresh.primary_store_id)) : null;
  const storeMember = fresh.primary_store_id ? toStoreMember(db.prepare('SELECT * FROM store_members WHERE store_id = ? AND user_id = ? LIMIT 1').get(fresh.primary_store_id, fresh.id)) : null;
  const customerProfile = toCustomerProfile(db.prepare('SELECT * FROM customer_profiles WHERE user_id = ? LIMIT 1').get(fresh.id));
  const driverProfile = toDriverProfile(db.prepare('SELECT * FROM driver_profiles WHERE user_id = ? LIMIT 1').get(fresh.id));
  return send(res, 200, { ok: true, message: 'Logged in locally.', user: publicUser(fresh), sessionToken: issueSessionToken(fresh.id), platformStore, storeMember, customerProfile, driverProfile });
}

async function handleStore(req, res, pathname) {
  const body = await readBody(req);
  if (req.method !== 'POST') return send(res, 405, { ok: false, error: 'Method not allowed.' });
  if (pathname === '/store/create') return storeCreate(res, body);
  if (pathname === '/store/link') return storeLink(res, body);
  return send(res, 404, { ok: false, error: 'Store endpoint not found.' });
}
function storeCreate(res, body) {
  const userId = String(body.userId || '').trim();
  const storeName = String(body.storeName || '').trim();
  const phone = String(body.phone || '').trim();
  const address = String(body.address || '').trim();
  if (!userId) return send(res, 400, { ok: false, error: 'User is required.' });
  if (!storeName) return send(res, 400, { ok: false, error: 'Store name is required.' });
  const user = db.prepare('SELECT * FROM app_users WHERE id = ? AND is_active = 1 LIMIT 1').get(userId);
  if (!user) return send(res, 404, { ok: false, error: 'Platform account not found.' });
  const now = new Date().toISOString();
  const storeId = randomId('store');
  const token = issueStoreToken();
  db.prepare(`INSERT INTO platform_stores (id, name, owner_user_id, phone, address, subscription_plan, subscription_status, is_online_enabled, is_active, store_token_hash, token_rotated_at, created_at, updated_at) VALUES (?, ?, ?, ?, ?, 'trial', 'pending_review', 1, 1, ?, ?, ?, ?)`).run(storeId, storeName, userId, phone, address, hashStoreToken(token), now, now, now);
  const memberId = randomId('member');
  db.prepare(`INSERT INTO store_members (id, store_id, user_id, role, permissions, is_active, created_at, updated_at) VALUES (?, ?, ?, 'owner', '[]', 1, ?, ?)`).run(memberId, storeId, userId, now, now);
  db.prepare(`UPDATE app_users SET account_type = 'merchant', role_id = 'store_owner', primary_store_id = ?, updated_at = ? WHERE id = ?`).run(storeId, now, userId);
  return send(res, 200, { ok: true, message: 'Store created locally.', user: publicUser(db.prepare('SELECT * FROM app_users WHERE id = ?').get(userId)), sessionToken: issueSessionToken(userId), platformStore: toPlatformStore(db.prepare('SELECT * FROM platform_stores WHERE id = ?').get(storeId)), storeMember: toStoreMember(db.prepare('SELECT * FROM store_members WHERE id = ?').get(memberId)), storeToken: token });
}
function storeLink(res, body) {
  const userId = String(body.userId || '').trim();
  const storeId = String(body.storeId || '').trim();
  const storeToken = String(body.storeToken || '').trim();
  if (!userId || !storeId || !storeToken) return send(res, 400, { ok: false, error: 'User, Store ID and Store Token are required.' });
  const user = db.prepare('SELECT * FROM app_users WHERE id = ? AND is_active = 1 LIMIT 1').get(userId);
  if (!user) return send(res, 404, { ok: false, error: 'Platform account not found.' });
  const store = db.prepare('SELECT * FROM platform_stores WHERE id = ? AND is_active = 1 LIMIT 1').get(storeId);
  if (!store) return send(res, 404, { ok: false, error: 'Store not found.' });
  if (!store.store_token_hash || store.store_token_hash !== hashStoreToken(storeToken)) return send(res, 403, { ok: false, error: 'Invalid Store ID or Store Token.' });
  const now = new Date().toISOString();
  let member = db.prepare('SELECT * FROM store_members WHERE store_id = ? AND user_id = ? LIMIT 1').get(storeId, userId);
  if (member) db.prepare('UPDATE store_members SET is_active = 1, updated_at = ? WHERE id = ?').run(now, member.id);
  else {
    const id = randomId('member');
    db.prepare(`INSERT INTO store_members (id, store_id, user_id, role, permissions, is_active, created_at, updated_at) VALUES (?, ?, ?, 'manager', '[]', 1, ?, ?)`).run(id, storeId, userId, now, now);
    member = db.prepare('SELECT * FROM store_members WHERE id = ?').get(id);
  }
  db.prepare(`UPDATE app_users SET account_type = 'merchant', role_id = 'store_owner', primary_store_id = ?, updated_at = ? WHERE id = ?`).run(storeId, now, userId);
  return send(res, 200, { ok: true, message: 'Store linked successfully.', user: publicUser(db.prepare('SELECT * FROM app_users WHERE id = ?').get(userId)), sessionToken: issueSessionToken(userId), platformStore: toPlatformStore(store), storeMember: toStoreMember(member) });
}

async function handleSync(req, res, pathname, url) {
  maybeAssertSyncToken(req);
  if (pathname === '/sync/push' && req.method === 'POST') return syncPush(res, await readBody(req));
  if (pathname === '/sync/pull' && req.method === 'GET') return syncPull(res, url);
  if (pathname === '/sync/requests/push' && req.method === 'POST') return requestPush(res, await readBody(req));
  if (pathname === '/sync/requests/pull' && req.method === 'GET') return requestPull(res, url);
  if (pathname === '/sync/requests/ack' && req.method === 'POST') return requestAck(res, await readBody(req));
  if (pathname === '/sync/host-heartbeat' && req.method === 'POST') return hostHeartbeat(res, await readBody(req));
  return send(res, 404, { ok: false, error: 'Sync endpoint not found.' });
}
function normalizeChange(raw, fallback = {}) {
  if (!raw || typeof raw !== 'object') throw httpError(400, 'Invalid sync change.');
  const id = String(raw.id || '').trim();
  const entityType = String(raw.entityType || raw.entity_type || '').trim();
  const entityId = String(raw.entityId || raw.entity_id || '').trim();
  const operation = String(raw.operation || '').trim();
  if (!id || !entityType || !entityId || !operation) throw httpError(400, 'Sync change is missing required fields.');
  return { id, storeId: String(raw.storeId || raw.store_id || fallback.storeId || 'default-store'), branchId: String(raw.branchId || raw.branch_id || fallback.branchId || 'main'), deviceId: String(raw.deviceId || raw.device_id || fallback.deviceId || 'unknown-device'), entityType, entityId, operation, payload: raw.payload && typeof raw.payload === 'object' ? raw.payload : {}, createdAt: raw.createdAt ? new Date(raw.createdAt).toISOString() : new Date().toISOString() };
}
function syncPush(res, body) {
  const changes = Array.isArray(body.changes) ? body.changes : [];
  const fallback = { storeId: body.storeId, branchId: body.branchId, deviceId: body.deviceId };
  const ackIds = [];
  const insert = db.prepare(`INSERT OR IGNORE INTO sync_events (id, store_id, branch_id, device_id, entity_type, entity_id, operation, payload, created_at, received_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`);
  runTransaction(() => {
    for (const raw of changes) {
      const c = normalizeChange(raw, fallback);
      const receivedAt = new Date().toISOString();
      const before = db.prepare('SELECT id FROM sync_events WHERE id = ?').get(c.id);
      insert.run(c.id, c.storeId, c.branchId, c.deviceId, c.entityType, c.entityId, c.operation, JSON.stringify(c.payload || {}), c.createdAt, receivedAt);
      if (!before) materializeChange(c);
      ackIds.push(c.id);
    }
  });
  return send(res, 200, { ok: true, ackIds, serverTime: new Date().toISOString() });
}
function syncPull(res, url) {
  const storeId = String(url.searchParams.get('store_id') || url.searchParams.get('storeId') || 'default-store');
  const branchId = String(url.searchParams.get('branch_id') || url.searchParams.get('branchId') || 'main');
  const since = url.searchParams.get('since');
  const limit = Math.min(Number(url.searchParams.get('limit') || 1000), 5000);
  if (!since) {
    const rows = db.prepare(`SELECT * FROM entity_snapshots WHERE store_id = ? AND branch_id = ? AND operation <> 'delete' AND entity_type <> 'stock_movement' ORDER BY updated_at ASC LIMIT ?`).all(storeId, branchId, limit);
    const changes = rows.map((r) => ({ id: `snapshot-${r.entity_type}-${r.entity_id}-${r.updated_at}`, storeId: r.store_id, branchId: r.branch_id, deviceId: 'local-snapshot', entityType: r.entity_type, entityId: r.entity_id, operation: 'upsert', payload: parseJson(r.payload, {}), createdAt: r.updated_at, isSynced: true, syncedAt: new Date().toISOString() }));
    return send(res, 200, { ok: true, changes, generatedAt: new Date().toISOString(), source: 'entity_snapshots' });
  }
  const rows = db.prepare(`SELECT * FROM sync_events WHERE store_id = ? AND branch_id = ? AND received_at > ? ORDER BY received_at ASC, created_at ASC LIMIT ?`).all(storeId, branchId, since, limit);
  const changes = rows.map((r) => ({ id: r.id, storeId: r.store_id, branchId: r.branch_id, deviceId: r.device_id, entityType: r.entity_type, entityId: r.entity_id, operation: r.operation, payload: parseJson(r.payload, {}), createdAt: r.created_at, isSynced: true, syncedAt: new Date().toISOString() }));
  const generatedAt = rows.length ? rows[rows.length - 1].received_at : since;
  return send(res, 200, { ok: true, changes, generatedAt, source: 'sync_events' });
}
function upsertSnapshot({ storeId, branchId = 'main', entityType, entityId, operation = 'upsert', payload = {}, updatedAt }) {
  db.prepare(`INSERT INTO entity_snapshots (store_id, branch_id, entity_type, entity_id, payload, operation, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT(store_id, branch_id, entity_type, entity_id) DO UPDATE SET payload = excluded.payload, operation = excluded.operation, updated_at = excluded.updated_at`).run(storeId, branchId, entityType, entityId, JSON.stringify(payload || {}), operation, updatedAt || new Date().toISOString());
}
function materializeChange(change) {
  const updatedAt = change.createdAt || new Date().toISOString();
  if (change.operation === 'reset_store_data') {
    db.prepare('DELETE FROM entity_snapshots WHERE store_id = ? AND branch_id = ?').run(change.storeId, change.branchId || 'main');
    return;
  }
  if (change.entityType === 'system' && change.operation === 'restore_snapshot') {
    const collections = { products: 'product', customers: 'customer', sales: 'sale', suppliers: 'supplier', expenses: 'expense', categories: 'category', brands: 'brand', units: 'unit', roles: 'role', users: 'user', platformStores: 'platform_store', onlineOrders: 'online_order', storeMembers: 'store_member', customerProfiles: 'customer_profile', driverProfiles: 'driver_profile' };
    for (const [key, entityType] of Object.entries(collections)) {
      const list = Array.isArray(change.payload?.[key]) ? change.payload[key] : [];
      list.forEach((item, i) => upsertSnapshot({ storeId: change.storeId, branchId: change.branchId, entityType, entityId: String(item?.id || `${key}-${i}`), operation: 'upsert', payload: item, updatedAt }));
    }
    if (change.payload?.storeProfile) upsertSnapshot({ storeId: change.storeId, branchId: change.branchId, entityType: 'store_profile', entityId: 'store', operation: 'upsert', payload: change.payload.storeProfile, updatedAt });
    return;
  }
  if (change.entityType === 'stock_movement') {
    const p = change.payload || {};
    const productId = String(p.productId || p.product_id || '').trim();
    const quantity = Number(p.quantity || 0);
    if (productId && Number.isFinite(quantity) && quantity !== 0) {
      const row = db.prepare(`SELECT * FROM entity_snapshots WHERE store_id = ? AND branch_id = ? AND entity_type = 'product' AND entity_id = ? LIMIT 1`).get(change.storeId, change.branchId || 'main', productId);
      if (row && row.operation !== 'delete') {
        const product = parseJson(row.payload, {});
        upsertSnapshot({ storeId: change.storeId, branchId: change.branchId, entityType: 'product', entityId: productId, operation: 'upsert', payload: { ...product, stock: Number(product.stock || 0) + quantity, updatedAt, syncStatus: 'synced', storeId: change.storeId, branchId: change.branchId || product.branchId || 'main' }, updatedAt });
      }
    }
  }
  upsertSnapshot({ storeId: change.storeId, branchId: change.branchId, entityType: change.entityType, entityId: change.entityId, operation: change.operation === 'delete' ? 'delete' : 'upsert', payload: change.payload, updatedAt });
}
function requestPush(res, body) {
  const changes = Array.isArray(body.changes) ? body.changes : [];
  const fallback = { storeId: body.storeId, branchId: body.branchId, deviceId: body.deviceId };
  const ids = [];
  const stmt = db.prepare(`INSERT OR IGNORE INTO cloud_change_requests (id, store_id, branch_id, device_id, entity_type, entity_id, operation, payload, created_at, received_at, status) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending')`);
  runTransaction(() => {
    for (const raw of changes) {
      const c = normalizeChange(raw, fallback);
      stmt.run(c.id, c.storeId, c.branchId, c.deviceId, c.entityType, c.entityId, c.operation, JSON.stringify(c.payload || {}), c.createdAt, new Date().toISOString());
      ids.push(c.id);
    }
  });
  return send(res, 200, { ok: true, ackIds: ids, serverTime: new Date().toISOString() });
}
function requestPull(res, url) {
  const storeId = String(url.searchParams.get('store_id') || url.searchParams.get('storeId') || 'default-store');
  const branchId = String(url.searchParams.get('branch_id') || url.searchParams.get('branchId') || 'main');
  const limit = Math.min(Number(url.searchParams.get('limit') || 1000), 5000);
  const rows = db.prepare(`SELECT * FROM cloud_change_requests WHERE store_id = ? AND branch_id = ? AND status = 'pending' ORDER BY received_at ASC, created_at ASC LIMIT ?`).all(storeId, branchId, limit);
  const changes = rows.map((r) => ({ id: r.id, storeId: r.store_id, branchId: r.branch_id, deviceId: r.device_id, entityType: r.entity_type, entityId: r.entity_id, operation: r.operation, payload: parseJson(r.payload, {}), createdAt: r.created_at, isSynced: false }));
  return send(res, 200, { ok: true, changes, serverTime: new Date().toISOString() });
}
function requestAck(res, body) {
  const ids = Array.isArray(body.ackIds) ? body.ackIds : Array.isArray(body.ids) ? body.ids : [];
  const hostDeviceId = String(body.hostDeviceId || body.host_device_id || '').trim();
  const now = new Date().toISOString();
  const stmt = db.prepare(`UPDATE cloud_change_requests SET status = 'accepted', accepted_at = ?, host_device_id = ? WHERE id = ?`);
  runTransaction(() => ids.forEach((id) => stmt.run(now, hostDeviceId, String(id))));
  return send(res, 200, { ok: true, ackIds: ids, serverTime: now });
}
function hostHeartbeat(res, body) {
  const storeId = String(body.storeId || body.store_id || 'default-store');
  const branchId = String(body.branchId || body.branch_id || 'main');
  const hostDeviceId = String(body.hostDeviceId || body.host_device_id || body.deviceId || 'host');
  const now = new Date().toISOString();
  db.prepare(`INSERT INTO store_host_heartbeats (store_id, branch_id, host_device_id, host_device_name, platform, app_version, sync_mode, last_seen_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(store_id, branch_id, host_device_id) DO UPDATE SET host_device_name = excluded.host_device_name, platform = excluded.platform, app_version = excluded.app_version, sync_mode = excluded.sync_mode, last_seen_at = excluded.last_seen_at, updated_at = excluded.updated_at`).run(storeId, branchId, hostDeviceId, String(body.hostDeviceName || body.host_device_name || ''), String(body.platform || ''), String(body.appVersion || body.app_version || ''), String(body.syncMode || body.sync_mode || ''), now, now);
  return send(res, 200, { ok: true, serverTime: now });
}

async function handleMarketplace(req, res, pathname, url) {
  if (req.method === 'POST' && pathname === '/marketplace/publish-store') {
    const body = await readBody(req);
    const storeId = String(body.storeId || '').trim();
    const branchId = String(body.branchId || 'main').trim() || 'main';
    const store = body.store && typeof body.store === 'object' ? body.store : {};
    const products = Array.isArray(body.products) ? body.products : [];
    if (!storeId) return send(res, 400, { ok: false, error: 'storeId is required.' });
    const now = new Date().toISOString();
    const storeName = String(store.name || body.storeName || 'Store').trim() || 'Store';
    db.prepare(`INSERT INTO platform_stores (id, name, owner_user_id, phone, address, description, is_online_enabled, subscription_plan, subscription_status, is_active, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, 1, 'local', 'active', 1, ?, ?) ON CONFLICT(id) DO UPDATE SET name = excluded.name, phone = excluded.phone, address = excluded.address, description = excluded.description, is_online_enabled = 1, is_active = 1, subscription_status = 'active', updated_at = excluded.updated_at`)
      .run(storeId, storeName, String(store.ownerUserId || ''), String(store.phone || ''), String(store.address || ''), String(store.description || ''), now, now);
    upsertSnapshot({ storeId, branchId, entityType: 'store_profile', entityId: 'store', operation: 'upsert', payload: { ...store, name: storeName, id: storeId, storeId, branchId, isMarketplacePublished: true, updatedAt: now }, updatedAt: now });

    const clear = db.prepare(`DELETE FROM marketplace_products WHERE store_id = ? AND branch_id = ?`);
    const insertProduct = db.prepare(`INSERT INTO marketplace_products (id, store_id, branch_id, name, code, category, price, stock, payload, is_active, is_available_online, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`);
    runTransaction(() => {
      clear.run(storeId, branchId);
      for (const raw of products) {
        if (!raw || typeof raw !== 'object') continue;
        const id = String(raw.id || '').trim();
        if (!id) continue;
        const product = { ...raw, storeId, branchId, isPublic: raw.isPublic !== false, isAvailableOnline: raw.isAvailableOnline !== false, updatedAt: raw.updatedAt || now };
        const active = product.isActive === false || product.deletedAt ? 0 : 1;
        const available = product.isAvailableOnline === false || product.isPublic === false ? 0 : 1;
        insertProduct.run(id, storeId, branchId, String(product.name || product.nameAr || product.nameEn || ''), String(product.code || ''), String(product.category || 'General'), Number(product.price || 0), Number(product.stock || 0), JSON.stringify(product), active, available, now);
        upsertSnapshot({ storeId, branchId, entityType: 'product', entityId: id, operation: active ? 'upsert' : 'delete', payload: product, updatedAt: now });
      }
    });
    return send(res, 200, { ok: true, storeId, branchId, publishedProducts: products.length, updatedAt: now });
  }
  if (req.method === 'GET' && pathname === '/marketplace/stores') {
    const stores = new Map();
    const rows = db.prepare(`SELECT * FROM platform_stores WHERE is_active = 1 AND is_online_enabled = 1 ORDER BY updated_at DESC`).all();
    for (const row of rows) stores.set(row.id, toPlatformStore(row));

    // Also expose stores that were published through sync snapshots from POS hosts.
    const snapshotRows = db.prepare(`SELECT * FROM entity_snapshots WHERE entity_type = 'store_profile' AND operation <> 'delete' ORDER BY updated_at DESC`).all();
    for (const row of snapshotRows) {
      if (stores.has(row.store_id)) continue;
      const payload = parseJson(row.payload, {});
      stores.set(row.store_id, {
        id: row.store_id,
        name: String(payload.name || payload.storeName || payload.title || `Store ${row.store_id}`),
        ownerUserId: String(payload.ownerUserId || ''),
        phone: String(payload.phone || payload.mobile || ''),
        address: String(payload.address || ''),
        description: String(payload.description || ''),
        isOnlineEnabled: true,
        subscriptionPlan: 'local',
        subscriptionStatus: 'active',
        commissionRate: 0,
        isActive: true,
        createdAt: payload.createdAt || row.updated_at,
        updatedAt: payload.updatedAt || row.updated_at,
      });
    }

    return send(res, 200, { ok: true, stores: Array.from(stores.values()) });
  }

  const productsMatch = pathname.match(/^\/marketplace\/stores\/([^/]+)\/products$/);
  if (req.method === 'GET' && productsMatch) {
    const storeId = decodeURIComponent(productsMatch[1]);
    const branchId = String(url.searchParams.get('branch_id') || url.searchParams.get('branchId') || 'main');
    const publishedRows = db.prepare(`SELECT * FROM marketplace_products WHERE store_id = ? AND branch_id = ? AND is_active = 1 AND is_available_online = 1 ORDER BY updated_at DESC`).all(storeId, branchId);
    let products = publishedRows.map((r) => ({ ...parseJson(r.payload, {}), id: r.id, storeId: r.store_id, branchId: r.branch_id }));
    if (!products.length) {
      const rows = db.prepare(`SELECT * FROM entity_snapshots WHERE store_id = ? AND branch_id = ? AND entity_type = 'product' AND operation <> 'delete' ORDER BY updated_at DESC`).all(storeId, branchId);
      products = rows
        .map((r) => ({ ...parseJson(r.payload, {}), id: r.entity_id, storeId: r.store_id, branchId: r.branch_id }))
        .filter((p) => p.isActive !== false && p.isPublic !== false && p.isOnlineEnabled !== false && p.isAvailableOnline !== false);
    }
    products = products.filter((p) => p.trackStock === false || Number(p.stock || 0) > 0);
    return send(res, 200, { ok: true, storeId, products });
  }

  if (req.method === 'POST' && pathname === '/marketplace/orders') {
    const body = await readBody(req);
    const storeId = String(body.storeId || '').trim();
    if (!storeId) return send(res, 400, { ok: false, error: 'storeId is required.' });
    const items = Array.isArray(body.items) ? body.items : [];
    if (!items.length) return send(res, 400, { ok: false, error: 'Order must contain at least one item.' });
    const now = new Date().toISOString();
    const id = String(body.id || randomId('order'));
    db.prepare(`INSERT INTO online_orders (id, store_id, customer_user_id, customer_name, customer_phone, delivery_address, notes, status, items, delivery_fee, discount, payment_method, payment_status, assigned_driver_user_id, is_deleted, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, 'placed', ?, ?, ?, ?, 'unpaid', '', 0, ?, ?)`)
      .run(
        id,
        storeId,
        String(body.customerUserId || ''),
        String(body.customerName || ''),
        String(body.customerPhone || ''),
        String(body.deliveryAddress || ''),
        String(body.notes || ''),
        JSON.stringify(items),
        Number(body.deliveryFee || 0),
        Number(body.discount || 0),
        String(body.paymentMethod || 'cash_on_delivery'),
        now,
        now,
      );
    const order = db.prepare('SELECT * FROM online_orders WHERE id = ?').get(id);

    // Mirror the order as a sync event so the target store can pull it.
    const change = {
      id: `order-event-${id}`,
      storeId,
      branchId: String(body.branchId || 'main'),
      deviceId: 'marketplace-server',
      entityType: 'online_order',
      entityId: id,
      operation: 'upsert',
      payload: onlineOrderPayload(order),
      createdAt: now,
    };
    db.prepare(`INSERT OR IGNORE INTO sync_events (id, store_id, branch_id, device_id, entity_type, entity_id, operation, payload, created_at, received_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`)
      .run(change.id, change.storeId, change.branchId, change.deviceId, change.entityType, change.entityId, change.operation, JSON.stringify(change.payload), change.createdAt, now);
    upsertSnapshot({ storeId, branchId: change.branchId, entityType: 'online_order', entityId: id, operation: 'upsert', payload: change.payload, updatedAt: now });

    return send(res, 200, { ok: true, order: change.payload });
  }


  const statusMatch = pathname.match(/^\/marketplace\/orders\/([^/]+)\/status$/);
  if (req.method === 'POST' && statusMatch) {
    const orderId = decodeURIComponent(statusMatch[1]);
    const body = await readBody(req);
    const allowed = new Set(['placed', 'accepted', 'preparing', 'ready_for_delivery', 'assigned_to_driver', 'out_for_delivery', 'delivered', 'cancelled']);
    const status = String(body.status || '').trim();
    if (!allowed.has(status)) return send(res, 400, { ok: false, error: 'Invalid order status.' });
    const existing = db.prepare('SELECT * FROM online_orders WHERE id = ? AND is_deleted = 0 LIMIT 1').get(orderId);
    if (!existing) return send(res, 404, { ok: false, error: 'Order not found.' });
    const now = new Date().toISOString();
    db.prepare('UPDATE online_orders SET status = ?, updated_at = ? WHERE id = ?').run(status, now, orderId);
    const fresh = db.prepare('SELECT * FROM online_orders WHERE id = ?').get(orderId);
    const payload = onlineOrderPayload(fresh);
    const branchId = String(body.branchId || body.branch_id || 'main');
    const eventId = `order-status-${orderId}-${Date.now()}`;
    db.prepare(`INSERT OR IGNORE INTO sync_events (id, store_id, branch_id, device_id, entity_type, entity_id, operation, payload, created_at, received_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`)
      .run(eventId, payload.storeId, branchId, 'marketplace-server', 'online_order', orderId, 'upsert', JSON.stringify(payload), now, now);
    upsertSnapshot({ storeId: payload.storeId, branchId, entityType: 'online_order', entityId: orderId, operation: 'upsert', payload, updatedAt: now });
    return send(res, 200, { ok: true, order: payload });
  }

  if (req.method === 'GET' && pathname === '/marketplace/orders') {
    const customerUserId = String(url.searchParams.get('customerUserId') || url.searchParams.get('customer_user_id') || '').trim();
    const storeId = String(url.searchParams.get('storeId') || url.searchParams.get('store_id') || '').trim();
    let rows;
    if (customerUserId) {
      rows = db.prepare(`SELECT * FROM online_orders WHERE customer_user_id = ? AND is_deleted = 0 ORDER BY created_at DESC LIMIT 100`).all(customerUserId);
    } else if (storeId) {
      rows = db.prepare(`SELECT * FROM online_orders WHERE store_id = ? AND is_deleted = 0 ORDER BY created_at DESC LIMIT 100`).all(storeId);
    } else {
      rows = db.prepare(`SELECT * FROM online_orders WHERE is_deleted = 0 ORDER BY created_at DESC LIMIT 100`).all();
    }
    return send(res, 200, { ok: true, orders: rows.map(onlineOrderPayload) });
  }

  return send(res, 404, { ok: false, error: 'Marketplace endpoint not found.' });
}

function onlineOrderPayload(row) {
  return {
    id: row.id,
    storeId: row.store_id,
    customerUserId: row.customer_user_id || '',
    customerName: row.customer_name || '',
    customerPhone: row.customer_phone || '',
    deliveryAddress: row.delivery_address || '',
    notes: row.notes || '',
    status: row.status || 'placed',
    items: parseJson(row.items, []),
    deliveryFee: Number(row.delivery_fee || 0),
    discount: Number(row.discount || 0),
    paymentMethod: row.payment_method || 'cash_on_delivery',
    paymentStatus: row.payment_status || 'unpaid',
    assignedDriverUserId: row.assigned_driver_user_id || '',
    isDeleted: bool(row.is_deleted),
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}
