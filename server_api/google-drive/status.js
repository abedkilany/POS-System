import { sql, sendError } from '../_db.js';

async function ensureTable() {
  await sql`
    create table if not exists google_drive_oauth_sessions (
      session_id text primary key,
      state text not null,
      status text not null default 'pending',
      access_token text default '',
      refresh_token text default '',
      expires_at timestamptz,
      error text default '',
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now()
    )
  `;
}

export default async function handler(req, res) {
  try {
    if (req.method !== 'GET') return res.status(405).json({ ok: false, error: 'Method not allowed' });
    await ensureTable();
    const sessionId = String(req.query.session_id || '').trim();
    if (!sessionId || !/^[a-zA-Z0-9_-]{24,160}$/.test(sessionId)) {
      return res.status(400).json({ ok: false, error: 'Invalid Google Drive session.' });
    }
    const rows = await sql`
      select status, access_token, refresh_token, expires_at, error
      from google_drive_oauth_sessions
      where session_id = ${sessionId}
      limit 1
    `;
    if (!rows.length) return res.status(404).json({ ok: false, error: 'Google Drive session not found.' });
    const row = rows[0];
    if (row.status === 'complete') {
      await sql`delete from google_drive_oauth_sessions where session_id = ${sessionId}`;
      return res.status(200).json({
        ok: true,
        status: 'complete',
        accessToken: row.access_token || '',
        refreshToken: row.refresh_token || '',
        accessTokenExpiresAt: row.expires_at ? new Date(row.expires_at).toISOString() : '',
      });
    }
    if (row.status === 'error') {
      await sql`delete from google_drive_oauth_sessions where session_id = ${sessionId}`;
      return res.status(200).json({
        ok: false,
        status: 'error',
        error: row.error || 'Google Drive connection failed.',
      });
    }
    return res.status(200).json({ ok: true, status: 'pending' });
  } catch (error) {
    sendError(res, error);
  }
}
