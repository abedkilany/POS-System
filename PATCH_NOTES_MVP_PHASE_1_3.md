# MVP Phase 1-3 Patch Notes

This build starts moving the app toward the target marketplace model:

1. **Backend-first foundation**
   - Store create/link endpoints now require a central session token.
   - Session tokens have a 14-day expiry and server-side verification.
   - Public user responses no longer expose `passwordHash`.
   - Customer self-registration is now allowed for the online ordering flow.

2. **Clear roles and access boundaries**
   - `platform_user`, `merchant`, `customer`, `driver`, and `app_admin` are supported in the central schema.
   - Store-only operations verify active store membership.
   - Store order listing and status changes are limited to owner/manager/orders_staff.

3. **Online order MVP**
   - Added `/api/customer/stores` to list stores that are active and online-enabled.
   - Added `/api/orders`:
     - `POST` for customers to place an order.
     - `GET ?customer=me` for customers to view their orders.
     - `GET ?storeId=...` for store staff to view incoming orders.
   - Added `/api/orders/status` for store staff to update order status.
   - Added Flutter `OnlineOrderService` to call the new order APIs.
   - Added schema for `online_orders` with indexes and allowed status values.

## Important

This is still an MVP foundation, not a final production marketplace. The next phase should add:

- Real customer storefront UI.
- Product publishing API from store inventory to online catalog.
- Conflict policy for stock/price changes while offline.
- Push notifications for new orders and status changes.
- Admin dashboard for approving stores and monitoring order flow.
