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

function page(title, message, variant = 'success') {
  const isSuccess = variant === 'success';
  const badge = isSuccess ? 'Connected' : 'Action needed';
  const icon = isSuccess ? '&#10003;' : '!';
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
        --surface: #ffffff;
        --page: #f5f8fb;
        --success: #18a058;
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
        color: ${isSuccess ? '#0f6b3c' : '#8a4b00'};
        background: ${isSuccess ? '#e9f8ef' : '#fff4df'};
        border: 1px solid ${isSuccess ? '#bfe8cd' : '#f5d38b'};
        font-size: 13px;
        font-weight: 700;
      }
      .content {
        padding: 34px 32px 36px;
      }
      .status {
        width: 64px;
        height: 64px;
        display: grid;
        place-items: center;
        margin-bottom: 22px;
        border-radius: 20px;
        color: #fff;
        background: ${isSuccess ? 'linear-gradient(135deg, var(--success), #128048)' : 'linear-gradient(135deg, var(--warning), #b45309)'};
        font-size: 34px;
        font-weight: 900;
        box-shadow: 0 18px 38px ${isSuccess ? 'rgba(24, 160, 88, 0.25)' : 'rgba(217, 119, 6, 0.22)'};
      }
      h1 {
        margin: 0 0 14px;
        font-size: clamp(34px, 5vw, 54px);
        line-height: 1.02;
        letter-spacing: -0.02em;
      }
      p {
        max-width: 560px;
        margin: 0;
        color: var(--muted);
        font-size: 18px;
        line-height: 1.65;
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
        <div class="badge">${badge}</div>
      </div>
      <section class="content">
        <div class="status">${icon}</div>
        <h1>${title}</h1>
        <p>${message}</p>
        <div class="hint">You can safely close this window and return to Ventio. The app will continue automatically.</div>
      </section>
    </main>
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
    if (!state) return res.status(400).send(page('Connection failed', 'Missing Google state.', 'error'));

    const rows = await sql`
      select session_id
      from google_drive_oauth_sessions
      where state = ${state}
      limit 1
    `;
    if (!rows.length) return res.status(400).send(page('Connection failed', 'This Google session is no longer valid.', 'error'));
    const sessionId = rows[0].session_id;

    if (denied) {
      await sql`
        update google_drive_oauth_sessions
        set status = 'error', error = ${denied}, updated_at = now()
        where session_id = ${sessionId}
      `;
      return res.status(200).send(page('Connection cancelled', 'Google Drive access was not granted.', 'error'));
    }
    if (!code) {
      await sql`
        update google_drive_oauth_sessions
        set status = 'error', error = 'Missing authorization code.', updated_at = now()
        where session_id = ${sessionId}
      `;
      return res.status(400).send(page('Connection failed', 'Google did not return an authorization code.', 'error'));
    }

    const clientId = String(process.env.GOOGLE_DRIVE_WEB_CLIENT_ID || process.env.GOOGLE_DRIVE_CLIENT_ID || '').trim();
    const clientSecret = String(process.env.GOOGLE_DRIVE_WEB_CLIENT_SECRET || process.env.GOOGLE_DRIVE_CLIENT_SECRET || '').trim();
    if (!clientId || !clientSecret) {
      await sql`
        update google_drive_oauth_sessions
        set status = 'error', error = 'Google Drive OAuth server credentials are not configured.', updated_at = now()
        where session_id = ${sessionId}
      `;
      return res.status(500).send(page('Connection failed', 'Google Drive OAuth server credentials are not configured.', 'error'));
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
      return res.status(400).send(page('Connection failed', String(message), 'error'));
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
    return res.status(200).send(page('Google Drive connected', 'Your account is linked successfully. Ventio can now save automatic and manual backups to your Google Drive.'));
  } catch (error) {
    sendError(res, error);
  }
}
