import { sql } from '../_db.js';
import { hashPassword, issueSessionToken, normalizeUsername, publicUser, PUBLIC_ACCOUNT_TYPES, roleForAccountType, sendAuthError } from './_auth-utils.js';

export default async function handler(req, res) {
  if (req.method !== 'POST') return sendAuthError(res, 405, 'Method not allowed.');
  try {
    const fullName = String(req.body?.fullName || '').trim();
    const username = normalizeUsername(req.body?.username);
    const password = String(req.body?.password || '').trim();
    const accountType = String(req.body?.accountType || 'platform_user').trim();
    const phone = String(req.body?.phone || '').trim();
    const email = String(req.body?.email || '').trim();

    if (!fullName || !username) return sendAuthError(res, 400, 'Name and username are required.');
    if (password.length < 4) return sendAuthError(res, 400, 'Password must be at least 4 characters.');
    if (!PUBLIC_ACCOUNT_TYPES.has(accountType)) return sendAuthError(res, 400, 'This account type cannot self-register.');

    const existing = await sql`select id from app_users where username = ${username} limit 1`;
    if (existing.length) return sendAuthError(res, 409, 'Username already exists.');

    const now = new Date().toISOString();
    const userId = `user_${Date.now()}_${cryptoRandom()}`;
    const roleId = roleForAccountType(accountType);
    let primaryStoreId = '';
    let platformStore = null;
    let storeMember = null;
    let customerProfile = null;
    let driverProfile = null;

    const inserted = await sql`
      insert into app_users (id, full_name, username, password_hash, account_type, role_id, phone, email, primary_store_id, is_active, is_system, created_at, updated_at)
      values (${userId}, ${fullName}, ${username}, ${hashPassword(password)}, ${accountType}, ${roleId}, ${phone}, ${email}, ${primaryStoreId}, true, false, ${now}, ${now})
      returning *
    `;

    if (accountType === 'customer') {
      const rows = await sql`insert into customer_profiles (user_id, default_address, phone, created_at, updated_at) values (${userId}, '', ${phone}, ${now}, ${now}) returning *`;
      customerProfile = toCustomerProfile(rows[0]);
    } else if (accountType === 'driver') {
      const rows = await sql`insert into driver_profiles (user_id, phone, zone, is_available, created_at, updated_at) values (${userId}, ${phone}, '', false, ${now}, ${now}) returning *`;
      driverProfile = toDriverProfile(rows[0]);
    }

    res.status(200).json({ ok: true, message: 'Account created centrally.', user: publicUser(inserted[0]), sessionToken: issueSessionToken(userId), platformStore, storeMember, customerProfile, driverProfile });
  } catch (error) {
    if (String(error?.message || '').includes('duplicate')) return sendAuthError(res, 409, 'Username already exists.');
    return sendAuthError(res, 500, error.message || String(error));
  }
}

function cryptoRandom() { return Math.floor(Math.random() * 999999).toString().padStart(6, '0'); }
function toPlatformStore(row) { return row && { id: row.id, name: row.name, ownerUserId: row.owner_user_id || '', phone: row.phone || '', address: row.address || '', description: row.description || '', isOnlineEnabled: row.is_online_enabled === true, subscriptionPlan: row.subscription_plan || 'trial', subscriptionStatus: row.subscription_status || 'pending_review', commissionRate: Number(row.commission_rate || 0), isActive: row.is_active !== false, createdAt: row.created_at, updatedAt: row.updated_at }; }
function toStoreMember(row) { return row && { id: row.id, storeId: row.store_id, userId: row.user_id, role: row.role, permissions: Array.isArray(row.permissions) ? row.permissions : [], isActive: row.is_active !== false, createdAt: row.created_at, updatedAt: row.updated_at }; }
function toCustomerProfile(row) { return row && { userId: row.user_id, defaultAddress: row.default_address || '', phone: row.phone || '', createdAt: row.created_at, updatedAt: row.updated_at }; }
function toDriverProfile(row) { return row && { userId: row.user_id, phone: row.phone || '', zone: row.zone || '', isAvailable: row.is_available === true, createdAt: row.created_at, updatedAt: row.updated_at }; }
