
import { sql } from '../_db.js';
import { requireAuth, requireStoreAccess, sendAuthError } from '../auth/_auth-utils.js';

const PUBLIC_ORDER_STATUSES = new Set(['placed','accepted','preparing','ready_for_delivery','out_for_delivery','delivered','cancelled']);

export default async function handler(req, res) {
  try {
    if (req.method === 'GET') return listOrders(req, res);
    if (req.method === 'POST') return createOrder(req, res);
    return sendAuthError(res, 405, 'Method not allowed.');
  } catch (error) {
    return sendAuthError(res, error.statusCode || 500, error.message || String(error));
  }
}

async function listOrders(req, res) {
  const storeId = String(req.query.storeId || req.query.store_id || '').trim();
  const customerOnly = String(req.query.customer || '') === 'me';
  const user = await requireAuth(req, sql);
  let rows;
  if (customerOnly || user.account_type === 'customer') {
    rows = await sql`select * from online_orders where customer_user_id = ${user.id} and is_deleted = false order by created_at desc limit 200`;
  } else {
    if (!storeId) return sendAuthError(res, 400, 'storeId is required.');
    await requireStoreAccess(req, sql, storeId, ['owner','manager','orders_staff']);
    rows = await sql`select * from online_orders where store_id = ${storeId} and is_deleted = false order by created_at desc limit 300`;
  }
  return res.status(200).json({ ok: true, orders: rows.map(toOrder) });
}

async function createOrder(req, res) {
  const user = await requireAuth(req, sql);
  const storeId = String(req.body?.storeId || '').trim();
  const customerName = String(req.body?.customerName || user.full_name || '').trim();
  const customerPhone = String(req.body?.customerPhone || user.phone || '').trim();
  const deliveryAddress = String(req.body?.deliveryAddress || '').trim();
  const notes = String(req.body?.notes || '').trim();
  const items = Array.isArray(req.body?.items) ? req.body.items : [];
  if (!storeId) return sendAuthError(res, 400, 'storeId is required.');
  if (!items.length) return sendAuthError(res, 400, 'Order items are required.');
  const stores = await sql`select id from platform_stores where id = ${storeId} and is_active = true and is_online_enabled = true limit 1`;
  if (!stores.length) return sendAuthError(res, 404, 'Store is not available online.');
  const cleanItems = items.map((item) => ({
    productId: String(item.productId || item.product_id || '').trim(),
    productName: String(item.productName || item.product_name || '').trim(),
    unitPrice: Number(item.unitPrice || item.unit_price || 0),
    quantity: Math.max(1, Number.parseInt(item.quantity || 1, 10)),
  })).filter((item) => item.productId && item.productName && Number.isFinite(item.unitPrice));
  if (!cleanItems.length) return sendAuthError(res, 400, 'Valid order items are required.');
  const now = new Date().toISOString();
  const orderId = `ord_${Date.now()}_${Math.floor(Math.random() * 999999).toString().padStart(6, '0')}`;
  const rows = await sql`
    insert into online_orders (id, store_id, customer_user_id, customer_name, customer_phone, delivery_address, notes, status, items, delivery_fee, discount, payment_method, payment_status, created_at, updated_at)
    values (${orderId}, ${storeId}, ${user.id}, ${customerName}, ${customerPhone}, ${deliveryAddress}, ${notes}, 'placed', ${JSON.stringify(cleanItems)}, ${Number(req.body?.deliveryFee || 0)}, ${Number(req.body?.discount || 0)}, ${String(req.body?.paymentMethod || 'cash_on_delivery')}, 'unpaid', ${now}, ${now})
    returning *
  `;
  return res.status(201).json({ ok: true, message: 'Order placed.', order: toOrder(rows[0]) });
}

function toOrder(row) {
  return {
    id: row.id,
    storeId: row.store_id,
    customerUserId: row.customer_user_id || '',
    customerName: row.customer_name || '',
    customerPhone: row.customer_phone || '',
    deliveryAddress: row.delivery_address || '',
    notes: row.notes || '',
    status: row.status || 'placed',
    items: Array.isArray(row.items) ? row.items : [],
    deliveryFee: Number(row.delivery_fee || 0),
    discount: Number(row.discount || 0),
    paymentMethod: row.payment_method || 'cash_on_delivery',
    paymentStatus: row.payment_status || 'unpaid',
    assignedDriverUserId: row.assigned_driver_user_id || '',
    isDeleted: row.is_deleted === true,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}
