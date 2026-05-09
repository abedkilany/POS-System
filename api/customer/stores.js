
import { sql } from '../_db.js';
import { sendAuthError } from '../auth/_auth-utils.js';

export default async function handler(req, res) {
  if (req.method !== 'GET') return sendAuthError(res, 405, 'Method not allowed.');
  try {
    const rows = await sql`
      select id, name, owner_user_id, phone, address, description, is_online_enabled, subscription_plan, subscription_status, commission_rate, is_active, created_at, updated_at
      from platform_stores
      where is_active = true and is_online_enabled = true
      order by name asc
      limit 200
    `;
    return res.status(200).json({ ok: true, stores: rows.map(toPlatformStore) });
  } catch (error) {
    return sendAuthError(res, 500, error.message || String(error));
  }
}

function toPlatformStore(row) { return row && { id: row.id, name: row.name, ownerUserId: row.owner_user_id || '', phone: row.phone || '', address: row.address || '', description: row.description || '', isOnlineEnabled: row.is_online_enabled === true, subscriptionPlan: row.subscription_plan || 'trial', subscriptionStatus: row.subscription_status || 'pending_review', commissionRate: Number(row.commission_rate || 0), isActive: row.is_active !== false, createdAt: row.created_at, updatedAt: row.updated_at }; }
