import { neon } from '@neondatabase/serverless';

if (!process.env.DATABASE_URL) {
  throw new Error('DATABASE_URL is not configured. Add it in Vercel Environment Variables.');
}

export const sql = neon(process.env.DATABASE_URL);

export function assertSyncToken(req) {
  const expected = process.env.CLOUD_SYNC_TOKEN || '';
  if (!expected) {
    const err = new Error('CLOUD_SYNC_TOKEN is not configured. Refusing unauthenticated cloud sync.');
    err.statusCode = 500;
    throw err;
  }
  const header = req.headers.authorization || req.headers.Authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7).trim() : '';
  if (token !== expected) {
    const err = new Error('Invalid or missing cloud sync token.');
    err.statusCode = 401;
    throw err;
  }
}

export function assertStoreAllowed(storeId) {
  const allowed = (process.env.CLOUD_SYNC_STORE_ID || '').trim();
  if (allowed && storeId !== allowed) {
    const err = new Error('This sync token is not allowed to access the requested store_id.');
    err.statusCode = 403;
    throw err;
  }
}

export function sendError(res, error) {
  const status = error.statusCode || 500;
  res.status(status).json({ ok: false, error: error.message || String(error) });
}
