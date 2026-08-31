import {
  accountTokenFromRequest,
  createAuthSession,
  findRefreshSession,
  revokeAuthSession,
  sql,
} from '../_db.js';

function sendError(res, error) {
  const status = Number(error?.statusCode || error?.status || 500);
  return res.status(status).json({ ok: false, error: error?.message || 'Request failed.' });
}

export default async function handler(req, res) {
  try {
    if (req.method !== 'GET' && req.method !== 'POST') {
      res.setHeader('Allow', 'GET, POST, OPTIONS');
      return res.status(405).json({ ok: false, error: 'Method not allowed.' });
    }

    let payload = await accountTokenFromRequest(req);
    let refreshSession = null;
    if (req.method === 'POST') {
      const body = req.body || {};
      const refreshToken = String(body.refreshToken || body.refresh_token || '').trim();
      refreshSession = await findRefreshSession(refreshToken);
      if (!refreshSession) {
        return res.status(401).json({ ok: false, error: 'Invalid or expired refresh token.' });
      }
      if (payload && payload.sessionId !== refreshSession.id) payload = null;
      await revokeAuthSession(refreshSession.id);
    }
    if (!payload) {
      if (!refreshSession) {
        return res.status(401).json({ ok: false, error: 'Invalid or missing account session.' });
      }
    }

    const accountId = String(refreshSession?.account_id || payload?.accountId || '');
    const rows = await sql`
      select a.id as account_id, a.username, a.namespace_slug, a.account_type,
             s.id as store_id, s.branch_id, s.slug as store_slug, s.name as store_name,
             sub.status as subscription_status, sub.trial_ends_at, sub.devices_limit, sub.direct_sync_enabled
      from app_accounts a
      left join app_stores s on s.owner_account_id = a.id and s.slug = a.namespace_slug
      left join app_subscriptions sub on sub.store_id = s.id
      where a.id = ${accountId}
      limit 1
    `;
    if (!rows.length) {
      return res.status(404).json({ ok: false, error: 'Account session was not found.' });
    }

    const row = rows[0];
    if (String(payload?.storeId || '') && String(row.store_id || '') !== String(payload.storeId || '')) {
      return res.status(403).json({ ok: false, error: 'This account is not allowed to access the requested store.' });
    }

    const isPlatformNamespace = String(row.namespace_slug || '') === 'ventio';
    const tokens = await createAuthSession({
      accountId: row.account_id,
      username: row.username,
      namespace: row.namespace_slug,
      storeId: row.store_id || '',
      branchId: row.branch_id || '',
      accountType: row.account_type || 'store_owner',
    });
    return res.status(200).json({
      ok: true,
      message: 'Online account session refreshed.',
      accountId: row.account_id,
      storeId: row.store_id || '',
      branchId: row.branch_id || '',
      username: row.username,
      storeSlug: row.store_slug || row.namespace_slug || '',
      storeName: row.store_name || '',
      loginName: `${row.username}@${row.namespace_slug}`,
      accountType: isPlatformNamespace ? 'platform_admin' : (row.account_type || 'store_owner'),
      subscriptionStatus: row.subscription_status || '',
      trialEndsAt: row.trial_ends_at ? new Date(row.trial_ends_at).toISOString() : null,
      devicesLimit: row.devices_limit == null ? null : Number(row.devices_limit),
      directSyncEnabled: row.direct_sync_enabled === true,
      adminToken: tokens.adminToken,
      accountToken: tokens.accountToken,
      refreshToken: tokens.refreshToken,
    });
  } catch (error) {
    return sendError(res, error);
  }
}
