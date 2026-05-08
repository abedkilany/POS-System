# Platform Foundation Patch

This build prepares the app to grow from a single-store POS into a marketplace-style platform.

## Added
- System roles:
  - `platform_admin`
  - `store_owner`
  - `store_staff`
  - `customer`
  - `driver`
- New permissions for platform administration, online orders, and delivery readiness.
- New models:
  - `PlatformStore`
  - `OnlineOrder`
  - `OnlineOrderItem`
- Local persistence keys:
  - `platform_stores_v1`
  - `online_orders_v1`
- Sync support for:
  - `platform_store`
  - `online_order`
- Backup/snapshot inclusion for platform stores and online orders.
- A basic `Platform` page showing stores, online orders, pending orders, and delivery readiness.
- Neon SQL foundation tables for platform stores and online orders.

## Important
This is a foundation build, not the final customer app or delivery app. The next step should separate the UI flows by role:
- Store dashboard
- Customer shopping experience
- Platform admin panel
- Driver/delivery workflow
