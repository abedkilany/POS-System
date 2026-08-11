import {
  accountTokenFromRequest,
  findRefreshSession,
  revokeAuthSession,
  sendError,
} from '../_db.js';

export default async function handler(req, res) {
  try {
    if (req.method !== 'POST') {
      res.setHeader('Allow', 'POST, OPTIONS');
      return res.status(405).json({ ok: false, error: 'Method not allowed.' });
    }

    const payload = await accountTokenFromRequest(req);
    const body = req.body || {};
    const refreshSession = await findRefreshSession(
      body.refreshToken || body.refresh_token,
    );
    const sessionId = payload?.sessionId || refreshSession?.id;
    if (sessionId) await revokeAuthSession(sessionId);

    return res.status(200).json({ ok: true, message: 'Session revoked.' });
  } catch (error) {
    return sendError(res, error);
  }
}
