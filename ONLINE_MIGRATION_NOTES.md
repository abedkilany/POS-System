# Online migration notes

This copy includes the first production-oriented changes needed before running the POS as a website.

## What changed

1. `LocalDatabaseService` no longer imports `dart:io`, so it can compile for Flutter Web.
2. LAN sync was split with conditional exports:
   - `lan_sync_service_io.dart` keeps the current Windows/Android LAN host/client behavior.
   - `lan_sync_service_stub.dart` is used on Web and safely disables LAN sync.
3. `CloudSyncService` now has a real HTTP contract instead of a placeholder.
4. `vercel-api/` was added as a starter Next.js API for Vercel + Neon/PostgreSQL.
5. `http` was added to Flutter dependencies.

## Flutter Web commands

```bash
flutter pub get
flutter build web
```

If you deploy the Flutter frontend to Vercel, set it up as a static build and publish `build/web`.

## API commands

```bash
cd vercel-api
npm install
cp .env.example .env
npx prisma generate
npx prisma migrate dev --name init
npm run dev
```

For Vercel production, add these environment variables:

```txt
DATABASE_URL
JWT_SECRET
```

## API contract used by Flutter

```txt
GET  /api/health
POST /api/sync/push
GET  /api/sync/pull?since=2026-05-03T00:00:00.000Z
```

The Flutter app should never connect directly to Neon. It should call the Vercel API over HTTPS.

## Important remaining work

This is not yet a complete marketplace backend. The next tasks are:

1. Add `/api/auth/register` and `/api/auth/login`.
2. Add store onboarding and role management.
3. Store the Cloud API URL/token in app settings.
4. Add a Cloud Sync button/status screen in Flutter settings.
5. Add server-side validation for every entity payload.
6. Add conflict strategy per entity type.
7. Remove or force-change the default admin credentials before production.
