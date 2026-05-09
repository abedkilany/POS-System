import { sql } from '../_db.js';
import { hashStoreToken, issueSessionToken, issueStoreToken, publicUser, sendAuthError } from '../auth/_auth-utils.js';

export default async function handler(req, res) {
  if (req.method !== 'POST') return sendAuthError(res, 405, 'Method not allowed.');
  try {
    const userId = String(req.body?.userId || '').trim();
    const storeName = String(req.body?.storeName || '').trim();
    const phone = String(req.body?.phone || '').trim();
    const address = String(req.body?.address || '').trim();
    if (!userId) return sendAuthError(res, 400, 'User is required.');
    if (!storeName) return sendAuthError(res, 400, 'Store name is required.');

    const users = await sql`select * from app_users where id = ${userId} and is_active = true limit 1`;
    if (!users.length) return sendAuthError(res, 404, 'Platform account not found.');
    const user = users[0];

    const now = new Date().toISOString();
    const storeId = `store_${Date.now()}_${cryptoRandom()}`;
    const token = issueStoreToken();
    const storeRows = await sql`
      insert into platform_stores (id, name, owner_user_id, phone, address, subscription_plan, subscription_status, is_online_enabled, is_active, store_token_hash, token_rotated_at, created_at, updated_at)
      values (${storeId}, ${storeName}, ${userId}, ${phone}, ${address}, 'trial', 'pending_review', false, true, ${hashStoreToken(token)}, ${now}, ${now}, ${now})
      returning *
    `;

    const memberId = `member_${Date.now()}_${cryptoRandom()}`;
    const memberRows = await sql`
      insert into store_members (id, store_id, user_id, role, permissions, is_active, created_at, updated_at)
      values (${memberId}, ${storeId}, ${userId}, 'owner', ${JSON.stringify([])}, true, ${now}, ${now})
      on conflict (store_id, user_id) do update set role = 'owner', is_active = true, updated_at = ${now}
      returning *
    `;

    const updatedRows = await sql`
      update app_users set account_type = 'merchant', role_id = 'store_owner', primary_store_id = ${storeId}, updated_at = ${now}
      where id = ${userId}
      returning *
    `;

    return res.status(200).json({
      ok: true,
      message: 'Store created centrally.',
      user: publicUser(updatedRows[0]),
      sessionToken: issueSessionToken(userId),
      platformStore: toPlatformStore(storeRows[0]),
      storeMember: toStoreMember(memberRows[0]),
      storeToken: token,
    });
  } catch (error) {
    return sendAuthError(res, 500, error.message || String(error));
  }
}

function cryptoRandom() { return Math.floor(Math.random() * 999999).toString().padStart(6, '0'); }
function toPlatformStore(row) { return row && { id: row.id, name: row.name, ownerUserId: row.owner_user_id || '', phone: row.phone || '', address: row.address || '', description: row.description || '', isOnlineEnabled: row.is_online_enabled === true, subscriptionPlan: row.subscription_plan || 'trial', subscriptionStatus: row.subscription_status || 'pending_review', commissionRate: Number(row.commission_rate || 0), isActive: row.is_active !== false, createdAt: row.created_at, updatedAt: row.updated_at }; }
function toStoreMember(row) { return row && { id: row.id, storeId: row.store_id, userId: row.user_id, role: row.role, permissions: Array.isArray(row.permissions) ? row.permissions : [], isActive: row.is_active !== false, createdAt: row.created_at, updatedAt: row.updated_at }; }
