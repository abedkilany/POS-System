# Auth + Multi-role Platform Foundation v2

## Added
- Login-first flow remains the app entry point.
- Public signup flow for:
  - Customer
  - Merchant / store owner
  - Delivery driver
- App admin is intentionally not available in public signup.
- `AppUser` now includes `accountType`, phone, email, and `primaryStoreId`.
- New platform data models:
  - `StoreMember`
  - `StoreMemberRole`
  - `CustomerProfile`
  - `DriverProfile`
- Merchant signup automatically creates:
  - Platform store
  - Owner store membership
  - Trial/pending subscription status
- Account routing after login:
  - Customer -> customer home foundation
  - Driver -> delivery foundation screen
  - Merchant/Admin -> store management shell
- Platform page now shows user and store membership overview.
- Backup/snapshot payload now includes store members and customer/driver profiles.
- Neon SQL now includes platform auth/store-membership/profile tables.

## Notes
- This is still a foundation layer, not a full production auth server.
- Password hashing is still local-app style and should be replaced with server-side auth/JWT before public launch.
- Next recommended step: build online ordering flow for customers and order management for merchants.
