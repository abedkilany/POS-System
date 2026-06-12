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
      .box { max-width: 560px; padding: 24px; border: 1px solid #d1d5db; border-radius: 12px; }
      h1 { margin-top: 0; }
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
    if (req.method !== 'GET') return res.status(405).send('Method not allowed');
    await ensureTable();
    const state = String(req.query.state || '').trim();
    const code = String(req.query.code || '').trim();
    const denied = String(req.query.error || '').trim();
    if (!state) return res.status(400).send(page('Connection failed', 'Missing Google state.'));

    const rows = await sql`
      select session_id
      from google_drive_oauth_sessions
      where state = ${state}
      limit 1
    `;
    if (!rows.length) return res.status(400).send(page('Connection failed', 'This Google session is no longer valid.'));
    const sessionId = rows[0].session_id;

    if (denied) {
      await sql`
        update google_drive_oauth_sessions
        set status = 'error', error = ${denied}, updated_at = now()
        where session_id = ${sessionId}
      `;
      return res.status(200).send(page('Connection cancelled', 'Google Drive access was not granted.'));
    }
    if (!code) {
      await sql`
        update google_drive_oauth_sessions
        set status = 'error', error = 'Missing authorization code.', updated_at = now()
        where session_id = ${sessionId}
      `;
      return res.status(400).send(page('Connection failed', 'Google did not return an authorization code.'));
    }

    const clientId = String(process.env.GOOGLE_DRIVE_WEB_CLIENT_ID || process.env.GOOGLE_DRIVE_CLIENT_ID || '').trim();
    const clientSecret = String(process.env.GOOGLE_DRIVE_WEB_CLIENT_SECRET || process.env.GOOGLE_DRIVE_CLIENT_SECRET || '').trim();
    if (!clientId || !clientSecret) {
      await sql`
        update google_drive_oauth_sessions
        set status = 'error', error = 'Google Drive OAuth server credentials are not configured.', updated_at = now()
        where session_id = ${sessionId}
      `;
      return res.status(500).send(page('Connection failed', 'Google Drive OAuth server credentials are not configured.'));
    }

    const redirectUri = `${apiBaseUrl(req)}/api/google-drive/callback`;
    const tokenResponse = await fetch('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        client_id: clientId,
        client_secret: clientSecret,
        code,
        grant_type: 'authorization_code',
        redirect_uri: redirectUri,
      }),
    });
    const token = await tokenResponse.json();
    if (!tokenResponse.ok) {
      const message = token.error_description || token.error || 'Google token exchange failed.';
      await sql`
        update google_drive_oauth_sessions
        set status = 'error', error = ${String(message)}, updated_at = now()
        where session_id = ${sessionId}
      `;
      return res.status(400).send(page('Connection failed', String(message)));
    }

    const expiresIn = Number(token.expires_in || 3600);
    await sql`
      update google_drive_oauth_sessions
      set status = 'complete',
          access_token = ${String(token.access_token || '')},
          refresh_token = ${String(token.refresh_token || '')},
          expires_at = now() + (${String(expiresIn)} || ' seconds')::interval,
          error = '',
          updated_at = now()
      where session_id = ${sessionId}
    `;
    return res.status(200).send(page('Google Drive connected', 'Ventio can now save backups to your Google Drive.'));
  } catch (error) {
    sendError(res, error);
  }
}
