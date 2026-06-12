import crypto from 'crypto';
import { sql, sendError } from '../_db.js';

const scope = 'https://www.googleapis.com/auth/drive.file';

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

function apiBaseUrl(req) {
  const configured = String(process.env.PUBLIC_API_BASE_URL || process.env.VERCEL_URL || '').trim();
  if (configured) {
    return configured.startsWith('http') ? configured.replace(/\/+$/, '') : `https://${configured.replace(/\/+$/, '')}`;
  }
  const proto = String(req.headers['x-forwarded-proto'] || 'https').split(',')[0].trim();
  const host = String(req.headers.host || '').trim();
  return `${proto}://${host}`;
}

export default async function handler(req, res) {
  try {
    if (req.method !== 'GET') return res.status(405).json({ ok: false, error: 'Method not allowed' });
    const clientId = String(process.env.GOOGLE_DRIVE_WEB_CLIENT_ID || process.env.GOOGLE_DRIVE_CLIENT_ID || '').trim();
    if (!clientId) return res.status(500).send('Google Drive OAuth client is not configured.');

    const sessionId = String(req.query.session_id || '').trim();
    if (!sessionId || !/^[a-zA-Z0-9_-]{24,160}$/.test(sessionId)) {
      return res.status(400).send('Invalid Google Drive session.');
    }

    await ensureTable();
    const state = crypto.randomBytes(24).toString('base64url');
    await sql`
      insert into google_drive_oauth_sessions (session_id, state, status, updated_at)
      values (${sessionId}, ${state}, 'pending', now())
      on conflict (session_id) do update
      set state = excluded.state,
          status = 'pending',
          access_token = '',
          refresh_token = '',
          expires_at = null,
          error = '',
          updated_at = now()
    `;

    const redirectUri = `${apiBaseUrl(req)}/api/google-drive/callback`;
    const authUrl = new URL('https://accounts.google.com/o/oauth2/v2/auth');
    authUrl.searchParams.set('client_id', clientId);
    authUrl.searchParams.set('redirect_uri', redirectUri);
    authUrl.searchParams.set('response_type', 'code');
    authUrl.searchParams.set('scope', scope);
    authUrl.searchParams.set('access_type', 'offline');
    authUrl.searchParams.set('prompt', 'consent');
    authUrl.searchParams.set('state', state);
    res.setHeader('Location', authUrl.toString());
    return res.status(302).end();
  } catch (error) {
    sendError(res, error);
  }
}
