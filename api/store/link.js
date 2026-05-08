import { sql } from '../_db.js';
import { hashStoreToken, issueSessionToken, publicUser, sendAuthError } from '../auth/_auth-utils.js';

export default async function handler(req, res) {
  if (req.method !== 'POST') return sendAuthError(res, 405, 'Method not allowed.');
  try {
    const userId = String(req.body?.userId || '').trim();
    const storeId = String(req.body?.storeId || '').trim();
    const storeToken = String(req.body?.storeToken || '').trim();
    if (!userId || !storeId || !storeToken) return sendAuthError(res, 400, 'User, Store ID and Store Token are required.');

    const users = await sql`select * from app_users where id = ${userId} and is_active = true limit 1`;
    if (!users.length) return sendAuthError(res, 404, 'Platform account not found.');

    const stores = await sql`select * from platform_stores where id = ${storeId} and is_active = true limit 1`;
    if (!stores.length) return sendAuthError(res, 404, 'Store not found.');
    const store = stores[0];
    if (!store.store_token_hash || store.store_token_hash !== hashStoreToken(storeToken)) return sendAuthError(res, 403, 'Invalid Store ID or Store Token.');

    const now = new Date().toISOString();
    const existing = await sql`select * from store_members where store_id = ${storeId} and user_id = ${userId} limit 1`;
    let memberRows;
    if (existing.length) {
      memberRows = await sql`update store_members set is_active = true, updated_at = ${now} where store_id = ${storeId} and user_id = ${userId} returning *`;
    } else {
      memberRows = await sql`
        insert into store_members (id, store_id, user_id, role, permissions, is_active, created_at, updated_at)
        values (${`member_${Date.now()}_${cryptoRandom()}`}, ${storeId}, ${userId}, 'manager', ${JSON.stringify([])}, true, ${now}, ${now})
        returning *
      `;
    }

    const updatedRows = await sql`
      update app_users set account_type = 'merchant', role_id = 'store_owner', primary_store_id = ${storeId}, updated_at = ${now}
      where id = ${userId}
      returning *
    `;

    return res.status(200).json({
      ok: true,
      message: 'Store linked successfully.',
      user: publicUser(updatedRows[0]),
      sessionToken: issueSessionToken(userId),
      platformStore: toPlatformStore(store),
      storeMember: toStoreMember(memberRows[0]),
    });
  } catch (error) {
    return sendAuthError(res, 500, error.message || String(error));
  }
}

function cryptoRandom() { return Math.floor(Math.random() * 999999).toString().padStart(6, '0'); }
function toPlatformStore(row) { return row && { id: row.id, name: row.name, ownerUserId: row.owner_user_id || '', phone: row.phone || '', address: row.address || '', description: row.description || '', isOnlineEnabled: row.is_online_enabled === true, subscriptionPlan: row.subscription_plan || 'trial', subscriptionStatus: row.subscription_status || 'pending_review', commissionRate: Number(row.commission_rate || 0), isActive: row.is_active !== false, createdAt: row.created_at, updatedAt: row.updated_at }; }
function toStoreMember(row) { return row && { id: row.id, storeId: row.store_id, userId: row.user_id, role: row.role, permissions: Array.isArray(row.permissions) ? row.permissions : [], isActive: row.is_active !== false, createdAt: row.created_at, updatedAt: row.updated_at }; }
