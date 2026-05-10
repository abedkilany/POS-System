# Platform Account + Store Binding v4

## What changed

This version separates the identities more clearly:

- Platform account: central login only. Registration asks for full name, username, phone, email, and password.
- Store: created after login from inside the platform account.
- Store ID + Store Token: generated when a store is created and used to link additional devices.
- Device identity: local-only device role and sync mode selection after creating/linking a store.
- Store internal users: remain inside the store permissions area for cashier/manager/supervisor roles.

## New user flow

1. Open app.
2. Register or login with platform account.
3. If no store is linked, user sees the setup page.
4. User can:
   - Create a new store and receive Store ID + Store Token.
   - Link an existing store using Store ID + Store Token.
5. User chooses device role and sync mode:
   - Host / Client / Standalone
   - Local only / LAN / Online / Hybrid
6. After linking, the normal store dashboard opens.

## UI fix

The desktop side navigation rail is now wrapped in a scroll view with a scrollbar, so lower icons can be reached on smaller screens.

## New API endpoints

- POST /api/store/create
- POST /api/store/link

## Database update

Run `database/neon_central_auth_schema.sql` again in Neon. It now adds:

- account_type = platform_user
- platform_stores.store_token_hash
- platform_stores.token_rotated_at

## Important

The Store Token is shown when the store is created. Save it, because it is used to link new devices. Later we can add a regenerate-token button in store settings.
