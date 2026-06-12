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

function page(title, message) {
  return `<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <title>${title}</title>
    <style>
      body { font-family: Arial, sans-serif; margin: 48px; color: #1f2937; }
      .box { max-width: 640px; padding: 24px; border: 1px solid #d1d5db; border-radius: 12px; }
      h1 { margin-top: 0; }
      code { background: #f3f4f6; border-radius: 4px; padding: 2px 5px; }
    </style>
  </head>
  <body>
    <div class="box">
      <h1>${title}</h1>
      <p>${message}</p>
      <p>You can close this window and return to Ventio.</p>
    </div>
  </body>
</html>`;
}

export default async function handler(req, res) {
  try {
    if (req.method !== 'GET') return res.status(405).json({ ok: false, error: 'Method not allowed' });
    const sessionId = String(req.query.session_id || '').trim();
    if (!sessionId || !/^[a-zA-Z0-9_-]{24,160}$/.test(sessionId)) {
      return res.status(400).send('Invalid Google Drive session.');
    }

    await ensureTable();
    const clientId = String(process.env.GOOGLE_DRIVE_WEB_CLIENT_ID || process.env.GOOGLE_DRIVE_CLIENT_ID || '').trim();
    const clientSecret = String(process.env.GOOGLE_DRIVE_WEB_CLIENT_SECRET || process.env.GOOGLE_DRIVE_CLIENT_SECRET || '').trim();
    if (!clientId || !clientSecret) {
      await sql`
        insert into google_drive_oauth_sessions (session_id, state, status, error, updated_at)
        values (${sessionId}, 'missing-google-oauth-config', 'error', 'Google Drive is not configured on the server. Set GOOGLE_DRIVE_WEB_CLIENT_ID and GOOGLE_DRIVE_WEB_CLIENT_SECRET, then redeploy.', now())
        on conflict (session_id) do update
        set status = 'error',
            error = excluded.error,
            access_token = '',
            refresh_token = '',
            expires_at = null,
            updated_at = now()
      `;
      return res.status(500).send(page(
        'Google Drive is not configured',
        'The Ventio server is missing <code>GOOGLE_DRIVE_WEB_CLIENT_ID</code> or <code>GOOGLE_DRIVE_WEB_CLIENT_SECRET</code>. Add them to the server environment variables, redeploy, then try again.'
      ));
    }

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
