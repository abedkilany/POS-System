
import { sql } from '../_db.js';
import { requireStoreAccess, sendAuthError } from '../auth/_auth-utils.js';

const ALLOWED_STATUSES = new Set(['placed','accepted','preparing','ready_for_delivery','out_for_delivery','delivered','cancelled']);

export default async function handler(req, res) {
  if (req.method !== 'PATCH' && req.method !== 'POST') return sendAuthError(res, 405, 'Method not allowed.');
  try {
    const orderId = String(req.body?.orderId || '').trim();
    const status = String(req.body?.status || '').trim();
    if (!orderId) return sendAuthError(res, 400, 'orderId is required.');
    if (!ALLOWED_STATUSES.has(status)) return sendAuthError(res, 400, 'Unsupported order status.');
    const orders = await sql`select * from online_orders where id = ${orderId} and is_deleted = false limit 1`;
    if (!orders.length) return sendAuthError(res, 404, 'Order not found.');
    await requireStoreAccess(req, sql, orders[0].store_id, ['owner','manager','orders_staff']);
    const now = new Date().toISOString();
    const rows = await sql`update online_orders set status = ${status}, updated_at = ${now} where id = ${orderId} returning *`;
    return res.status(200).json({ ok: true, message: 'Order status updated.', order: toOrder(rows[0]) });
  } catch (error) {
    return sendAuthError(res, error.statusCode || 500, error.message || String(error));
  }
}

function toOrder(row) { return { id: row.id, storeId: row.store_id, customerUserId: row.customer_user_id || '', customerName: row.customer_name || '', customerPhone: row.customer_phone || '', deliveryAddress: row.delivery_address || '', notes: row.notes || '', status: row.status || 'placed', items: Array.isArray(row.items) ? row.items : [], deliveryFee: Number(row.delivery_fee || 0), discount: Number(row.discount || 0), paymentMethod: row.payment_method || 'cash_on_delivery', paymentStatus: row.payment_status || 'unpaid', assignedDriverUserId: row.assigned_driver_user_id || '', isDeleted: row.is_deleted === true, createdAt: row.created_at, updatedAt: row.updated_at }; }
