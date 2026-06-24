import { sendError } from '../_db.js';

export default async function handler(req, res) {
  try {
    if (req.method !== 'POST') return res.status(405).json({ ok: false, error: 'Method not allowed' });
    const clientId = String(process.env.GOOGLE_DRIVE_WEB_CLIENT_ID || process.env.GOOGLE_DRIVE_CLIENT_ID || '').trim();
    const clientSecret = String(process.env.GOOGLE_DRIVE_WEB_CLIENT_SECRET || process.env.GOOGLE_DRIVE_CLIENT_SECRET || '').trim();
    if (!clientId || !clientSecret) {
      return res.status(500).json({ ok: false, error: 'Google Drive OAuth server credentials are not configured.' });
    }
    const refreshToken = String(req.body?.refreshToken || req.body?.refresh_token || '').trim();
    if (!refreshToken) return res.status(400).json({ ok: false, error: 'refreshToken is required.' });

    const tokenResponse = await fetch('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        client_id: clientId,
        client_secret: clientSecret,
        refresh_token: refreshToken,
        grant_type: 'refresh_token',
      }),
    });
    const token = await tokenResponse.json();
    if (!tokenResponse.ok) {
      return res.status(400).json({
        ok: false,
        error: token.error_description || token.error || 'Google Drive token refresh failed.',
      });
    }
    const expiresIn = Number(token.expires_in || 3600);
    return res.status(200).json({
      ok: true,
      accessToken: token.access_token || '',
      accessTokenExpiresAt: new Date(Date.now() + expiresIn * 1000).toISOString(),
    });
  } catch (error) {
    sendError(res, error);
  }
}
