import { neon } from '@neondatabase/serverless';

if (!process.env.DATABASE_URL) {
  throw new Error('DATABASE_URL is not configured. Add it in Vercel Environment Variables.');
}

export const sql = neon(process.env.DATABASE_URL);

export function assertSyncToken(req) {
  const expected = process.env.CLOUD_SYNC_TOKEN || '';
  if (!expected) return;
  const header = req.headers.authorization || req.headers.Authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7).trim() : '';
  if (token !== expected) {
    const err = new Error('Invalid or missing cloud sync token.');
    err.statusCode = 401;
    throw err;
  }
}

export function sendError(res, error) {
  const status = error.statusCode || 500;
  res.status(status).json({ ok: false, error: error.message || String(error) });
}
