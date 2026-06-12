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
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>${title}</title>
    <style>
      :root {
        color-scheme: light;
        --brand: #1f6f93;
        --brand-dark: #124f6d;
        --ink: #172033;
        --muted: #667085;
        --line: #d9e2ea;
        --page: #f5f8fb;
        --warning: #d97706;
      }
      * { box-sizing: border-box; }
      body {
        margin: 0;
        min-height: 100vh;
        display: grid;
        place-items: center;
        padding: 32px;
        color: var(--ink);
        font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        background:
          radial-gradient(circle at 20% 12%, rgba(31, 111, 147, 0.10), transparent 30%),
          linear-gradient(135deg, #f7fbfd 0%, var(--page) 100%);
      }
      .card {
        width: min(720px, 100%);
        overflow: hidden;
        border: 1px solid var(--line);
        border-radius: 28px;
        background: rgba(255, 255, 255, 0.94);
        box-shadow: 0 24px 70px rgba(23, 32, 51, 0.12);
      }
      .top {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 16px;
        padding: 28px 32px 0;
      }
      .brand {
        display: flex;
        align-items: center;
        gap: 12px;
        font-weight: 800;
        letter-spacing: 0.2px;
      }
      .brand img {
        width: 42px;
        height: 42px;
        border-radius: 12px;
        box-shadow: 0 8px 24px rgba(31, 111, 147, 0.20);
      }
      .brand-mark {
        width: 42px;
        height: 42px;
        display: none;
        place-items: center;
        border-radius: 12px;
        color: #fff;
        background: linear-gradient(135deg, var(--brand), var(--brand-dark));
        font-weight: 900;
      }
      .badge {
        border-radius: 999px;
        padding: 8px 12px;
        color: #8a4b00;
        background: #fff4df;
        border: 1px solid #f5d38b;
        font-size: 13px;
        font-weight: 700;
      }
      .content { padding: 34px 32px 36px; }
      .status {
        width: 64px;
        height: 64px;
        display: grid;
        place-items: center;
        margin-bottom: 22px;
        border-radius: 20px;
        color: #fff;
        background: linear-gradient(135deg, var(--warning), #b45309);
        font-size: 34px;
        font-weight: 900;
        box-shadow: 0 18px 38px rgba(217, 119, 6, 0.22);
      }
      h1 {
        margin: 0 0 14px;
        font-size: clamp(34px, 5vw, 54px);
        line-height: 1.02;
        letter-spacing: -0.02em;
      }
      p {
        max-width: 580px;
        margin: 0;
        color: var(--muted);
        font-size: 18px;
        line-height: 1.65;
      }
      code {
        background: #eef4f7;
        border: 1px solid #dce8ee;
        border-radius: 6px;
        padding: 2px 6px;
        color: #124f6d;
      }
      .hint {
        margin-top: 26px;
        padding: 16px 18px;
        border-radius: 16px;
        background: #f1f6f9;
        border: 1px solid #dde8ee;
        color: #405366;
        font-size: 15px;
      }
      @media (max-width: 560px) {
        body { padding: 18px; }
        .top { padding: 22px 22px 0; }
        .content { padding: 28px 22px 26px; }
      }
    </style>
  </head>
  <body>
    <main class="card">
      <div class="top">
        <div class="brand">
          <img src="/icons/Icon-192.png" alt="Ventio" onerror="this.style.display='none';this.nextElementSibling.style.display='grid';" />
          <span class="brand-mark">V</span>
          <span>Ventio</span>
        </div>
        <div class="badge">Action needed</div>
      </div>
      <section class="content">
        <div class="status">!</div>
        <h1>${title}</h1>
        <p>${message}</p>
        <div class="hint">You can close this window and return to Ventio after the setup is corrected.</div>
      </section>
    </main>
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
