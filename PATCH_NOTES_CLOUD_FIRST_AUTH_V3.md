# Cloud-first Authentication Foundation v3

This patch makes the central server / Neon database the source of truth for account names and identities.

## Added

- New Flutter service: `lib/core/services/central_auth_service.dart`
- New Vercel API endpoints:
  - `POST /api/auth/register`
  - `POST /api/auth/login`
- New Neon schema helper:
  - `database/neon_central_auth_schema.sql`

## Behavior change

- Public signup now attempts to create the account on the central API first.
- The local database only stores the returned user/session/profile as a local cache.
- If central signup fails or is not configured, account creation is blocked to avoid duplicate usernames across stores/customers/drivers.
- Login checks the central API first, then falls back to local login for existing/offline admin users.

## Central records created during signup

### Customer

- `app_users`
- `customer_profiles`

### Merchant

- `app_users`
- `platform_stores`
- `store_members` with role `owner`

### Driver

- `app_users`
- `driver_profiles`

## Required setup

1. Run `database/neon_central_auth_schema.sql` in Neon.
2. Deploy the app/API to Vercel.
3. Configure environment variables:
   - `DATABASE_URL`
   - `CLOUD_SYNC_TOKEN`
   - optional: `AUTH_SESSION_SECRET`
4. In desktop/mobile builds, set the Cloud API URL in settings before public signup.

## Security notes

- App admin accounts are still not allowed through public signup.
- Password hashes use the existing app-compatible salted SHA-256 loop format.
- This is a foundation layer. For production, the next step should add session verification middleware and per-route authorization for platform/admin/order APIs.
