import { sql } from '../_db.js';
import { issueSessionToken, normalizeUsername, publicUser, sendAuthError, verifyPassword } from './_auth-utils.js';

export default async function handler(req, res) {
  if (req.method !== 'POST') return sendAuthError(res, 405, 'Method not allowed.');
  try {
    const username = normalizeUsername(req.body?.username);
    const password = String(req.body?.password || '').trim();
    if (!username || !password) return sendAuthError(res, 400, 'Username and password are required.');

    const rows = await sql`select * from app_users where username = ${username} and is_active = true limit 1`;
    if (!rows.length || !verifyPassword(password, rows[0].password_hash)) return sendAuthError(res, 401, 'Invalid username or password.');

    const user = rows[0];
    const now = new Date().toISOString();
    await sql`update app_users set last_login_at = ${now}, updated_at = ${now} where id = ${user.id}`;
    user.last_login_at = now;

    let platformStore = null;
    let storeMember = null;
    let customerProfile = null;
    let driverProfile = null;

    if (user.account_type === 'merchant' && user.primary_store_id) {
      const stores = await sql`select * from platform_stores where id = ${user.primary_store_id} limit 1`;
      if (stores.length) platformStore = toPlatformStore(stores[0]);
      const members = await sql`select * from store_members where store_id = ${user.primary_store_id} and user_id = ${user.id} limit 1`;
      if (members.length) storeMember = toStoreMember(members[0]);
    } else if (user.account_type === 'customer') {
      const rows = await sql`select * from customer_profiles where user_id = ${user.id} limit 1`;
      if (rows.length) customerProfile = toCustomerProfile(rows[0]);
    } else if (user.account_type === 'driver') {
      const rows = await sql`select * from driver_profiles where user_id = ${user.id} limit 1`;
      if (rows.length) driverProfile = toDriverProfile(rows[0]);
    }

    res.status(200).json({ ok: true, message: 'Logged in centrally.', user: publicUser(user), sessionToken: issueSessionToken(user.id), platformStore, storeMember, customerProfile, driverProfile });
  } catch (error) {
    return sendAuthError(res, 500, error.message || String(error));
  }
}

function toPlatformStore(row) { return row && { id: row.id, name: row.name, ownerUserId: row.owner_user_id || '', phone: row.phone || '', address: row.address || '', description: row.description || '', isOnlineEnabled: row.is_online_enabled === true, subscriptionPlan: row.subscription_plan || 'trial', subscriptionStatus: row.subscription_status || 'pending_review', commissionRate: Number(row.commission_rate || 0), isActive: row.is_active !== false, createdAt: row.created_at, updatedAt: row.updated_at }; }
function toStoreMember(row) { return row && { id: row.id, storeId: row.store_id, userId: row.user_id, role: row.role, permissions: Array.isArray(row.permissions) ? row.permissions : [], isActive: row.is_active !== false, createdAt: row.created_at, updatedAt: row.updated_at }; }
function toCustomerProfile(row) { return row && { userId: row.user_id, defaultAddress: row.default_address || '', phone: row.phone || '', createdAt: row.created_at, updatedAt: row.updated_at }; }
function toDriverProfile(row) { return row && { userId: row.user_id, phone: row.phone || '', zone: row.zone || '', isAvailable: row.is_available === true, createdAt: row.created_at, updatedAt: row.updated_at }; }
